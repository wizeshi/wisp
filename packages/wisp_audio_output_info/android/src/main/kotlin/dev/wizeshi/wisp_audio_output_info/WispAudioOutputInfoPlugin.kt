// Expected path: android/src/main/kotlin/dev/wizeshi/wisp_audio_output_info/WispAudioOutputInfoPlugin.kt
package dev.wizeshi.wisp_audio_output_info

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android side of wisp_audio_output_info.
 *
 * IMPORTANT PLATFORM CAVEAT: unlike Windows (WASAPI's
 * IMMDeviceEnumerator::GetDefaultAudioEndpoint), Android has no public API
 * that just tells you "the currently active render endpoint." The closest
 * thing, AudioTrack.getRoutedDevice(), only works on a live, currently
 * playing AudioTrack/AudioRecord instance — which this standalone
 * device-info plugin doesn't own (the playback engine does).
 *
 * Since API 31, AudioPlaybackConfiguration.getAudioDeviceInfo() gets us
 * real ground truth for OUR OWN currently-playing session without needing
 * to own the AudioTrack ourselves (see PlaybackDeviceSource below) — but
 * it only exists while something is actively playing. So "current output"
 * here is: that live ground truth when it's available, falling back to a
 * priority-ordered heuristic over AudioManager's device list plus its
 * route-state flags the rest of the time (idle/paused, or API < 31),
 * roughly mirroring
 * Android's own internal routing precedence (communication devices >
 * Bluetooth > wired > USB > HDMI > built-in speaker). It is a best-effort
 * inference, not an authoritative query, and can be wrong in edge cases
 * (e.g. multiple USB devices attached simultaneously). If you need this to
 * be exact, the real fix is to have the playback engine (MediaKit) surface
 * its live AudioTrack's routedDevice and prefer that when something is
 * actually playing, falling back to this heuristic when it isn't.
 */
class WispAudioOutputInfoPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {

    private lateinit var context: Context
    private lateinit var audioManager: AudioManager

    private lateinit var methodChannel: MethodChannel
    private lateinit var outputDevicesChannel: EventChannel
    private lateinit var activeOutputDeviceChannel: EventChannel

    private var outputDevicesStreamHandler: OutputDevicesStreamHandler? = null
    private var activeOutputDeviceStreamHandler: ActiveOutputDeviceStreamHandler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "dev.wizeshi.wisp_audio_output_info",
        )
        methodChannel.setMethodCallHandler(this)

        outputDevicesChannel = EventChannel(
            binding.binaryMessenger,
            "dev.wizeshi.wisp_audio_output_info/outputDevices",
        )
        val devicesHandler = OutputDevicesStreamHandler(audioManager)
        outputDevicesStreamHandler = devicesHandler
        outputDevicesChannel.setStreamHandler(devicesHandler)

        activeOutputDeviceChannel = EventChannel(
            binding.binaryMessenger,
            "dev.wizeshi.wisp_audio_output_info/activeOutputDevice",
        )
        val activeHandler = ActiveOutputDeviceStreamHandler(context, audioManager)
        activeOutputDeviceStreamHandler = activeHandler
        activeOutputDeviceChannel.setStreamHandler(activeHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        outputDevicesChannel.setStreamHandler(null)
        activeOutputDeviceChannel.setStreamHandler(null)
        outputDevicesStreamHandler = null
        activeOutputDeviceStreamHandler = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCurrentOutput" -> result.success(AudioDeviceMapper.currentOutputMap(audioManager))
            "getOutputDevices" -> result.success(AudioDeviceMapper.outputDevicesList(audioManager))
            else -> result.notImplemented()
        }
    }
}

/**
 * Streams the full output device list, re-emitting on every add/remove.
 * Mirrors the native Windows side's behavior of emitting the current
 * snapshot immediately on listen, then following up with changes.
 */
private class OutputDevicesStreamHandler(
    private val audioManager: AudioManager,
) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) = emit()
        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) = emit()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        audioManager.registerAudioDeviceCallback(callback, mainHandler)
        emit()
    }

    override fun onCancel(arguments: Any?) {
        audioManager.unregisterAudioDeviceCallback(callback)
        eventSink = null
    }

    private fun emit() {
        eventSink?.success(AudioDeviceMapper.outputDevicesList(audioManager))
    }
}

/**
 * Streams the best-effort "current output device" (see the platform caveat
 * on WispAudioOutputInfoPlugin above), re-running the heuristic whenever
 * the device list changes OR whenever a route-state broadcast fires that
 * wouldn't necessarily add/remove a device (e.g. Bluetooth SCO turning on
 * for a call uses a device that was already in the list).
 */
