library;

class SpotifyCdnUrl {
  final Uri uri;
  final DateTime? expiresAt;

  const SpotifyCdnUrl({required this.uri, required this.expiresAt});

  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }

  static SpotifyCdnUrl fromUri(Uri uri) {
    return SpotifyCdnUrl(
      uri: uri,
      expiresAt: _extractExpiry(uri),
    );
  }

  static DateTime? _extractExpiry(Uri uri) {
    final qp = uri.queryParameters;

    final tokenField = qp['__token__'] ?? qp['verify'];
    if (tokenField != null) {
      final tokenExpiry = _extractExpFromToken(tokenField);
      if (tokenExpiry != null) return tokenExpiry;
    }

    final expires = qp['Expires'];
    if (expires != null) {
      final seconds = int.tryParse(expires);
      if (seconds != null && seconds > 0) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
            .toLocal();
      }
    }

    if (uri.query.isNotEmpty) {
      final rawEpochPrefix = RegExp(r'^(\d{9,12})_').firstMatch(uri.query);
      if (rawEpochPrefix != null) {
        final seconds = int.tryParse(rawEpochPrefix.group(1)!);
        if (seconds != null && seconds > 0) {
          return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
              .toLocal();
        }
      }
    }

    return null;
  }

  static DateTime? _extractExpFromToken(String token) {
    final expMatch = RegExp(r'(?:^|[~&])exp=(\d{9,12})(?:$|[~&])').firstMatch(token);
    if (expMatch == null) return null;
    final seconds = int.tryParse(expMatch.group(1)!);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toLocal();
  }
}
