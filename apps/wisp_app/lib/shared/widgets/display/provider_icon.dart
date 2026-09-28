// Copyright © 2026 wizeshi

library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Renders a modular provider's icon (`icon.png` or `icon.svg`),
/// with local file resolution, remote GitHub caching, and branded fallbacks.
class ProviderIcon extends StatefulWidget {
  final String providerId;
  final String? type;
  final String? packagePath;
  final double size;
  final IconData fallbackIcon;
  final Color? color;

  const ProviderIcon({
    super.key,
    required this.providerId,
    this.type,
    this.packagePath,
    this.size = 24,
    this.fallbackIcon = Icons.extension,
    this.color,
  });

  @override
  State<ProviderIcon> createState() => _ProviderIconState();
}

class _ProviderIconState extends State<ProviderIcon> {
  static final Map<String, String?> _iconPathCache = {};
  static final Map<String, Future<String?>> _inFlightResolutions = {};
  static const String _rawBaseUrl =
      'https://raw.githubusercontent.com/wizeshi/wisp/main/providers';

  String? _resolvedPath;
  bool _isSvg = false;

  @override
  void initState() {
    super.initState();
    _resolveIconPath();
  }

  @override
  void didUpdateWidget(covariant ProviderIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.providerId != widget.providerId ||
        oldWidget.type != widget.type ||
        oldWidget.packagePath != widget.packagePath) {
      _resolveIconPath();
    }
  }

  String get _cacheKey {
    final cleanId = widget.providerId.toLowerCase();
    final pth = widget.packagePath?.toLowerCase();
    if (pth != null && pth.isNotEmpty) return pth;
    return '${widget.type ?? "any"}_$cleanId'.toLowerCase();
  }

  Future<void> _resolveIconPath() async {
    final key = _cacheKey;
    if (_iconPathCache.containsKey(key)) {
      final cached = _iconPathCache[key];
      if (cached != null && File(cached).existsSync()) {
        if (mounted) {
          setState(() {
            _resolvedPath = cached;
            _isSvg = cached.toLowerCase().endsWith('.svg');
          });
        }
        return;
      }
    }

    final future = _inFlightResolutions.putIfAbsent(
      key,
      () => _findOrDownloadIcon(),
    );

    final path = await future;
    _inFlightResolutions.remove(key);
    _iconPathCache[key] = path;

    if (mounted) {
      setState(() {
        _resolvedPath = path;
        _isSvg = path != null && path.toLowerCase().endsWith('.svg');
      });
    }
  }

  Future<String?> _findOrDownloadIcon() async {
    final cleanId = widget.providerId.toLowerCase();
    final candidateTypes = widget.type != null
        ? [widget.type!.toLowerCase()]
        : ['metadata', 'lyrics', 'auth'];

    Directory? supportDir;
    try {
      supportDir = await getApplicationSupportDirectory();
    } catch (_) {}

    // 1. Search local filesystem in support directory and workspace
    final searchDirs = <Directory>[];
    if (supportDir != null) {
      searchDirs.add(Directory(p.join(supportDir.path, 'providers')));
      searchDirs.add(Directory(p.join(supportDir.path, 'provider_icons')));
    }

    final devBases = [
      p.join(Directory.current.path, 'providers'),
      p.join(Directory.current.path, '..', 'providers'),
      p.join(Directory.current.path, '..', '..', 'providers'),
    ];
    for (final base in devBases) {
      final d = Directory(base);
      if (d.existsSync()) {
        searchDirs.add(d);
      }
    }

    // Direct packagePath check
    if (widget.packagePath != null && widget.packagePath!.isNotEmpty) {
      for (final baseDir in searchDirs) {
        final targetDir = Directory(p.join(baseDir.path, widget.packagePath));
        if (targetDir.existsSync()) {
          final svg = File(p.join(targetDir.path, 'icon.svg'));
          if (svg.existsSync()) return svg.path;
          final png = File(p.join(targetDir.path, 'icon.png'));
          if (png.existsSync()) return png.path;
        }
      }
    }

    for (final baseDir in searchDirs) {
      for (final t in candidateTypes) {
        final targetDir = Directory(p.join(baseDir.path, t, cleanId));
        if (targetDir.existsSync()) {
          final svg = File(p.join(targetDir.path, 'icon.svg'));
          if (svg.existsSync()) return svg.path;
          final png = File(p.join(targetDir.path, 'icon.png'));
          if (png.existsSync()) return png.path;
        }
      }
    }

    // 2. Fall back to downloading from GitHub raw and caching locally
    if (supportDir != null) {
      final candidatePaths = <String>[];
      if (widget.packagePath != null && widget.packagePath!.isNotEmpty) {
        candidatePaths.add(widget.packagePath!);
      }
      for (final t in candidateTypes) {
        final path = '$t/$cleanId';
        if (!candidatePaths.contains(path)) {
          candidatePaths.add(path);
        }
      }

      for (final relPath in candidatePaths) {
        for (final ext in ['svg', 'png']) {
          final url = '$_rawBaseUrl/$relPath/icon.$ext';
          try {
            final res = await http.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              final cacheDir = Directory(
                p.join(supportDir.path, 'provider_icons', relPath),
              );
              if (!cacheDir.existsSync()) {
                cacheDir.createSync(recursive: true);
              }
              final file = File(p.join(cacheDir.path, 'icon.$ext'));
              await file.writeAsBytes(res.bodyBytes);
              return file.path;
            }
          } catch (_) {
            // Ignore failure and try next candidate
          }
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedPath != null) {
      if (_isSvg) {
        return SvgPicture.file(
          File(_resolvedPath!),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
        );
      } else {
        return Image.file(
          File(_resolvedPath!),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
        );
      }
    }

    final cleanId = widget.providerId.toLowerCase();
    if (cleanId == 'spotify') {
      return Icon(
        Icons.graphic_eq_rounded,
        size: widget.size,
        color: const Color(0xFF1DB954),
      );
    } else if (cleanId == 'youtube') {
      return Icon(
        Icons.play_circle_fill,
        size: widget.size,
        color: const Color(0xFFFF0000),
      );
    }

    return Icon(
      widget.fallbackIcon,
      size: widget.size,
      color: widget.color,
    );
  }
}