private class ActiveOutputDeviceStreamHandler(
    private val context: Context,
    private val audioManager: AudioManager,
) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Dedup state so the half-second poll below only actually pushes an
    // event when the resolved device id changes, not on every tick.
    private var hasEmitted = false
    private var lastEmittedId: String? = null

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) = emit()
        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) = emit()
    }

    private val routeStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(receivedContext: Context?, intent: Intent?) = emit()
    }

    private val playbackCallback: AudioManager.AudioPlaybackCallback? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            object : AudioManager.AudioPlaybackCallback() {
                override fun onPlaybackConfigChanged(
                    configs: MutableList<AudioPlaybackConfiguration>,
                ) = emit()
            }
        } else {
            null
        }

    /**
     * Android gives third-party apps no broadcast or callback for "the
     * active output changed" when the user switches between two already-
     * connected devices via the system Output Switcher — no add/remove, no
     * SCO/headset/HDMI state change fires. (BluetoothA2dp has
     * ACTION_ACTIVE_DEVICE_CHANGED, but it's @SystemApi/BLUETOOTH_PRIVILEGED,
     * unavailable to normal apps.) A short poll while something is actually
     * listening is the only way to catch that case without waiting on the
     * manual refresh button. emit() already diffs against the last-sent id,
     * so this only costs a getAudioDevicesForAttributes() call every tick,
     * never an unnecessary platform-channel round trip to Dart.
     */
    private val pollRunnable = object : Runnable {
        override fun run() {
            emit()
            mainHandler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
        playbackCallback?.let { audioManager.registerAudioPlaybackCallback(it, mainHandler) }
        context.registerReceiver(
            routeStateReceiver,
            IntentFilter().apply {
                addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
                addAction(AudioManager.ACTION_HEADSET_PLUG)
                addAction(AudioManager.ACTION_HDMI_AUDIO_PLUG)
            },
        )
        emit()
        mainHandler.postDelayed(pollRunnable, POLL_INTERVAL_MS)
    }

    override fun onCancel(arguments: Any?) {
        mainHandler.removeCallbacks(pollRunnable)
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        playbackCallback?.let { audioManager.unregisterAudioPlaybackCallback(it) }
        context.unregisterReceiver(routeStateReceiver)
        eventSink = null
        hasEmitted = false
        lastEmittedId = null
    }

    private fun emit() {
        val map = AudioDeviceMapper.currentOutputMap(audioManager)
        val id = map?.get("id") as? String
        if (hasEmitted && id == lastEmittedId) return
        hasEmitted = true
        lastEmittedId = id
        eventSink?.success(map)
    }

    private companion object {
        const val POLL_INTERVAL_MS = 500L
    }
}

/**
 * Live ground truth for "what device is OUR playback actually routed to,"
 * sourced from AudioPlaybackConfiguration.getAudioDeviceInfo() (API 31+).
 *
 * Two hard limits, both unavoidable: it requires API 31, and it only
 * exists while something is actively playing — a paused/idle player has
 * no entry here at all (getActivePlaybackConfigurations() only returns
 * configs the framework currently considers active in the first place).
 * That's why this is layered on top of, and never a replacement for,
 * AudioDeviceMapper's heuristic.
 *
 * There's no public uid/package accessor on AudioPlaybackConfiguration to
 * directly confirm "this entry is ours" — getPlayerState()/getClientUid()/
 * etc. are all hidden @SystemApi, privileged-only. getAudioAttributes()
 * and getAudioDeviceInfo() are the only genuinely public members. So
 * instead: the platform anonymizes AudioAttributes for playback configs
 * belonging to OTHER apps (reduced to USAGE_UNKNOWN) unless the caller
 * holds the privileged MODIFY_AUDIO_ROUTING permission, which this app
 * doesn't request. Filtering for a real, non-UNKNOWN usage is therefore
 * sufficient in practice to isolate our own player's config.
 */
private object PlaybackDeviceSource {
    fun current(audioManager: AudioManager): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null

        val configs = audioManager.activePlaybackConfigurations
        configs.forEach {
            android.util.Log.d(
                "WispAudioOutput",
                "config usage=${it.audioAttributes.usage} " +
                    "device=${it.audioDeviceInfo?.type} " +
                    "name=${it.audioDeviceInfo?.productName}",
            )
        }
        return configs
            .firstOrNull { it.audioAttributes.usage != AudioAttributes.USAGE_UNKNOWN }
            ?.audioDeviceInfo
    }
}

