#define INITGUID

#include "wisp_audio_output_info_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <mmdeviceapi.h>
#include <devicetopology.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propsys.h>
#include <audioclient.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "propsys.lib")

namespace
{

  using flutter::EncodableList;
  using flutter::EncodableMap;
  using flutter::EncodableValue;

  // =============================================================================
  // Utility
  // =============================================================================

  std::string WideToUtf8(const wchar_t *value)
  {
    if (value == nullptr)
    {
      return {};
    }

    int size = WideCharToMultiByte(
        CP_UTF8,
        0,
        value,
        -1,
        nullptr,
        0,
        nullptr,
        nullptr);

    if (size <= 0)
    {
      return {};
    }

    std::string result(size - 1, '\0');

    WideCharToMultiByte(
        CP_UTF8,
        0,
        value,
        -1,
        result.data(),
        size,
        nullptr,
        nullptr);

    return result;
  }

  // =============================================================================
  // Property helpers
  // =============================================================================

  std::string GetStringProperty(
      IPropertyStore *store,
      const PROPERTYKEY &key)
  {

    if (store == nullptr)
    {
      return {};
    }

    PROPVARIANT value;
    PropVariantInit(&value);

    std::string result;

    if (SUCCEEDED(store->GetValue(key, &value)))
    {

      if (value.vt == VT_LPWSTR &&
          value.pwszVal != nullptr)
      {

        result = WideToUtf8(value.pwszVal);
      }
      else if (value.vt == VT_BSTR &&
               value.bstrVal != nullptr)
      {

        result = WideToUtf8(value.bstrVal);
      }
    }

    PropVariantClear(&value);

    return result;
  }

  std::string GetGuidProperty(
      IPropertyStore *store,
      const PROPERTYKEY &key)
  {

    if (store == nullptr)
    {
      return {};
    }

    PROPVARIANT value;
    PropVariantInit(&value);

    std::string result;

    if (SUCCEEDED(store->GetValue(key, &value)))
    {

      if (value.vt == VT_CLSID &&
          value.puuid != nullptr)
      {

        wchar_t buffer[64] = {};

        if (StringFromGUID2(
                *value.puuid,
                buffer,
                static_cast<int>(
                    sizeof(buffer) / sizeof(buffer[0]))) > 0)
        {

          result = WideToUtf8(buffer);
        }
      }
    }

    PropVariantClear(&value);

    return result;
  }

  // =============================================================================
  // Form factor
  // =============================================================================

  std::string GetFormFactor(
      IPropertyStore *store)
  {

    if (store == nullptr)
    {
      return "unknown";
    }

    PROPVARIANT value;
    PropVariantInit(&value);

    std::string result = "unknown";

    if (SUCCEEDED(store->GetValue(
            PKEY_AudioEndpoint_FormFactor,
            &value)))
    {

      if (value.vt == VT_UI4)
      {

        switch (static_cast<EndpointFormFactor>(
            value.uintVal))
        {

        case Speakers:
          result = "speakers";
          break;

        case Headphones:
          result = "headphones";
          break;

        case Headset:
          result = "headset";
          break;

        case LineLevel:
          result = "lineOut";
          break;

        case SPDIF:
          result = "digitalOut";
          break;

        case DigitalAudioDisplayDevice:
          result = "hdmi";
          break;

        case RemoteNetworkDevice:
          result = "remote";
          break;

        case Handset:
          result = "headset";
          break;

        case UnknownDigitalPassthrough:
          result = "digitalOut";
          break;

        case Microphone:
          result = "unknown";
          break;

        case UnknownFormFactor:
        default:
          result = "unknown";
          break;
        }
      }
    }

    PropVariantClear(&value);

    return result;
  }

  // =============================================================================
  // Physical device instance ID
  // =============================================================================

