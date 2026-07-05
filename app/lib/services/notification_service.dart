import 'package:flutter/foundation.dart' show kIsWeb;
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
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Returns true if a reminder was scheduled, false if unsupported (web)
  /// or the contest starts too soon.
  Future<bool> scheduleContestReminder(
    Contest contest, {
    Duration before = const Duration(minutes: 30),
  }) async {
    if (kIsWeb) return false;
    final when = contest.start.subtract(before);
    if (when.isBefore(DateTime.now())) return false;

    await _plugin.zonedSchedule(
      contest.id.hashCode,
      '${contest.name} starts soon!',
      '${contest.platform} contest begins in ${before.inMinutes} minutes.',
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'contests',
          'Contest reminders',
          channelDescription: 'Reminders before programming contests start',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    return true;
  }
}