/**
 * Shared mapping from AudioDeviceInfo -> the wire format AudioOutputDevice
 * expects on the Dart side (see AudioOutputDevice.fromMap in types.dart).
 */
private object AudioDeviceMapper {

    /**
     * getDevices(GET_DEVICES_OUTPUTS) enumerates a couple of internal audio
     * policy nodes alongside the real, user-selectable outputs — neither is
     * something a person would ever pick from a device list:
     *
     * - TYPE_TELEPHONY: the internal hop used to route actual phone-call
     *   audio. Not a real output.
     * - TYPE_BUILTIN_SPEAKER_SAFE: the *same physical speaker* as
     *   TYPE_BUILTIN_SPEAKER, just in a volume-limited "safe listening"
     *   routing mode — not a second, distinct device.
     *
     * Both get excluded here rather than surfaced as (currently unknown/
     * unknown-mapped) selectable devices.
     */
    private val excludedTypes = setOf(
        AudioDeviceInfo.TYPE_TELEPHONY,
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
    )

    private fun excludedTypesFiltered(audioManager: AudioManager): List<AudioDeviceInfo> =
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filterNot { excludedTypes.contains(it.type) }

    /**
     * Some physical devices enumerate as two separate AudioDeviceInfo
     * entries — one for call/communication routing, one for actual media
     * playback of the exact same hardware:
     *
     * - Bluetooth earbuds/headsets with a mic: TYPE_BLUETOOTH_SCO (call
     *   profile) alongside TYPE_BLUETOOTH_A2DP (media profile), both
     *   reporting the same product name (e.g. "WF-C700N").
     * - The phone's own hardware: TYPE_BUILTIN_EARPIECE (call) alongside
     *   TYPE_BUILTIN_SPEAKER (media) — always the same physical unit on a
     *   given phone, so no name check applies there.
     *
     * A media player only ever wants the media-profile entry when both
     * exist. This is conditional on purpose: a call-only device (some
     * older mono Bluetooth headsets only support SCO/HFP, no A2DP) has no
     * media counterpart, so its SCO entry must stay — it's the only real
     * option in that case, not a duplicate to hide.
     */
    private val callProfileToMediaProfile = mapOf(
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO to AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE to AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
    )

    private fun dedupeByPhysicalDevice(devices: List<AudioDeviceInfo>): List<AudioDeviceInfo> {
        val excludedIds = mutableSetOf<Int>()

        for ((callType, mediaType) in callProfileToMediaProfile) {
            val callDevices = devices.filter { it.type == callType }
            if (callDevices.isEmpty()) continue
            val mediaDevices = devices.filter { it.type == mediaType }
            if (mediaDevices.isEmpty()) continue

            for (callDevice in callDevices) {
                val hasMediaCounterpart = if (callType == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE) {
                    // Built-in earpiece and speaker are always the same
                    // physical unit — no name check needed or possible
                    // (both just report the phone model as their name).
                    true
                } else {
                    val callName = callDevice.productName?.toString()?.trim()?.lowercase()
                    mediaDevices.any {
                        it.productName?.toString()?.trim()?.lowercase() == callName
                    }
                }
                if (hasMediaCounterpart) {
                    excludedIds += callDevice.id
                }
            }
        }

        return devices.filterNot { excludedIds.contains(it.id) }
    }

    /**
     * When the raw "current" pick (see pickCurrentDevice) turns out to be a
     * call-profile device that got collapsed out of the display list by
     * dedupeByPhysicalDevice, report its media-profile counterpart as
     * current instead — the physical device is still the thing the user
     * has connected, it's just not the entry left in the deduped list.
     */
    private fun representativeInDedupedList(
        rawCurrent: AudioDeviceInfo,
        dedupedOutputs: List<AudioDeviceInfo>,
    ): AudioDeviceInfo? {
        if (dedupedOutputs.any { it.id == rawCurrent.id }) return rawCurrent

        val mediaType = callProfileToMediaProfile[rawCurrent.type] ?: return null
        return if (rawCurrent.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE) {
            dedupedOutputs.firstOrNull { it.type == mediaType }
        } else {
            val name = rawCurrent.productName?.toString()?.trim()?.lowercase()
            dedupedOutputs.firstOrNull {
                it.type == mediaType &&
                    it.productName?.toString()?.trim()?.lowercase() == name
            }
        }
    }