  std::string GetPhysicalDeviceInstanceId(
      IMMDevice *audio_device,
      IMMDeviceEnumerator *enumerator)
  {

    if (audio_device == nullptr ||
        enumerator == nullptr)
    {
      return {};
    }

    IDeviceTopology *topology = nullptr;

    HRESULT hr = audio_device->Activate(
        __uuidof(IDeviceTopology),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void **>(&topology));

    if (FAILED(hr) || topology == nullptr)
    {
      return {};
    }

    IConnector *connector = nullptr;

    hr = topology->GetConnector(
        0,
        &connector);

    if (FAILED(hr) || connector == nullptr)
    {
      topology->Release();
      return {};
    }

    LPWSTR connected_device_id = nullptr;

    hr = connector->GetDeviceIdConnectedTo(
        &connected_device_id);

    if (FAILED(hr) ||
        connected_device_id == nullptr)
    {

      connector->Release();
      topology->Release();

      return {};
    }

    IMMDevice *physical_device = nullptr;

    hr = enumerator->GetDevice(
        connected_device_id,
        &physical_device);

    CoTaskMemFree(connected_device_id);

    connector->Release();
    topology->Release();

    if (FAILED(hr) ||
        physical_device == nullptr)
    {
      return {};
    }

    IPropertyStore *property_store = nullptr;

    hr = physical_device->OpenPropertyStore(
        STGM_READ,
        &property_store);

    if (FAILED(hr) ||
        property_store == nullptr)
    {

      physical_device->Release();

      return {};
    }

    PROPVARIANT value;
    PropVariantInit(&value);

    std::string result;

    hr = property_store->GetValue(
        PKEY_Device_InstanceId,
        &value);

    if (SUCCEEDED(hr) &&
        value.vt == VT_LPWSTR &&
        value.pwszVal != nullptr)
    {

      result = WideToUtf8(value.pwszVal);
    }

    PropVariantClear(&value);

    property_store->Release();
    physical_device->Release();

    return result;
  }

  // =============================================================================
  // Connection type
  // =============================================================================

  std::string GetConnectionType(
      const std::string &instance_id,
      const std::string &kind)
  {

    if (kind == "hdmi")
    {
      return "hdmi";
    }

    std::string upper_instance_id = instance_id;

    for (char &c : upper_instance_id)
    {
      c = static_cast<char>(
          ::toupper(
              static_cast<unsigned char>(c)));
    }

    if (upper_instance_id.rfind("USB\\", 0) == 0)
    {
      return "usb";
    }

    if (upper_instance_id.rfind("BTHENUM\\", 0) == 0 ||
        upper_instance_id.rfind("BTHHFENUM\\", 0) == 0)
    {

      return "bluetooth";
    }

    if (upper_instance_id.rfind("BTHLE\\", 0) == 0)
    {
      return "bluetoothLe";
    }

    if (upper_instance_id.rfind("SWD\\", 0) == 0)
    {
      return "virtual";
    }

    return "unknown";
  }

  // =============================================================================
  // Device info
  // =============================================================================

