import 'package:wisp_audio_output_info/models/types.dart';
import 'wisp_audio_output_info_platform_interface.dart';

class WispAudioOutputInfo {
  WispAudioOutputInfo._();

  static Stream<List<AudioOutputDevice>> get outputDevices => WispAudioOutputInfoPlatform.instance.outputDevices;
  static Stream<AudioOutputDevice?> get activeOutputDevice => WispAudioOutputInfoPlatform.instance.activeOutputDevice;

  /// Returns the audio output device currently being used by the system.
  ///
  /// Returns null if the platform cannot determine the current output.
  static Future<AudioOutputDevice?> getCurrentOutput() {
    return WispAudioOutputInfoPlatform.instance.getCurrentOutput();
  }

  /// Returns all currently available audio output devices.
  static Future<List<AudioOutputDevice>> getOutputDevices() {
    return WispAudioOutputInfoPlatform.instance.getOutputDevices();
  }
}