import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/features/connect/services/spotify_connect_models.dart';
import 'package:wisp/features/connect/services/spotify_connect_api_client.dart';
import 'package:wisp/features/connect/services/spotify_web_player_service.dart';

void main() {
  group('SpotifyConnectDevice', () {
    test('parses device JSON correctly', () {
      final json = {
        'id': 'device_123',
        'name': 'Living Room Echo',
        'type': 'Speaker',
        'is_active': true,
        'is_restricted': false,
        'volume_percent': 65,
        'supports_volume': true,
      };

      final device = SpotifyConnectDevice.fromJson(json);

      expect(device.id, equals('device_123'));
      expect(device.name, equals('Living Room Echo'));
      expect(device.type, equals(SpotifyDeviceType.speaker));
      expect(device.type.label, equals('Speaker'));
      expect(device.isActive, isTrue);
      expect(device.isRestricted, isFalse);
      expect(device.volumePercent, equals(65));
      expect(device.supportsVolume, isTrue);
    });

    test('handles unknown device type gracefully', () {
      final json = {
        'id': 'tv_456',
        'name': 'Smart TV',
        'type': 'something_unexpected',
      };

      final device = SpotifyConnectDevice.fromJson(json);

      expect(device.id, equals('tv_456'));
      expect(device.name, equals('Smart TV'));
      expect(device.type, equals(SpotifyDeviceType.unknown));
      expect(device.isActive, isFalse);
    });

    test('parses various Spotify device types correctly', () {
      expect(SpotifyDeviceType.fromString('computer'), equals(SpotifyDeviceType.computer));
      expect(SpotifyDeviceType.fromString('smartphone'), equals(SpotifyDeviceType.smartphone));
      expect(SpotifyDeviceType.fromString('tv'), equals(SpotifyDeviceType.tv));
      expect(SpotifyDeviceType.fromString('gameconsole'), equals(SpotifyDeviceType.gameConsole));
      expect(SpotifyDeviceType.fromString('audiodongle'), equals(SpotifyDeviceType.audioDongle));
    });
  });

  group('SpotifyConnectApiClient', () {
    test('initial rate limiting state is false', () {
      final client = SpotifyConnectApiClient.instance;
      expect(client.isRateLimited, isFalse);
      expect(client.rateLimitSecondsRemaining, equals(0));
    });
  });

  group('SpotifyWebPlayerService', () {
    test('formats publishedName correctly', () {
      final service = SpotifyWebPlayerService.instance;
      service.updateLocalDeviceName('DESKTOP-TEST');
      expect(service.publishedName, equals('wisp | DESKTOP-TEST'));
    });
  });
}
