// Expected path: android/app/src/main/kotlin/<your/package/path>/MainActivity.kt
// TODO: replace the package below with your actual applicationId from
// android/app/build.gradle, and move this file into the matching directory.
package dev.wizeshi.wisp

import android.content.Intent
import android.os.Build
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
    //
    // TODO: pick a channel name namespaced to your actual applicationId if
    // it differs from the placeholder package above.
    private val systemUiChannelName = "dev.wizeshi.wisp/system_ui"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemUiChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showOutputSwitcher" -> result.success(showOutputSwitcher())
                    else -> result.notImplemented()
                }
            }
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