    fun outputDevicesList(audioManager: AudioManager): List<Map<String, Any?>> {
        val rawOutputs = excludedTypesFiltered(audioManager)
        val dedupedOutputs = dedupeByPhysicalDevice(rawOutputs)
        val inputIds = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .map { it.id }
            .toSet()

        val rawCurrent = resolveRawCurrent(audioManager, rawOutputs)
        val currentId = rawCurrent
            ?.let { representativeInDedupedList(it, dedupedOutputs) }
            ?.id

        return dedupedOutputs.map { device ->
            toMap(device, hasInput = inputIds.contains(device.id), isCurrent = device.id == currentId)
        }
    }

    fun currentOutputMap(audioManager: AudioManager): Map<String, Any?>? {
        val rawOutputs = excludedTypesFiltered(audioManager)
        val dedupedOutputs = dedupeByPhysicalDevice(rawOutputs)

        val rawCurrent = resolveRawCurrent(audioManager, rawOutputs) ?: return null
        val current = representativeInDedupedList(rawCurrent, dedupedOutputs) ?: rawCurrent

        val inputIds = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .map { it.id }
            .toSet()
        return toMap(current, hasInput = inputIds.contains(current.id), isCurrent = true)
    }

    /**
     * Prefers PlaybackDeviceSource's live ground truth (API 31+, only
     * while actively playing); falls back to the heuristic otherwise.
     */
    private fun resolveRawCurrent(
        audioManager: AudioManager,
        rawOutputs: List<AudioDeviceInfo>,
    ): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val mediaAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .build()
            val routed = audioManager.getAudioDevicesForAttributes(mediaAttributes).firstOrNull()
            if (routed != null) {
                val matched = rawOutputs.firstOrNull { it.id == routed.id }
                if (matched != null) return matched
            }
        }

        // AudioPlaybackConfiguration.getAudioDeviceInfo() is deprecated as of
        // API 36 with the note "this information was never populated" — it's
        // effectively a no-op on every version, kept only as a harmless
        // secondary attempt below API 33 where the query above isn't available.
        val fromPlayback = PlaybackDeviceSource.current(audioManager)
        if (fromPlayback != null) {
            val matched = rawOutputs.firstOrNull { it.id == fromPlayback.id }
            if (matched != null) return matched
        }
        return pickCurrentDevice(audioManager, rawOutputs)
    }

    /**
     * Priority-ordered heuristic — see the platform caveat docs on
     * WispAudioOutputInfoPlugin. Roughly follows Android's own internal
     * routing precedence for where media/communication audio goes.
     */
    private fun pickCurrentDevice(
        audioManager: AudioManager,
        outputs: List<AudioDeviceInfo>,
    ): AudioDeviceInfo? {
        if (outputs.isEmpty()) return null

        fun firstOf(vararg types: Int): AudioDeviceInfo? =
            outputs.firstOrNull { types.contains(it.type) }

        val hearingAid = firstOf(AudioDeviceInfo.TYPE_HEARING_AID)
        if (hearingAid != null) return hearingAid

        val bleHeadset = firstOf(AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER)
        if (bleHeadset != null) return bleHeadset

        // SCO merely being present in the device list only means the
        // hardware supports the call profile — it does NOT mean SCO is the
        // active route right now. SCO is only genuinely in use during an
        // actual call/voice session; the rest of the time (including
        // normal music playback from the exact same earbuds) audio is
        // still going out over A2DP. Only trust the SCO entry as "current"
        // when the platform confirms SCO is actually turned on.
        if (audioManager.isBluetoothScoOn) {
            val sco = firstOf(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
            if (sco != null) return sco
        }

        val a2dp = firstOf(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
        if (a2dp != null) return a2dp

        val usb = firstOf(
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
        )
        if (usb != null) return usb

        val wired = firstOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        )
        if (wired != null) return wired

        val hdmi = firstOf(
            AudioDeviceInfo.TYPE_HDMI,
            AudioDeviceInfo.TYPE_HDMI_ARC,
        )
        if (hdmi != null) return hdmi

        val dock = firstOf(AudioDeviceInfo.TYPE_DOCK)
        if (dock != null) return dock

        val speaker = firstOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
        if (speaker != null) return speaker

        val earpiece = firstOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
        if (earpiece != null) return earpiece

        return outputs.first()
    }

    private fun toMap(
        device: AudioDeviceInfo,
        hasInput: Boolean,
        isCurrent: Boolean,
    ): Map<String, Any?> {
        val name = device.productName?.toString()?.takeIf { it.isNotBlank() }

        return mapOf(
            "id" to device.id.toString(),
            "platformId" to device.id.toString(),
            "name" to (name ?: kindLabel(device.type)),
            // Android doesn't expose a separate "composed" vs "plain" name
            // the way Windows does (see fullName in wisp_audio_output_info_
            // plugin.cpp) — productName is already the plain product name,
            // so fullName just mirrors it here for API symmetry.
            "fullName" to (name ?: kindLabel(device.type)),
            "kind" to kindFor(device.type).name,
            "connectionType" to connectionTypeFor(device.type).name,
            "hasInput" to hasInput,
            "hasOutput" to true,
            "isCurrent" to isCurrent,
            "manufacturer" to null,
            "model" to null,
            "description" to kindLabel(device.type),
            "sampleRate" to device.sampleRates.maxOrNull(),
            "channelCount" to device.channelCounts.maxOrNull(),
            "platformTransport" to device.type.toString(),
        )
    }

    /** Mirrors AudioOutputKind's enum names in types.dart exactly. */
    private fun kindFor(type: Int): Kind = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> Kind.speakers
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> Kind.receiver
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> Kind.headset
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> Kind.headphones
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> Kind.headset
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> Kind.headphones
        AudioDeviceInfo.TYPE_BLE_HEADSET -> Kind.headset
        AudioDeviceInfo.TYPE_BLE_SPEAKER -> Kind.speakers
        AudioDeviceInfo.TYPE_HEARING_AID -> Kind.hearingAid
        AudioDeviceInfo.TYPE_HDMI -> Kind.hdmi
        AudioDeviceInfo.TYPE_HDMI_ARC -> Kind.hdmi
        AudioDeviceInfo.TYPE_USB_HEADSET -> Kind.headset
        AudioDeviceInfo.TYPE_USB_DEVICE -> Kind.speakers
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> Kind.speakers
        AudioDeviceInfo.TYPE_LINE_ANALOG -> Kind.lineOut
        AudioDeviceInfo.TYPE_LINE_DIGITAL -> Kind.digitalOut
        AudioDeviceInfo.TYPE_AUX_LINE -> Kind.lineOut
        AudioDeviceInfo.TYPE_DOCK -> Kind.speakers
        AudioDeviceInfo.TYPE_REMOTE_SUBMIX -> Kind.virtual
        else -> Kind.unknown
    }

    /** Mirrors AudioConnectionType's enum names in types.dart exactly. */
    private fun connectionTypeFor(type: Int): ConnType = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        -> ConnType.integrated
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_AUX_LINE,
        -> ConnType.analog
        AudioDeviceInfo.TYPE_LINE_DIGITAL -> ConnType.digital
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        -> ConnType.bluetooth
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_HEARING_AID,
        -> ConnType.bluetoothLe
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        -> ConnType.hdmi
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY,
        -> ConnType.usb
        AudioDeviceInfo.TYPE_DOCK -> ConnType.analog
        AudioDeviceInfo.TYPE_REMOTE_SUBMIX -> ConnType.virtual
        else -> ConnType.unknown
    }

    private fun kindLabel(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired headphones"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth headset"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth audio"
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "Bluetooth LE headset"
        AudioDeviceInfo.TYPE_BLE_SPEAKER -> "Bluetooth LE speaker"
        AudioDeviceInfo.TYPE_HEARING_AID -> "Hearing aid"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI ARC"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB audio"
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB accessory"
        AudioDeviceInfo.TYPE_LINE_ANALOG -> "Line out"
        AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Digital out"
        AudioDeviceInfo.TYPE_AUX_LINE -> "Aux line"
        AudioDeviceInfo.TYPE_DOCK -> "Dock"
        AudioDeviceInfo.TYPE_REMOTE_SUBMIX -> "Virtual output"
        else -> "Unknown device"
    }

    // Local aliases so this file doesn't need to import the Dart-mirrored
    // enum names as actual Kotlin enums — kept as plain enums here purely
    // for exhaustive `when` checking against typos; `.name` is sent over
    // the wire and must match AudioOutputKind/AudioConnectionType in
    // types.dart exactly.
    private enum class Kind {
        speakers, headphones, headset, earbuds, hearingAid,
        receiver, amplifier, soundbar, television,
        lineOut, digitalOut, hdmi, displayPort,
        virtual, remote, unknown,
    }

    private enum class ConnType {
        integrated, usb, bluetooth, bluetoothLe, hdmi, displayPort,
        analog, digital, pci, network, wireless, virtual, unknown,
    }
}