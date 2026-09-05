enum AudioConnectionType {
  integrated,
  usb,
  bluetooth,
  bluetoothLe,
  hdmi,
  displayPort,
  analog,
  digital,
  pci,
  network,
  wireless,
  virtual,
  unknown;

  static AudioConnectionType fromString(String? value) {
    return AudioConnectionType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => AudioConnectionType.unknown,
    );
  }
}
enum AudioOutputKind {
  speakers,
  headphones,
  headset,
  earbuds,
  hearingAid,

  receiver,
  amplifier,
  soundbar,
  television,

  lineOut,
  digitalOut,
  hdmi,
  displayPort,

  virtual,
  remote,

  unknown;

  static AudioOutputKind fromString(String? value) {
    return AudioOutputKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => AudioOutputKind.unknown,
    );
  }
}

class AudioOutputDevice {
  final String? id;
  final String? name;
  /// This is a more complete name. For example, on Windows, the `name` might be "HyperX Cloud", while the `fullName` might be "Headphones (HyperX Cloud)".
  final String? fullName;

  final AudioOutputKind kind;
  final AudioConnectionType connectionType;

  final bool hasInput;
  final bool hasOutput;

  final bool isCurrent; 

  final String? manufacturer;
  final String? model;
  final String? description;

  final int? sampleRate;
  final int? channelCount;

  /// Raw platform-specific device identifier.
  final String? platformId;

  /// Raw platform-specific transport type.
  final String? platformTransport;

  const AudioOutputDevice({
    this.id,
    this.name,
    this.fullName,
    this.kind = AudioOutputKind.unknown,
    this.connectionType = AudioConnectionType.unknown,
    this.hasInput = false,
    this.hasOutput = true,
    this.isCurrent = false,
    this.manufacturer,
    this.model,
    this.description,
    this.sampleRate,
    this.channelCount,
    this.platformId,
    this.platformTransport,
  });

  factory AudioOutputDevice.fromMap(Map<Object?, Object?> map) {
    return AudioOutputDevice(
      id: map['id'] as String?,
      name: map['name'] as String?,
      fullName: map['fullName'] as String?,
      kind: AudioOutputKind.fromString(map['kind'] as String?),
      connectionType: AudioConnectionType.fromString(
        map['connectionType'] as String?,
      ),
      hasInput: map['hasInput'] as bool? ?? false,
      hasOutput: map['hasOutput'] as bool? ?? true,
      isCurrent: map['isCurrent'] as bool? ?? false,
      manufacturer: map['manufacturer'] as String?,
      model: map['model'] as String?,
      description: map['description'] as String?,
      sampleRate: map['sampleRate'] as int?,
      channelCount: map['channelCount'] as int?,
      platformId: map['platformId'] as String?,
      platformTransport: map['platformTransport'] as String?,
    );
  }

  @override
  String toString() {
    return 'AudioOutputDevice('
        'id: $id, '
        'name: $name, '
        'fullName: $fullName, '
        'kind: $kind, '
        'connectionType: $connectionType, '
        'isCurrent: $isCurrent'
        ')';
  }
}