  EncodableMap GetDeviceInfo(
      IMMDevice *device,
      IMMDeviceEnumerator *enumerator)
  {

    EncodableMap result;

    if (device == nullptr)
    {
      return result;
    }

    result[EncodableValue("kind")] =
        EncodableValue("unknown");

    result[EncodableValue("connectionType")] =
        EncodableValue("unknown");

    result[EncodableValue("hasOutput")] =
        EncodableValue(true);

    result[EncodableValue("hasInput")] =
        EncodableValue(false);

    // ---------------------------------------------------------------------------
    // WASAPI endpoint ID
    // ---------------------------------------------------------------------------

    LPWSTR endpoint_id = nullptr;

    if (SUCCEEDED(
            device->GetId(&endpoint_id)) &&
        endpoint_id != nullptr)
    {

      const std::string id =
          WideToUtf8(endpoint_id);

      result[EncodableValue("id")] =
          EncodableValue(id);

      result[EncodableValue("platformId")] =
          EncodableValue(id);

      CoTaskMemFree(endpoint_id);
    }

    // ---------------------------------------------------------------------------
    // Endpoint properties
    // ---------------------------------------------------------------------------

    std::string kind = "unknown";

    IPropertyStore *property_store = nullptr;

    if (SUCCEEDED(
            device->OpenPropertyStore(
                STGM_READ,
                &property_store)))
    {

      const std::string friendly_name =
          GetStringProperty(
              property_store,
              PKEY_Device_FriendlyName);

      // PKEY_Device_FriendlyName is a *composed* string on Windows —
      // "<jack description> (<product/adapter name>)", e.g.
      // "Headphones (HyperX Cloud Flight Wireless)". PKEY_DeviceInterface_
      // FriendlyName is the plain product name alone ("HyperX Cloud Flight
      // Wireless") without the jack-type wrapper, and is available on the
      // same property store — this is what should surface as `name` so the
      // Dart side isn't left parsing parentheses out of a display string.
      const std::string device_interface_friendly_name =
          GetStringProperty(
              property_store,
              PKEY_DeviceInterface_FriendlyName);

      const std::string description =
          GetStringProperty(
              property_store,
              PKEY_Device_DeviceDesc);

      const std::string manufacturer =
          GetStringProperty(
              property_store,
              PKEY_Device_Manufacturer);

      const std::string container_id =
          GetGuidProperty(
              property_store,
              PKEY_Device_ContainerId);

      kind = GetFormFactor(
          property_store);

      if (!device_interface_friendly_name.empty())
      {
        result[EncodableValue("name")] =
            EncodableValue(device_interface_friendly_name);
      }
      else if (!friendly_name.empty())
      {
        // Fall back to the composed name if the interface-level name isn't
        // available for this endpoint (seen on some virtual/software
        // devices) rather than surfacing nothing.
        result[EncodableValue("name")] =
            EncodableValue(friendly_name);
      }

      if (!friendly_name.empty())
      {
        result[EncodableValue("fullName")] =
            EncodableValue(friendly_name);
      }

      if (!description.empty())
      {
        result[EncodableValue("description")] =
            EncodableValue(description);
      }

      if (!manufacturer.empty())
      {
        result[EncodableValue("manufacturer")] =
            EncodableValue(manufacturer);
      }

      if (!container_id.empty())
      {
        result[EncodableValue("containerId")] =
            EncodableValue(container_id);
      }

      result[EncodableValue("kind")] =
          EncodableValue(kind);

      property_store->Release();
    }

    // ---------------------------------------------------------------------------
    // Physical connection
    // ---------------------------------------------------------------------------

    const std::string physical_instance_id =
        GetPhysicalDeviceInstanceId(
            device,
            enumerator);

    const std::string connection_type =
        GetConnectionType(
            physical_instance_id,
            kind);

    result[EncodableValue("connectionType")] =
        EncodableValue(connection_type);

    if (!physical_instance_id.empty())
    {
      result[EncodableValue("platformTransport")] =
          EncodableValue(physical_instance_id);
    }

    // ---------------------------------------------------------------------------
    // Audio format
    // ---------------------------------------------------------------------------

    IAudioClient *audio_client = nullptr;

    if (SUCCEEDED(
            device->Activate(
                __uuidof(IAudioClient),
                CLSCTX_ALL,
                nullptr,
                reinterpret_cast<void **>(
                    &audio_client))))
    {

      WAVEFORMATEX *format = nullptr;

      if (SUCCEEDED(
              audio_client->GetMixFormat(&format)) &&
          format != nullptr)
      {

        result[EncodableValue("sampleRate")] =
            EncodableValue(
                static_cast<int64_t>(
                    format->nSamplesPerSec));

        result[EncodableValue("channelCount")] =
            EncodableValue(
                static_cast<int64_t>(
                    format->nChannels));

        CoTaskMemFree(format);
      }

      audio_client->Release();
    }

    return result;
  }

  // =============================================================================
  // Enumerate active output devices
  // =============================================================================

  EncodableList EnumerateOutputDevices(
      IMMDeviceEnumerator *enumerator)
  {

    EncodableList devices;

    if (enumerator == nullptr)
    {
      return devices;
    }

    IMMDeviceCollection *collection = nullptr;

    HRESULT hr = enumerator->EnumAudioEndpoints(
        eRender,
        DEVICE_STATE_ACTIVE,
        &collection);

    if (FAILED(hr) ||
        collection == nullptr)
    {

      return devices;
    }

    UINT count = 0;

    hr = collection->GetCount(&count);

    if (FAILED(hr))
    {
      collection->Release();
      return devices;
    }

    for (UINT i = 0; i < count; ++i)
    {

      IMMDevice *device = nullptr;

      if (FAILED(
              collection->Item(
                  i,
                  &device)) ||
          device == nullptr)
      {

        continue;
      }

      EncodableMap device_info =
          GetDeviceInfo(
              device,
              enumerator);

      devices.emplace_back(
          EncodableValue(
              std::move(device_info)));

      device->Release();
    }

    collection->Release();

    return devices;
  }

