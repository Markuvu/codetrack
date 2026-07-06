import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/contest.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (kIsWeb) return; // local notifications are not supported on web
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    // Android 12+: exact alarms need a user grant (Settings -> Alarms &
    // reminders). Best-effort - scheduling falls back to inexact when denied.
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {
      // Older plugin/OS combinations may not support the request; inexact
      // scheduling still works.
    }
  }

  /// Stable notification id for a contest + lead-time combination, so the
  /// same reminder can be replaced or cancelled later.
  int reminderId(Contest contest, Duration before) =>
      ('${contest.id}@${before.inMinutes}').hashCode & 0x7fffffff;

  String _leadText(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
    if (d.inHours >= 1) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    return '${d.inMinutes} minutes';
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'contests',
      'Contest reminders',
      channelDescription: 'Reminders before programming contests start',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Schedules a reminder. Returns the notification id, or null when
  /// unsupported (web) or the notify time is already in the past.
  ///
  /// Tries an **exact** alarm first (fires at the precise minute even in
  /// Doze); falls back to inexact when the exact-alarm permission is denied.
  /// With `RECEIVE_BOOT_COMPLETED` declared in the Android manifest (see
  /// app/README.md), the plugin re-registers scheduled notifications after a
  /// reboot, so reminders survive phone restarts.
  Future<int?> scheduleContestReminder(
    Contest contest, {
    Duration before = const Duration(minutes: 30),
  }) async {
    if (kIsWeb) return null;
    final when = contest.start.subtract(before);
    if (when.isBefore(DateTime.now())) return null;

    final id = reminderId(contest, before);
    final title = '${contest.name} starts soon!';
    final body = '${contest.platform} contest begins in ${_leadText(before)}.';
    final at = tz.TZDateTime.from(when, tz.local);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        at,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException {
      // Exact alarms not permitted on this device - schedule inexactly
      // (may fire a few minutes late under Doze, but never silently fails).
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        at,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    return id;
  }

  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id);
  }
}
