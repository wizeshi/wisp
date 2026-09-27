// Copyright © 2026 wizeshi

library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Renders a modular provider's icon (`icon.png` or `icon.svg`),
/// falling back to a Material Icon if no icon asset is present.
class ProviderIcon extends StatefulWidget {
  final String providerId;
  final String? type;
  final double size;
  final IconData fallbackIcon;
  final Color? color;

  const ProviderIcon({
    super.key,
    required this.providerId,
    this.type,
    this.size = 24,
    this.fallbackIcon = Icons.extension,
    this.color,
  });

  @override
  State<ProviderIcon> createState() => _ProviderIconState();
}

class _ProviderIconState extends State<ProviderIcon> {
  static final Map<String, String?> _iconPathCache = {};
  String? _resolvedPath;
  bool _isSvg = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _resolveIconPath();
  }

  @override
  void didUpdateWidget(covariant ProviderIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.providerId != widget.providerId || oldWidget.type != widget.type) {
      _resolveIconPath();
    }
  }

  Future<void> _resolveIconPath() async {
    final key = '${widget.type ?? "any"}_${widget.providerId}'.toLowerCase();
    if (_iconPathCache.containsKey(key)) {
      final cached = _iconPathCache[key];
      if (mounted) {
        setState(() {
          _resolvedPath = cached;
          _isSvg = cached != null && cached.toLowerCase().endsWith('.svg');
          _checked = true;
        });
      }
      return;
    }

    final path = await _findIconFile(widget.providerId, widget.type);
    _iconPathCache[key] = path;

    if (mounted) {
      setState(() {
        _resolvedPath = path;
        _isSvg = path != null && path.toLowerCase().endsWith('.svg');
        _checked = true;
      });
    }
  }

  static Future<String?> _findIconFile(String providerId, String? type) async {
    final cleanId = providerId.toLowerCase();
    final candidateTypes = type != null ? [type.toLowerCase()] : ['metadata', 'lyrics', 'auth'];

    Directory? supportDir;
    try {
      supportDir = await getApplicationSupportDirectory();
    } catch (_) {}

    final searchDirs = <Directory>[];
    if (supportDir != null) {
      searchDirs.add(Directory(p.join(supportDir.path, 'providers')));
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

    for (final baseDir in searchDirs) {
      for (final t in candidateTypes) {
        final targetDir = Directory(p.join(baseDir.path, t, cleanId));
        if (targetDir.existsSync()) {
          final png = File(p.join(targetDir.path, 'icon.png'));
          if (png.existsSync()) return png.path;

          final svg = File(p.join(targetDir.path, 'icon.svg'));
          if (svg.existsSync()) return svg.path;
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

    return Icon(
      widget.fallbackIcon,
      size: widget.size,
      color: widget.color,
    );
  }
}
