// Expected path: android/app/src/main/kotlin/<your/package/path>/MainActivity.kt
// TODO: replace the package below with your actual applicationId from
// android/app/build.gradle, and move this file into the matching directory.
package dev.wizeshi.wisp

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    // Deliberately app-level, not part of wisp_audio_output_info: opening
    // the system volume/output-switcher panel is a UI action tied to this
    // Activity, not audio *device information* the plugin is scoped to.
    // Keeping it here keeps the plugin's public API stable regardless of
    // how (or whether) this feature evolves.
    private val systemUiChannelName = "dev.wizeshi.wisp/system_ui"
    private val backgroundAudioChannelName = "dev.wizeshi.wisp/background_audio"

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemUiChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showOutputSwitcher" -> result.success(showOutputSwitcher())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundAudioChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireLocks" -> result.success(acquireBackgroundLocks())
                    "releaseLocks" -> result.success(releaseBackgroundLocks())
                    "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> result.success(requestIgnoreBatteryOptimizations())
                    "isDataSaverRestricted" -> result.success(isDataSaverRestricted())
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquireBackgroundLocks(): Boolean {
        return try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Wisp:AudioPlayback")?.apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire()
            }

            if (wifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                wifiLock = wifiManager?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Wisp:AudioPlayback")?.apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun releaseBackgroundLocks(): Boolean {
        return try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            return powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
        }
        return true
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!isIgnoringBatteryOptimizations()) {
                return try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    true
                } catch (e: Exception) {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                        true
                    } catch (e2: Exception) {
                        false
                    }
                }
            }
        }
        return true
    }

    private fun isDataSaverRestricted(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            return when (connectivityManager?.restrictBackgroundStatus) {
                ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED -> true
                else -> false
            }
        }
        return false
    }

    override fun onDestroy() {
        releaseBackgroundLocks()
        super.onDestroy()
    }

    /**
     * Opens the system volume panel (Settings.Panel.ACTION_VOLUME, API 29+).
     * On Android 11+ this includes the media output-switcher chip whenever
     * this app has an active MediaSession in a playing/pausable state —
     * audio_service already sets one up via WispAudioHandler. Picking a
     * device there re-routes the OS "media" stream at the system level,
     * and mpv follows because its AO is left on "auto" rather than pinned
     * to a specific device — the exact same mechanism as switching via the
     * hardware volume rocker, just surfaced as an in-app button.
     *
     * Returns false below API 29 (the panel doesn't exist) or if some
     * OEM skin strips/blocks it — callers should treat false as "not
     * available here" and fall back accordingly rather than assuming
     * success.
     */
    private fun showOutputSwitcher(): Boolean {
    val launchedDirectDialog = try {
        sendBroadcast(
            Intent("com.android.systemui.action.LAUNCH_MEDIA_OUTPUT_DIALOG")
                .setPackage("com.android.systemui")
                .putExtra("package_name", packageName) // the missing piece
        )
        true
    } catch (error: Exception) {
        false
    }
    if (launchedDirectDialog) return true

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        return false
    }
    return try {
        startActivity(Intent(Settings.Panel.ACTION_VOLUME))
        true
    } catch (error: Exception) {
        false
    }
}
}