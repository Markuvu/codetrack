package com.example.codetrack

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * CodeTrack home-screen widget: a ViewFlipper that auto-cycles between the
 * current streak, weekly progress and the next contest reminder with slide
 * transitions. Data is written from Dart via the home_widget plugin
 * (lib/services/widget_sync.dart) whenever the dashboard refreshes or
 * reminders change.
 *
 * NOTE: if your applicationId / namespace is not com.example.codetrack,
 * move this file into your package folder (next to MainActivity.kt) and
 * change the package line above to match.
 */
class CodeTrackWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.codetrack_widget).apply {
                // Pane 1: streak
                setTextViewText(
                    R.id.streak_value,
                    prefs.getString("streak_text", "0 days")
                )
                setTextViewText(
                    R.id.streak_sub,
                    prefs.getString("streak_sub", "Solve a problem to start one")
                )
                // Pane 2: weekly progress
                setTextViewText(
                    R.id.progress_value,
                    prefs.getString("progress_text", "0 / 50 \u00B7 0%")
                )
                setProgressBar(
                    R.id.progress_bar,
                    100,
                    prefs.getInt("progress_pct", 0),
                    false
                )
                // Pane 3: next reminder (platform + notify time)
                setTextViewText(
                    R.id.reminder_value,
                    prefs.getString("reminder_platform", "No reminders")
                )
                setTextViewText(
                    R.id.reminder_sub,
                    prefs.getString("reminder_time", "Tap a contest bell to set one")
                )
            }

            // Tapping the widget opens the app.
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pending = PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