  // =============================================================================
  // Current default output
  // =============================================================================

  EncodableValue GetCurrentOutput(
      IMMDeviceEnumerator *enumerator)
  {

    if (enumerator == nullptr)
    {
      return EncodableValue();
    }

    IMMDevice *device = nullptr;

    HRESULT hr =
        enumerator->GetDefaultAudioEndpoint(
            eRender,
            eConsole,
            &device);

    if (FAILED(hr) ||
        device == nullptr)
    {

      return EncodableValue();
    }

    EncodableMap device_info =
        GetDeviceInfo(
            device,
            enumerator);

    device->Release();

    return EncodableValue(
        std::move(device_info));
  }

} // namespace

// =============================================================================
// Flutter stream handlers
// =============================================================================

namespace wisp_audio_output_info
{

  // =============================================================================
  // Windows notification client
  // =============================================================================

  class WispAudioNotificationClient
      : public IMMNotificationClient
  {

  public:
    explicit WispAudioNotificationClient(
        WispAudioOutputInfoPlugin *plugin)
        : plugin_(plugin) {}

    // ---------------------------------------------------------------------------
    // IUnknown
    // ---------------------------------------------------------------------------

    ULONG STDMETHODCALLTYPE AddRef() override
    {
      return ++ref_count_;
    }

    ULONG STDMETHODCALLTYPE Release() override
    {
      ULONG result = --ref_count_;

      if (result == 0)
      {
        delete this;
      }

      return result;
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(
        REFIID iid,
        void **object) override
    {

      if (object == nullptr)
      {
        return E_POINTER;
      }

      *object = nullptr;

      if (iid == __uuidof(IUnknown) ||
          iid == __uuidof(IMMNotificationClient))
      {

        *object =
            static_cast<IMMNotificationClient *>(
                this);

        AddRef();

        return S_OK;
      }

      return E_NOINTERFACE;
    }

    // ---------------------------------------------------------------------------
    // Device added
    // ---------------------------------------------------------------------------

    HRESULT STDMETHODCALLTYPE OnDeviceAdded(
        LPCWSTR device_id) override
    {

      NotifyDeviceChange();

      return S_OK;
    }

    // ---------------------------------------------------------------------------
    // Device removed
    // ---------------------------------------------------------------------------

    HRESULT STDMETHODCALLTYPE OnDeviceRemoved(
        LPCWSTR device_id) override
    {

      NotifyDeviceChange();

      return S_OK;
    }

    // ---------------------------------------------------------------------------
    // Device state changed
    // ---------------------------------------------------------------------------

    HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(
        LPCWSTR device_id,
        DWORD new_state) override
    {

      NotifyDeviceChange();

      return S_OK;
    }

    // ---------------------------------------------------------------------------
    // Device property changed
    // ---------------------------------------------------------------------------

    HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(
        LPCWSTR device_id,
        const PROPERTYKEY key) override
    {

      NotifyDeviceChange();

      return S_OK;
    }

    // ---------------------------------------------------------------------------
    // Default device changed
    // ---------------------------------------------------------------------------

    HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(
        EDataFlow flow,
        ERole role,
        LPCWSTR default_device_id) override
    {

      if (flow != eRender)
      {
        return S_OK;
      }

      if (role != eConsole)
      {
        return S_OK;
      }

      NotifyDefaultChange();

      return S_OK;
    }

  private:
    void NotifyDeviceChange()
    {

      if (plugin_ == nullptr)
      {
        return;
      }

      std::thread(
          [plugin = plugin_]()
          {
            plugin->OnAudioDeviceNotification();
          })
          .detach();
    }

    void NotifyDefaultChange()
    {

      if (plugin_ == nullptr)
      {
        return;
      }

      std::thread(
          [plugin = plugin_]()
          {
            plugin->OnDefaultOutputChanged();
          })
          .detach();
    }

    std::atomic<ULONG> ref_count_{1};

    WispAudioOutputInfoPlugin *plugin_;
  };

  // -----------------------------------------------------------------------------
  // Output devices stream handler
  // -----------------------------------------------------------------------------

  class WispAudioOutputInfoPlugin::
      OutputDevicesStreamHandler
      : public flutter::StreamHandler<flutter::EncodableValue>
  {

  public:
    explicit OutputDevicesStreamHandler(
        WispAudioOutputInfoPlugin *plugin)
        : plugin_(plugin) {}

  protected:
    std::unique_ptr<
        flutter::StreamHandlerError<flutter::EncodableValue>>
    OnListenInternal(
        const flutter::EncodableValue *arguments,
        std::unique_ptr<
            flutter::EventSink<flutter::EncodableValue>> &&events)
        override
    {

      plugin_->StartOutputDevicesStream(
          std::move(events));

      return nullptr;
    }

    std::unique_ptr<
        flutter::StreamHandlerError<flutter::EncodableValue>>
    OnCancelInternal(
        const flutter::EncodableValue *arguments)
        override
    {

      plugin_->StopOutputDevicesStream();

      return nullptr;
    }

  private:
    WispAudioOutputInfoPlugin *plugin_;
  };

  // -----------------------------------------------------------------------------
  // Active output stream handler
  // -----------------------------------------------------------------------------

  class WispAudioOutputInfoPlugin::
      ActiveOutputStreamHandler
      : public flutter::StreamHandler<flutter::EncodableValue>
  {

  public:
    explicit ActiveOutputStreamHandler(
        WispAudioOutputInfoPlugin *plugin)
        : plugin_(plugin) {}

  protected:
    std::unique_ptr<
        flutter::StreamHandlerError<flutter::EncodableValue>>
    OnListenInternal(
        const flutter::EncodableValue *arguments,
        std::unique_ptr<
            flutter::EventSink<flutter::EncodableValue>> &&events)
        override
    {

      plugin_->StartActiveOutputStream(
          std::move(events));

      return nullptr;
    }

    std::unique_ptr<
        flutter::StreamHandlerError<flutter::EncodableValue>>
    OnCancelInternal(
        const flutter::EncodableValue *arguments)
        override
    {

      plugin_->StopActiveOutputStream();

      return nullptr;
    }

  private:
    WispAudioOutputInfoPlugin *plugin_;
  };

  // =============================================================================
  // Plugin registration
  // =============================================================================

  void WispAudioOutputInfoPlugin::
      RegisterWithRegistrar(
          flutter::PluginRegistrarWindows *registrar)
  {

    // ---------------------------------------------------------------------------
    // Method channel
    // ---------------------------------------------------------------------------

    auto method_channel =
        std::make_unique<
            flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(),
            "dev.wizeshi.wisp_audio_output_info",
            &flutter::StandardMethodCodec::GetInstance());

    // ---------------------------------------------------------------------------
    // Output devices EventChannel
    // ---------------------------------------------------------------------------

    auto output_devices_channel =
        std::make_unique<
            flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(),
            "dev.wizeshi.wisp_audio_output_info/outputDevices",
            &flutter::StandardMethodCodec::GetInstance());

