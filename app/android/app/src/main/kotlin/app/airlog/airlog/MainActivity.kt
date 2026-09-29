package app.airlog.airlog

import android.content.Intent
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val b = HealthConnectBridge(applicationContext) { perms -> permissionLauncher.launch(perms) }
        bridge = b
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HealthConnectBridge.CHANNEL)
            .setMethodCallHandler(b)
    }

    override fun getInitialRoute(): String? =
        if (isPrivacyIntent(intent)) PRIVACY_ROUTE else super.getInitialRoute()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isPrivacyIntent(intent)) {
            flutterEngine?.navigationChannel?.pushRoute(PRIVACY_ROUTE)
        }
    }

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }

    companion object {
        const val PRIVACY_ROUTE = "/privacy"

        fun isPrivacyIntent(i: Intent?): Boolean =
            i?.action == "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" ||
                i?.action == "android.intent.action.VIEW_PERMISSION_USAGE"
    }
}
