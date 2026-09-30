package app.airlog.airlog

import android.content.Context
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SkinTemperatureRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import kotlin.reflect.KClass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Small Health Connect channel ("airlog/health_connect") for what the
 * `health` 13.3.2 plugin does not expose:
 *  - VO2 max (Vo2MaxRecord is not in the plugin's type map),
 *  - the exact granted-permission set (the plugin only answers yes/no for a
 *    whole list) and ONE permission sheet incl. VO2 + history + background,
 *  - record metadata (device model + lastModifiedTime) for the Phase 0 probe
 *    and "later write wins" on duplicate sleep sessions.
 * Uses the same connect-client version as the plugin (1.2.0-alpha02).
 * Registered by MainActivity only, i.e. absent in the workmanager isolate
 * (the Dart side catches MissingPluginException).
 */
class HealthConnectBridge(
    private val context: Context,
    private val launchPermissions: (Set<String>) -> Unit,
) : MethodChannel.MethodCallHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pendingPermissions: MethodChannel.Result? = null

    private fun client(): HealthConnectClient? =
        if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) {
            HealthConnectClient.getOrCreate(context)
        } else {
            null
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            // Any app via Health Connect: the installed app's label, or null
            // when the package isn't visible (manifest <queries>).
            "appLabel" -> {
                val pkg = call.argument<String>("package")
                result.success(
                    try {
                        val pm = context.packageManager
                        pm.getApplicationLabel(pm.getApplicationInfo(pkg!!, 0)).toString()
                    } catch (e: Exception) {
                        null
                    }
                )
            }
            "grantedPermissions" -> launchIo(result) { c ->
                c.permissionController.getGrantedPermissions().toList()
            }
            "requestPermissions" -> requestPermissions(call, result)
            "readVo2Max" -> launchIo(result) { c ->
                val s = call.argument<Number>("startMs")!!.toLong()
                val e = call.argument<Number>("endMs")!!.toLong()
                readAll(c, Vo2MaxRecord::class, s, e).map { r ->
                    mapOf(
                        "id" to r.metadata.id,
                        "time" to r.time.toEpochMilli(),
                        "vo2" to r.vo2MillilitersPerMinuteKilogram,
                        "origin" to r.metadata.dataOrigin.packageName,
                        "device" to deviceName(r.metadata.device),
                        "lastModified" to r.metadata.lastModifiedTime.toEpochMilli(),
                    )
                }
            }
            "recordMeta" -> launchIo(result) { c ->
                val type = call.argument<String>("type")!!
                val s = call.argument<Number>("startMs")!!.toLong()
                val e = call.argument<Number>("endMs")!!.toLong()
                @Suppress("UNCHECKED_CAST")
                val cls = (TYPES[type] ?: throw IllegalArgumentException("Unknown type $type"))
                    as KClass<Record>
                readAll(c, cls, s, e).map { r ->
                    mapOf(
                        "id" to r.metadata.id,
                        "origin" to r.metadata.dataOrigin.packageName,
                        "device" to deviceName(r.metadata.device),
                        "lastModified" to r.metadata.lastModifiedTime.toEpochMilli(),
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPermissions(call: MethodCall, result: MethodChannel.Result) {
        val perms = call.argument<List<String>>("permissions")?.toSet() ?: emptySet()
        if (client() == null) {
            result.error("HC_UNAVAILABLE", "Health Connect is not available", null)
            return
        }
        if (pendingPermissions != null) {
            result.error("BUSY", "A permission request is already running", null)
            return
        }
        pendingPermissions = result
        try {
            launchPermissions(perms)
        } catch (e: Exception) {
            pendingPermissions = null
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }

    /** Called by MainActivity's ActivityResult callback. */
    fun onPermissionsResult(granted: Set<String>) {
        val r = pendingPermissions ?: return
        pendingPermissions = null
        // Report the full granted set (previous grants included).
        launchIo(r) { c -> c.permissionController.getGrantedPermissions().toList() }
    }

    private fun <T> launchIo(result: MethodChannel.Result, block: suspend (HealthConnectClient) -> T) {
        val c = client()
        if (c == null) {
            result.error("HC_UNAVAILABLE", "Health Connect is not available", null)
            return
        }
        scope.launch {
            try {
                result.success(block(c))
            } catch (e: Exception) {
                result.error("HC_ERROR", e.message ?: e.toString(), null)
            }
        }
    }

    private suspend fun <T : Record> readAll(
        c: HealthConnectClient,
        cls: KClass<T>,
        startMs: Long,
        endMs: Long,
    ): List<T> {
        val out = mutableListOf<T>()
        var token: String? = null
        var pages = 0
        do {
            val resp = c.readRecords(
                ReadRecordsRequest(
                    recordType = cls,
                    timeRangeFilter = TimeRangeFilter.between(
                        Instant.ofEpochMilli(startMs),
                        Instant.ofEpochMilli(endMs),
                    ),
                    pageToken = token,
                ),
            )
            out.addAll(resp.records)
            token = resp.pageToken
            pages++
        } while (!token.isNullOrEmpty() && pages < 200)
        check(token.isNullOrEmpty()) { "Health Connect read exceeded page limit; window is incomplete" }
        return out
    }

    private fun deviceName(d: Device?): String? {
        if (d == null) return null
        val parts = listOfNotNull(d.manufacturer, d.model).filter { it.isNotBlank() }
        return if (parts.isEmpty()) null else parts.joinToString(" ")
    }

    fun dispose() {
        scope.cancel()
    }

    companion object {
        const val CHANNEL = "airlog/health_connect"

        val TYPES: Map<String, KClass<out Record>> = mapOf(
            "HEART_RATE" to HeartRateRecord::class,
            "HEART_RATE_VARIABILITY_RMSSD" to HeartRateVariabilityRmssdRecord::class,
            "RESTING_HEART_RATE" to RestingHeartRateRecord::class,
            "RESPIRATORY_RATE" to RespiratoryRateRecord::class,
            "SKIN_TEMPERATURE" to SkinTemperatureRecord::class,
            "SLEEP_SESSION" to SleepSessionRecord::class,
            "WORKOUT" to ExerciseSessionRecord::class,
            "STEPS" to StepsRecord::class,
            "WEIGHT" to WeightRecord::class,
            "VO2_MAX" to Vo2MaxRecord::class,
            "BLOOD_OXYGEN" to OxygenSaturationRecord::class,
        )
    }
}
