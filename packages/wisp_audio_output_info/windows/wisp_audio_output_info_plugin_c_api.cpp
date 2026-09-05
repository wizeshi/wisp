#include "include/wisp_audio_output_info/wisp_audio_output_info_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "wisp_audio_output_info_plugin.h"

void WispAudioOutputInfoPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  wisp_audio_output_info::WispAudioOutputInfoPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
