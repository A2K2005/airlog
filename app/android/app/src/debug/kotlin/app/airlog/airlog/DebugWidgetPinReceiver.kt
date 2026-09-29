package app.airlog.airlog

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * DEBUG BUILDS ONLY (src/debug): asks the launcher to pin an Airlog widget,
 * for emulator QA of the home-screen widgets (docs/WIDGETS_PLAN.md §9):
 *
 *   adb shell am broadcast -n app.airlog.airlog/.DebugWidgetPinReceiver --es widget recovery
 *
 * `widget` is recovery, plan or today. It also redraws every pinned widget
 * (`--es widget refresh`). The launcher shows its own confirmation dialog.
 */
class DebugWidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val which = intent.getStringExtra("widget") ?: "today"
        if (which == "refresh") {
            AirlogWidgets.updateAll(context)
            return
        }
        val cls = when (which) {
            "recovery" -> RecoveryWidgetProvider::class.java
            "plan" -> PlanWidgetProvider::class.java
            else -> AirlogWidgetProvider::class.java
        }
        val m = AppWidgetManager.getInstance(context)
        val ok = m.isRequestPinAppWidgetSupported &&
            m.requestPinAppWidget(ComponentName(context, cls), null, null)
        Log.i("AirlogWidget", "pin $which requested: $ok")
    }
}