    // ---------------------------------------------------------------------------
    // Active output EventChannel
    // ---------------------------------------------------------------------------

    auto active_output_channel =
        std::make_unique<
            flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(),
            "dev.wizeshi.wisp_audio_output_info/activeOutputDevice",
            &flutter::StandardMethodCodec::GetInstance());

    // ---------------------------------------------------------------------------
    // Plugin
    // ---------------------------------------------------------------------------

    auto plugin =
        std::make_unique<WispAudioOutputInfoPlugin>();

    // Method channel.
    method_channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](
            const auto &call,
            auto result)
        {
          plugin_pointer->HandleMethodCall(
              call,
              std::move(result));
        });

    // Stream handlers need to live as long as the EventChannels.
    plugin->output_devices_stream_handler_ =
        std::make_unique<
            WispAudioOutputInfoPlugin::
                OutputDevicesStreamHandler>(
            plugin.get());

    plugin->active_output_stream_handler_ =
        std::make_unique<
            WispAudioOutputInfoPlugin::
                ActiveOutputStreamHandler>(
            plugin.get());

    output_devices_channel->SetStreamHandler(
        std::unique_ptr<
            flutter::StreamHandler<
                flutter::EncodableValue>>(
            plugin->output_devices_stream_handler_.get()));

    active_output_channel->SetStreamHandler(
        std::unique_ptr<
            flutter::StreamHandler<
                flutter::EncodableValue>>(
            plugin->active_output_stream_handler_.get()));

    registrar->AddPlugin(
        std::move(plugin));
  }

  // =============================================================================
  // Constructor / destructor
  // =============================================================================

  WispAudioOutputInfoPlugin::
      WispAudioOutputInfoPlugin()
  {

    InitializeAudioNotifications();
  }

  WispAudioOutputInfoPlugin::
      ~WispAudioOutputInfoPlugin()
  {

    ShutdownAudioNotifications();
  }

  // =============================================================================
  // Core Audio notification initialization
  // =============================================================================

  bool WispAudioOutputInfoPlugin::
      InitializeAudioNotifications()
  {

    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void **>(
            &enumerator_));

    if (FAILED(hr) ||
        enumerator_ == nullptr)
    {

      enumerator_ = nullptr;

      return false;
    }

    notification_client_ =
        new WispAudioNotificationClient(this);

    hr =
        enumerator_->RegisterEndpointNotificationCallback(
            notification_client_);

    if (FAILED(hr))
    {

      notification_client_->Release();
      notification_client_ = nullptr;

      enumerator_->Release();
      enumerator_ = nullptr;

      return false;
    }

    return true;
  }

  // =============================================================================
  // Core Audio notification shutdown
  // =============================================================================

  void WispAudioOutputInfoPlugin::
      ShutdownAudioNotifications()
  {

    if (enumerator_ != nullptr &&
        notification_client_ != nullptr)
    {

      enumerator_->UnregisterEndpointNotificationCallback(
          notification_client_);

      notification_client_->Release();
      notification_client_ = nullptr;
    }

    if (enumerator_ != nullptr)
    {
      enumerator_->Release();
      enumerator_ = nullptr;
    }

    std::lock_guard<std::mutex> lock(
        event_sink_mutex_);

    output_devices_sink_.reset();
    active_output_sink_.reset();
  }

  // =============================================================================
  // Stream management
  // =============================================================================

  void WispAudioOutputInfoPlugin::
      StartOutputDevicesStream(
          std::unique_ptr<
              flutter::EventSink<flutter::EncodableValue>> &&events)
  {

    {
      std::lock_guard<std::mutex> lock(
          event_sink_mutex_);

      output_devices_sink_ =
          std::move(events);
    }

    // Immediately emit the current list.
    EmitOutputDevices();
  }

  void WispAudioOutputInfoPlugin::
      StopOutputDevicesStream()
  {

    std::lock_guard<std::mutex> lock(
        event_sink_mutex_);

    output_devices_sink_.reset();
  }

  void WispAudioOutputInfoPlugin::
      StartActiveOutputStream(
          std::unique_ptr<
              flutter::EventSink<flutter::EncodableValue>> &&events)
  {

    {
      std::lock_guard<std::mutex> lock(
          event_sink_mutex_);

      active_output_sink_ =
          std::move(events);
    }

    // Immediately emit the current device.
    EmitActiveOutputDevice();
  }

  void WispAudioOutputInfoPlugin::
      StopActiveOutputStream()
  {

    std::lock_guard<std::mutex> lock(
        event_sink_mutex_);

    active_output_sink_.reset();
  }

  // =============================================================================
  // Device notification callbacks
  // =============================================================================

  void WispAudioOutputInfoPlugin::
      OnAudioDeviceNotification()
  {

    std::lock_guard<std::mutex> lock(
        notification_mutex_);

    EmitOutputDevices();
  }

  void WispAudioOutputInfoPlugin::
      OnDefaultOutputChanged()
  {

    std::lock_guard<std::mutex> lock(
        notification_mutex_);

    EmitActiveOutputDevice();
  }

  // =============================================================================
  // Emit output device list
  // =============================================================================

  void WispAudioOutputInfoPlugin::
      EmitOutputDevices()
  {

    // Don't bother doing the work if nobody is listening.
    {
      std::lock_guard<std::mutex> lock(
          event_sink_mutex_);

      if (output_devices_sink_ == nullptr)
      {
        return;
      }
    }

    IMMDeviceEnumerator *enumerator = nullptr;

    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void **>(
            &enumerator));

    if (FAILED(hr) ||
        enumerator == nullptr)
    {

      return;
    }

    EncodableList devices =
        EnumerateOutputDevices(
            enumerator);

    enumerator->Release();

    std::lock_guard<std::mutex> lock(
        event_sink_mutex_);

    if (output_devices_sink_ != nullptr)
    {

      output_devices_sink_->Success(
          EncodableValue(
              std::move(devices)));
    }
  }

  // =============================================================================
  // Emit active output device
  // =============================================================================

  void WispAudioOutputInfoPlugin::
      EmitActiveOutputDevice()
  {

    // Don't bother doing the work if nobody is listening.
    {
      std::lock_guard<std::mutex> lock(
          event_sink_mutex_);

      if (active_output_sink_ == nullptr)
      {
        return;
      }
    }

    IMMDeviceEnumerator *enumerator = nullptr;

    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void **>(
            &enumerator));

    if (FAILED(hr) ||
        enumerator == nullptr)
    {

      return;
    }

    EncodableValue device =
        GetCurrentOutput(
            enumerator);

    enumerator->Release();

    std::lock_guard<std::mutex> lock(
        event_sink_mutex_);

    if (active_output_sink_ != nullptr)
    {

      active_output_sink_->Success(
          device);
    }
  }

  // =============================================================================
  // Method channel
  // =============================================================================

  void WispAudioOutputInfoPlugin::
      HandleMethodCall(
          const flutter::MethodCall<
              flutter::EncodableValue> &call,
          std::unique_ptr<
              flutter::MethodResult<
                  flutter::EncodableValue>>
              result)
  {

    // ===========================================================================
    // getCurrentOutput
    // ===========================================================================

    if (call.method_name() ==
        "getCurrentOutput")
    {

      IMMDeviceEnumerator *enumerator = nullptr;

      HRESULT hr = CoCreateInstance(
          __uuidof(MMDeviceEnumerator),
          nullptr,
          CLSCTX_ALL,
          __uuidof(IMMDeviceEnumerator),
          reinterpret_cast<void **>(
              &enumerator));

      if (FAILED(hr) ||
          enumerator == nullptr)
      {

        result->Error(
            "WINDOWS_AUDIO_ERROR",
            "Failed to create the Windows audio device enumerator.");

        return;
      }

      EncodableValue device =
          GetCurrentOutput(
              enumerator);

      enumerator->Release();

      result->Success(
          device);

      return;
    }

    // ===========================================================================
    // getOutputDevices
    // ===========================================================================

    if (call.method_name() ==
        "getOutputDevices")
    {

      IMMDeviceEnumerator *enumerator = nullptr;

      HRESULT hr = CoCreateInstance(
          __uuidof(MMDeviceEnumerator),
          nullptr,
          CLSCTX_ALL,
          __uuidof(IMMDeviceEnumerator),
          reinterpret_cast<void **>(
              &enumerator));

      if (FAILED(hr) ||
          enumerator == nullptr)
      {

        result->Error(
            "WINDOWS_AUDIO_ERROR",
            "Failed to create the Windows audio device enumerator.");

        return;
      }

      EncodableList devices =
          EnumerateOutputDevices(
              enumerator);

      enumerator->Release();

      result->Success(
          EncodableValue(
              std::move(devices)));

      return;
    }

    // ===========================================================================
    // Unknown method
    // ===========================================================================

    result->NotImplemented();
  }

} // namespace wisp_audio_output_info