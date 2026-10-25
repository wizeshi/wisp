// Copyright © 2026 wizeshi

library;

import 'package:flutter/material.dart';

enum SpotifyDeviceType {
  computer,
  tablet,
  smartphone,
  speaker,
  tv,
  avr,
  stb,
  audioDongle,
  gameConsole,
  castVideo,
  castAudio,
  automobile,
  unknown;

  static SpotifyDeviceType fromString(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case 'computer':
        return SpotifyDeviceType.computer;
      case 'tablet':
        return SpotifyDeviceType.tablet;
      case 'smartphone':
        return SpotifyDeviceType.smartphone;
      case 'speaker':
        return SpotifyDeviceType.speaker;
      case 'tv':
        return SpotifyDeviceType.tv;
      case 'avr':
        return SpotifyDeviceType.avr;
      case 'stb':
        return SpotifyDeviceType.stb;
      case 'audiodongle':
        return SpotifyDeviceType.audioDongle;
      case 'gameconsole':
        return SpotifyDeviceType.gameConsole;
      case 'castvideo':
        return SpotifyDeviceType.castVideo;
      case 'castaudio':
        return SpotifyDeviceType.castAudio;
      case 'automobile':
        return SpotifyDeviceType.automobile;
      default:
        return SpotifyDeviceType.unknown;
    }
  }

  IconData get icon {
    switch (this) {
      case SpotifyDeviceType.computer:
        return Icons.computer;
      case SpotifyDeviceType.tablet:
        return Icons.tablet;
      case SpotifyDeviceType.smartphone:
        return Icons.phone_iphone;
      case SpotifyDeviceType.speaker:
        return Icons.speaker;
      case SpotifyDeviceType.tv:
        return Icons.tv;
      case SpotifyDeviceType.gameConsole:
        return Icons.sports_esports;
      case SpotifyDeviceType.automobile:
        return Icons.directions_car;
      case SpotifyDeviceType.audioDongle:
      case SpotifyDeviceType.castAudio:
        return Icons.cast;
      case SpotifyDeviceType.avr:
      case SpotifyDeviceType.stb:
      case SpotifyDeviceType.castVideo:
        return Icons.connected_tv;
      case SpotifyDeviceType.unknown:
        return Icons.devices_other;
    }
  }

  String get label {
    switch (this) {
      case SpotifyDeviceType.computer:
        return 'Computer';
      case SpotifyDeviceType.tablet:
        return 'Tablet';
      case SpotifyDeviceType.smartphone:
        return 'Phone';
      case SpotifyDeviceType.speaker:
        return 'Speaker';
      case SpotifyDeviceType.tv:
        return 'TV';
      case SpotifyDeviceType.gameConsole:
        return 'Game Console';
      case SpotifyDeviceType.automobile:
        return 'Car';
      case SpotifyDeviceType.audioDongle:
      case SpotifyDeviceType.castAudio:
        return 'Audio Dongle';
      case SpotifyDeviceType.avr:
        return 'Audio Receiver';
      case SpotifyDeviceType.stb:
        return 'Set-top Box';
      case SpotifyDeviceType.castVideo:
        return 'Streaming Device';
      case SpotifyDeviceType.unknown:
        return 'Spotify Device';
    }
  }
}

class SpotifyConnectDevice {
  final String id;
  final String name;
  final SpotifyDeviceType type;
  final bool isActive;
  final bool isRestricted;
  final int volumePercent;
  final bool supportsVolume;

  const SpotifyConnectDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isActive = false,
    this.isRestricted = false,
    this.volumePercent = 100,
    this.supportsVolume = true,
  });

  factory SpotifyConnectDevice.fromJson(Map<String, dynamic> json) {
    return SpotifyConnectDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Device',
      type: SpotifyDeviceType.fromString(json['type'] as String?),
      isActive: json['is_active'] == true,
      isRestricted: json['is_restricted'] == true,
      volumePercent: (json['volume_percent'] as num?)?.toInt() ?? 100,
      supportsVolume: json['supports_volume'] != false,
    );
  }

  SpotifyConnectDevice copyWith({
    String? id,
    String? name,
    SpotifyDeviceType? type,
    bool? isActive,
    bool? isRestricted,
    int? volumePercent,
    bool? supportsVolume,
  }) {
    return SpotifyConnectDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      isRestricted: isRestricted ?? this.isRestricted,
      volumePercent: volumePercent ?? this.volumePercent,
      supportsVolume: supportsVolume ?? this.supportsVolume,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpotifyConnectDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

