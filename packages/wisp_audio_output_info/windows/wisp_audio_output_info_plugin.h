#ifndef WISP_AUDIO_OUTPUT_INFO_PLUGIN_H_
#define WISP_AUDIO_OUTPUT_INFO_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <mmdeviceapi.h>

#include <condition_variable>
#include <memory>
#include <mutex>
#include <thread>

namespace wisp_audio_output_info {

class WispAudioNotificationClient;

class WispAudioOutputInfoPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  WispAudioOutputInfoPlugin();
  ~WispAudioOutputInfoPlugin() override;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<
          flutter::MethodResult<flutter::EncodableValue>> result);

  // Called by WispAudioNotificationClient.
  void ScheduleDevicesUpdate();
  void ScheduleDefaultUpdate();
  void OnAudioDeviceNotification();
  void OnDefaultOutputChanged();

 private:
  class OutputDevicesStreamHandler;
  class ActiveOutputStreamHandler;

  friend class WispAudioNotificationClient;

  // Event-channel callbacks.
  std::unique_ptr<
      flutter::EventSink<flutter::EncodableValue>>
  output_devices_sink_;

  std::unique_ptr<
      flutter::EventSink<flutter::EncodableValue>>
  active_output_sink_;

  std::mutex event_sink_mutex_;

  // Windows Core Audio.
  IMMDeviceEnumerator* enumerator_ = nullptr;
  WispAudioNotificationClient* notification_client_ = nullptr;

  std::mutex notification_mutex_;

  // Coalesced background notification worker.
  std::thread worker_thread_;
  std::mutex worker_mutex_;
  std::condition_variable worker_cv_;
  bool worker_stop_ = false;
  bool devices_dirty_ = false;
  bool default_dirty_ = false;

  void WorkerLoop();

  // Emits the current state.
  void EmitOutputDevices();
  void EmitActiveOutputDevice();

  bool InitializeAudioNotifications();
  void ShutdownAudioNotifications();

  // Event channel handlers.
  void StartOutputDevicesStream(
      std::unique_ptr<
          flutter::EventSink<flutter::EncodableValue>>&& events);

  void StopOutputDevicesStream();

  void StartActiveOutputStream(
      std::unique_ptr<
          flutter::EventSink<flutter::EncodableValue>>&& events);

  void StopActiveOutputStream();
};

}  // namespace wisp_audio_output_info

#endif  // WISP_AUDIO_OUTPUT_INFO_PLUGIN_H_