import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

/// Pushes streak / weekly-progress / next-reminder data to the Android
/// home-screen widget (`CodeTrackWidgetProvider`, see app/README.md for the
/// native setup). Every method no-ops on web and swallows errors - widget
/// sync must never break the app, including when the native side isn't set
/// up yet.
class WidgetSync {
  static const _androidProvider = 'CodeTrackWidgetProvider';

  /// Called by the Dashboard after every refresh.
  static Future<void> pushStats({
    required int streak,
    required int solvedThisWeek,
    required int weeklyGoal,
  }) async {
    if (kIsWeb) return;
    try {
      final pct = weeklyGoal > 0
          ? ((solvedThisWeek / weeklyGoal) * 100).round().clamp(0, 100)
          : 0;
      await HomeWidget.saveWidgetData<String>(
        'streak_text',
        streak == 1 ? '1 day' : '$streak days',
      );
      await HomeWidget.saveWidgetData<String>(
        'progress_text',
        '$solvedThisWeek / $weeklyGoal solved',
      );
      await HomeWidget.saveWidgetData<int>('progress_pct', pct);
      await _update();
    } catch (_) {
      // Native side missing or plugin unavailable - ignore.
    }
  }

  /// Called whenever reminders change (set / cancel / prune) and after
  /// dashboard refreshes. [reminders] entries follow AppStore.loadReminders():
  /// `{ notifId, contestName, platform, startMs, notifyAtMs }`.
  static Future<void> pushNextReminder(
      List<Map<String, dynamic>> reminders) async {
    if (kIsWeb) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final upcoming = reminders
          .where((r) => (r['notifyAtMs'] as num) > now)
          .toList()
        ..sort((a, b) =>
            (a['notifyAtMs'] as num).compareTo(b['notifyAtMs'] as num));
      String text;
      if (upcoming.isEmpty) {
        text = 'No reminders set';
      } else {
        final next = upcoming.first;
        final at = DateTime.fromMillisecondsSinceEpoch(
            (next['notifyAtMs'] as num).toInt());
        text =
            '${next['contestName']} \u00B7 ${DateFormat('EEE h:mm a').format(at)}';
      }
      await HomeWidget.saveWidgetData<String>('reminder_text', text);
      await _update();
    } catch (_) {
      // Native side missing or plugin unavailable - ignore.
    }
  }

  static Future<void> _update() => HomeWidget.updateWidget(
        name: _androidProvider,
        androidName: _androidProvider,
      );
}
