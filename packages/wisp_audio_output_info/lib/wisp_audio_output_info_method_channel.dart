import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wisp_audio_output_info/models/types.dart';
import 'wisp_audio_output_info_platform_interface.dart';

class MethodChannelWispAudioOutputInfo
    extends WispAudioOutputInfoPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel(
    'dev.wizeshi.wisp_audio_output_info',
  );

  static const EventChannel _outputDevicesChannel = EventChannel(
    'dev.wizeshi.wisp_audio_output_info/outputDevices',
  );

  static const EventChannel _activeOutputDeviceChannel = EventChannel(
    'dev.wizeshi.wisp_audio_output_info/activeOutputDevice',
  );

  @override
  Stream<List<AudioOutputDevice>> get outputDevices {
    return _outputDevicesChannel
        .receiveBroadcastStream()
        .map((event) {
          final list = event as List<Object?>;

          return list
              .whereType<Map>()
              .map(
                (device) => AudioOutputDevice.fromMap(
                  Map<Object?, Object?>.from(device),
                ),
              )
              .toList(growable: false);
        });
  }

  @override
  Stream<AudioOutputDevice?> get activeOutputDevice {
    return _activeOutputDeviceChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event == null) {
            return null;
          }

          return AudioOutputDevice.fromMap(
            Map<Object?, Object?>.from(event as Map),
          );
        });
  }

  @override
  Future<AudioOutputDevice?> getCurrentOutput() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'getCurrentOutput',
    );

    if (result == null) {
      return null;
    }

    return AudioOutputDevice.fromMap(result);
  }

  @override
  Future<List<AudioOutputDevice>> getOutputDevices() async {
    final result = await methodChannel.invokeMethod<List<Object?>>(
      'getOutputDevices',
    );

    if (result == null) {
      return const [];
    }

    return result
        .whereType<Map<Object?, Object?>>()
        .map(AudioOutputDevice.fromMap)
        .toList(growable: false);
  }
}