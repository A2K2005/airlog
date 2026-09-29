package app.airlog.airlog

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import org.json.JSONObject

/**
 * Dark home-screen widget: Recovery %, Strain, Sleep. Renders the snapshot
 * that lib/data/services/widget/widget_sink.dart writes through home_widget
 * after every recompute (keys in WidgetKeys). No network, no Dart here.
 * Tapping opens the app.
 * Pattern follows OpenStrap/edge OpenStrapWidgetProvider.kt (MIT, see
 * third_party/edge/LICENSE); layout and copy are ours.
 */
class AirlogWidgetProvider : HomeWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in setOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) {
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, AirlogWidgetProvider::class.java))
            super.onReceive(context, Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
            return
        }
        super.onReceive(context, intent)
    }

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

    private fun render(context: Context, prefs: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.airlog_widget)
        // A single preference makes the mode, date and scores one snapshot.
        // Pre-upgrade individual keys are intentionally not reused.
        val data = runCatching {
            JSONObject(prefs.getString("airlog_snapshot_v1", "{}") ?: "{}")
        }.getOrElse { JSONObject() }
        val recovery = data.optInt("recovery", -1)
        val zone = data.optString("zone", "none")
        val strain = data.optString("strain", "–")
        val sleep = data.optString("sleep", "–")
        val demo = data.optBoolean("demo", false)
        // QA-08: the day shown isn't today (nothing for today has arrived):
        // label it, never pass yesterday's numbers off as today's. The
        // widget re-renders on clock broadcasts and every
        // 30 min, so it also checks the date itself (the app may not have
        // run since midnight).
        val date = data.optString("date", "")
        val stale = date.isNotEmpty() && date != LocalDate.now().toString()
        val quality = data.optString("quality", "")

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
            listOfNotNull(
                "Airlog",
                if (demo) "sample data" else null,
                if (date.isEmpty()) "waiting for data" else if (stale) date else null,
                quality.takeIf { it.isNotEmpty() },
            ).joinToString(" · "),
        )
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        return views
    }
}
