package app.airlog.airlog

import android.content.Intent
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.health.connect.client.PermissionController
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity (not FlutterActivity): the `health` plugin casts the
 * activity to ComponentActivity for registerForActivityResult (plugin README,
 * "Android 14").
 *
 * Health Connect opens this activity for the privacy policy, either with
 * ACTION_SHOW_PERMISSIONS_RATIONALE (Android ≤ 13) or through the
 * ViewPermissionUsageActivity alias (Android 14+). Both land on the Flutter
 * route "/privacy".
 *
 * A home-screen widget opens it with [AirlogWidgets.ACTION_OPEN_ROUTE] and a
 * route from the allow-list [AirlogWidgets.ROUTES] (WIDGETS_PLAN §6): the
 * initial route on a cold start, pushed on a warm one.
 */
class MainActivity : FlutterFragmentActivity() {

    private var bridge: HealthConnectBridge? = null

    // Must be registered before the activity is STARTED, so it's a field.
    // One sheet for every type we read + VO2 max + history + background
    // (the plugin's own launcher cannot request READ_VO2_MAX).
    private val permissionLauncher =
        registerForActivityResult(PermissionController.createRequestPermissionResultContract()) {
            granted -> bridge?.onPermissionsResult(granted)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        // TEMP startup probe (final wave): log main-thread messages > 80 ms.
        var t0 = 0L
        var what = ""
        Looper.getMainLooper().setMessageLogging { s ->
            if (s.startsWith(">>>>>")) { t0 = SystemClock.uptimeMillis(); what = s }
            else if (s.startsWith("<<<<<")) {
                val d = SystemClock.uptimeMillis() - t0
                if (d > 80) Log.w("AirlogProbe", "main ${d}ms $what")
            }
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val b = HealthConnectBridge(applicationContext) { perms -> permissionLauncher.launch(perms) }
        bridge = b
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HealthConnectBridge.CHANNEL)
            .setMethodCallHandler(b)
    }

    override fun getInitialRoute(): String? =
        if (isPrivacyIntent(intent)) PRIVACY_ROUTE
        else widgetRoute(intent) ?: super.getInitialRoute()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isPrivacyIntent(intent)) {
            flutterEngine?.navigationChannel?.pushRoute(PRIVACY_ROUTE)
            return
        }
        // "/" is Today, the root: bringing the app forward is enough.
        widgetRoute(intent)?.takeIf { it != "/" }?.let {
            flutterEngine?.navigationChannel?.pushRoute(it)
        }
    }

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }

    companion object {
        const val PRIVACY_ROUTE = "/privacy"

        /** The allow-listed route a widget tap asks for, or null. */
        fun widgetRoute(i: Intent?): String? =
            i?.takeIf { it.action == AirlogWidgets.ACTION_OPEN_ROUTE }
                ?.getStringExtra(AirlogWidgets.EXTRA_ROUTE)
                ?.takeIf { it in AirlogWidgets.ROUTES }

        fun isPrivacyIntent(i: Intent?): Boolean =
            i?.action == "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" ||
                i?.action == "android.intent.action.VIEW_PERMISSION_USAGE"
    }
}
