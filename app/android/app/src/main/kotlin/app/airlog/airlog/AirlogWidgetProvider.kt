package app.airlog.airlog

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate

/**
 * Dark home-screen widget: Recovery %, Strain, Sleep. Renders the snapshot
 * that lib/data/services/widget/widget_sink.dart writes through home_widget
 * after every recompute (keys in WidgetKeys). No network, no Dart here.
 * Tapping opens the app.
 * Pattern follows OpenStrap/edge OpenStrapWidgetProvider.kt (MIT, see
 * third_party/edge/LICENSE); layout and copy are ours.
 */
class AirlogWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, render(context, widgetData))
        }
    }

    private fun num(prefs: SharedPreferences, key: String): Long? =
        (prefs.all[key] as? Number)?.toLong()

    private fun render(context: Context, prefs: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.airlog_widget)
        val recovery = num(prefs, "airlog_recovery") ?: -1L
        val zone = prefs.getString("airlog_zone", "none") ?: "none"
        val strain = prefs.getString("airlog_strain", "–") ?: "–"
        val sleep = prefs.getString("airlog_sleep", "–") ?: "–"
        val demo = prefs.getBoolean("airlog_demo", false)
        // QA-08: the day shown isn't today (nothing for today has arrived):
        // label it, never pass yesterday's numbers off as today's. The flag
        // is written when the app last ran; the widget re-renders every
        // 30 min, so it also checks the date itself (the app may not have
        // run since midnight).
        val date = prefs.getString("airlog_date", "") ?: ""
        val stale = prefs.getBoolean("airlog_stale", false) ||
            (date.isNotEmpty() && date != LocalDate.now().toString())

        views.setTextViewText(R.id.widget_recovery, if (recovery >= 0) "$recovery%" else "–")
        views.setTextColor(
            R.id.widget_recovery,
            when (zone) {
                "green" -> Color.parseColor("#16EC06")
                "yellow" -> Color.parseColor("#FFDE00")
                "red" -> Color.parseColor("#FF3B30")
                else -> Color.parseColor("#E6E8EB")
            },
        )
        views.setTextViewText(R.id.widget_strain, strain)
        views.setTextViewText(R.id.widget_sleep, sleep)
        views.setTextViewText(
            R.id.widget_caption,
            when {
                demo && stale -> "Airlog · demo · not today"
                demo -> "Airlog · demo"
                stale -> "Airlog · waiting for today"
                else -> "Airlog"
            },
        )
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        return views
    }
}
