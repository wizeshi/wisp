library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';

class SpotifyAccessPointHosts {
  final List<String> accesspoint;
  final List<String> dealer;
  final List<String> spclient;

  const SpotifyAccessPointHosts({
    required this.accesspoint,
    required this.dealer,
    required this.spclient,
  });

  factory SpotifyAccessPointHosts.fromJson(Map<String, dynamic> json) {
    List<String> parseList(String key) {
      final value = json[key];
      if (value is! List) return const [];
      return value.whereType<String>().where((entry) => entry.isNotEmpty).toList();
    }

    return SpotifyAccessPointHosts(
      accesspoint: parseList('accesspoint'),
      dealer: parseList('dealer'),
      spclient: parseList('spclient'),
    );
  }
}

class SpotifyEndpoint {
  final String host;
  final int port;

  const SpotifyEndpoint({required this.host, required this.port});

  String get authority => '$host:$port';
  Uri get httpsBaseUri => Uri(scheme: 'https', host: host, port: port);

  static SpotifyEndpoint parseOrDefault(String input, SpotifyEndpoint fallback) {
    final split = input.split(':');
    if (split.isEmpty) return fallback;
    final host = split.first.trim();
    if (host.isEmpty) return fallback;

    if (split.length == 1) {
      return SpotifyEndpoint(host: host, port: 443);
    }

    final parsedPort = int.tryParse(split.last.trim());
    if (parsedPort == null || parsedPort <= 0 || parsedPort > 65535) {
      return SpotifyEndpoint(host: host, port: 443);
    }

    return SpotifyEndpoint(host: host, port: parsedPort);
  }
}

class SpotifyServiceAccessPoints {
  final SpotifyEndpoint accesspoint;
  final SpotifyEndpoint dealer;
  final SpotifyEndpoint spclient;

  const SpotifyServiceAccessPoints({
    required this.accesspoint,
    required this.dealer,
    required this.spclient,
  });

  Uri get accesspointBaseUri => accesspoint.httpsBaseUri;
  Uri get spclientBaseUri => spclient.httpsBaseUri;
}

class SpotifyAccessPointResolver {
  static const SpotifyEndpoint _fallbackAccesspoint = SpotifyEndpoint(
    host: 'ap.spotify.com',
    port: 443,
  );
  static const SpotifyEndpoint _fallbackDealer = SpotifyEndpoint(
    host: 'dealer.spotify.com',
    port: 443,
  );
  static const SpotifyEndpoint _fallbackSpclient = SpotifyEndpoint(
    host: 'spclient.wg.spotify.com',
    port: 443,
  );

  static final Uri _resolveUri = Uri.parse(
    'https://apresolve.spotify.com/?type=accesspoint&type=dealer&type=spclient',
  );

  const SpotifyAccessPointResolver();

  Future<SpotifyServiceAccessPoints> resolve() async {
    try {
      final response = await http
          .get(_resolveUri)
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        logger.w(
          '[Spotify/APResolve] Non-200 response: ${response.statusCode}; using fallback endpoints.',
        );
        return _fallback();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        logger.w(
          '[Spotify/APResolve] Invalid payload type; using fallback endpoints.',
        );
        return _fallback();
      }

      final hosts = SpotifyAccessPointHosts.fromJson(decoded);
      return SpotifyServiceAccessPoints(
        accesspoint: hosts.accesspoint.isNotEmpty
            ? SpotifyEndpoint.parseOrDefault(
                hosts.accesspoint.first,
                _fallbackAccesspoint,
              )
            : _fallbackAccesspoint,
        dealer: hosts.dealer.isNotEmpty
            ? SpotifyEndpoint.parseOrDefault(hosts.dealer.first, _fallbackDealer)
            : _fallbackDealer,
        spclient: hosts.spclient.isNotEmpty
            ? SpotifyEndpoint.parseOrDefault(
                hosts.spclient.first,
                _fallbackSpclient,
              )
            : _fallbackSpclient,
      );
    } on SocketException catch (error) {
      logger.w('[Spotify/APResolve] Network error; using fallback', error: error);
      return _fallback();
    } on HttpException catch (error) {
      logger.w('[Spotify/APResolve] HTTP error; using fallback', error: error);
      return _fallback();
    } on FormatException catch (error) {
      logger.w('[Spotify/APResolve] JSON decode error; using fallback', error: error);
      return _fallback();
    } catch (error) {
      logger.w('[Spotify/APResolve] Unexpected error; using fallback', error: error);
      return _fallback();
    }
  }

  SpotifyServiceAccessPoints _fallback() {
    return const SpotifyServiceAccessPoints(
      accesspoint: _fallbackAccesspoint,
      dealer: _fallbackDealer,
      spclient: _fallbackSpclient,
    );
  }
}
