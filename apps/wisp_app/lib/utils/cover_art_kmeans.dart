import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CoverArtKMeans {
  static const double _scoreColorfulness = 4.923;
  static const double _scoreDarkness = 1.406;
  static const double _scoreDominance = 0.793;
  static const double _minLuminance = 0.08;
  static const double _maxLuminance = 0.92;
  static const double _saturationBoost = 1.1;
  static const double _brightnessFactor = 0.9;
  static Future<ColorScheme?> fromImageProvider({
    required ImageProvider provider,
    int maxSamples = 1200,
    int clusterCount = 5,
    int maxIterations = 10,
  }) async {
    ui.Image? image;
    try {
      image = await _loadImage(provider);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        return null;
      }
      final samples = _samplePixels(
        byteData.buffer.asUint8List(),
        image.width,
        image.height,
        maxSamples,
      );
      if (samples.isEmpty) {
        return null;
      }
      final clusters = _kmeans(samples, clusterCount, maxIterations);
      if (clusters.isEmpty) {
        return null;
      }
      return _buildScheme(clusters, samples.length);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  static Future<ui.Image> _loadImage(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static List<_ColorSample> _samplePixels(
    Uint8List bytes,
    int width,
    int height,
    int maxSamples,
  ) {
    final totalPixels = width * height;
    final stride = math.max(1, math.sqrt(totalPixels / maxSamples).ceil());
    final samples = <_ColorSample>[];
    for (var y = 0; y < height; y += stride) {
      for (var x = 0; x < width; x += stride) {
        final index = (y * width + x) * 4;
        final alpha = bytes[index + 3];
        if (alpha < 20) {
          continue;
        }
        samples.add(
          _ColorSample(
            bytes[index].toDouble(),
            bytes[index + 1].toDouble(),
            bytes[index + 2].toDouble(),
          ),
        );
      }
    }
    return samples;
  }

  static List<_ColorCluster> _kmeans(
    List<_ColorSample> samples,
    int clusterCount,
    int maxIterations,
  ) {
    final targetClusters = math.max(1, math.min(clusterCount, samples.length));
    final random = math.Random(1337);
    final centroids = <_ColorSample>[];

    centroids.add(samples[random.nextInt(samples.length)].copy());
    while (centroids.length < targetClusters) {
      final distances = List<double>.filled(samples.length, 0);
      var total = 0.0;
      for (var i = 0; i < samples.length; i++) {
        final sample = samples[i];
        var best = double.infinity;
        for (final centroid in centroids) {
          final distance = sample.distanceSquared(centroid);
          if (distance < best) {
            best = distance;
          }
        }
        distances[i] = best;
        total += best;
      }
      if (total <= 0) {
        centroids.add(samples[random.nextInt(samples.length)].copy());
        continue;
      }
      var roll = random.nextDouble() * total;
      var picked = samples.first;
      for (var i = 0; i < samples.length; i++) {
        roll -= distances[i];
        if (roll <= 0) {
          picked = samples[i];
          break;
        }
      }
      centroids.add(picked.copy());
    }

    var assignments = List<int>.filled(samples.length, 0);
    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final sums = List<_ColorSample>.generate(
        centroids.length,
        (_) => _ColorSample(0, 0, 0),
      );
      final counts = List<int>.filled(centroids.length, 0);

      for (var i = 0; i < samples.length; i++) {
        final sample = samples[i];
        var bestIndex = 0;
        var bestDistance = double.infinity;
        for (var c = 0; c < centroids.length; c++) {
          final distance = sample.distanceSquared(centroids[c]);
          if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = c;
          }
        }
        assignments[i] = bestIndex;
        sums[bestIndex].add(sample);
        counts[bestIndex] += 1;
      }

      var maxShift = 0.0;
      for (var c = 0; c < centroids.length; c++) {
        if (counts[c] == 0) {
          centroids[c] = samples[random.nextInt(samples.length)].copy();
          continue;
        }
        final next = sums[c].divide(counts[c]);
        final shift = centroids[c].distanceSquared(next);
        if (shift > maxShift) {
          maxShift = shift;
        }
        centroids[c] = next;
      }

      if (maxShift < 1.0) {
        break;
      }
    }

    final counts = List<int>.filled(centroids.length, 0);
    for (final assignment in assignments) {
      counts[assignment] += 1;
    }

    final clusters = <_ColorCluster>[];
    for (var c = 0; c < centroids.length; c++) {
      if (counts[c] == 0) {
        continue;
      }
      clusters.add(_ColorCluster(centroids[c], counts[c]));
    }
    clusters.sort((a, b) => b.count.compareTo(a.count));
    return clusters;
  }

  static ColorScheme _buildScheme(
    List<_ColorCluster> clusters,
    int totalSamples,
  ) {
    final scored = _scoreClusters(clusters, totalSamples);
    final primary = _tuneColor(_sanitizeColor(scored.first.color));
    final secondary = _pickDistinctColor(scored, [primary]);
    final tertiary = secondary == null
        ? null
        : _pickDistinctColor(scored, [primary, secondary]);

    var scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primary,
      onPrimary: _bestOnColor(primary),
    );

    if (secondary != null) {
      scheme = scheme.copyWith(
        secondary: secondary,
        onSecondary: _bestOnColor(secondary),
      );
    }

    if (tertiary != null) {
      scheme = scheme.copyWith(
        tertiary: tertiary,
        onTertiary: _bestOnColor(tertiary),
      );
    }

    return scheme;
  }

  static Color? _pickDistinctColor(
    List<_ScoredCluster> clusters,
    List<Color> avoid,
  ) {
    var bestColor = clusters.first.color;
    var bestScore = -1.0;
    for (final cluster in clusters.skip(1)) {
      final candidate = _sanitizeColor(cluster.color);
      var minDistance = double.infinity;
      for (final color in avoid) {
        final distance = _rgbDistanceSquared(candidate, color);
        if (distance < minDistance) {
          minDistance = distance;
        }
      }
      if (minDistance > bestScore) {
        bestScore = minDistance;
        bestColor = candidate;
      }
    }
    if (bestScore <= 0) {
      return null;
    }
    return _tuneColor(bestColor);
  }

  static double _rgbDistanceSquared(Color a, Color b) {
    final dr = ((a.r * 255.0).round().clamp(0, 255)) - ((b.r * 255.0).round().clamp(0, 255));
    final dg = ((a.g * 255.0).round().clamp(0, 255)) - ((b.g * 255.0).round().clamp(0, 255));
    final db = ((a.b * 255.0).round().clamp(0, 255)) - ((b.b * 255.0).round().clamp(0, 255));
    return (dr * dr + dg * dg + db * db).toDouble();
  }

  static Color _tuneColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final lightness = hsl.lightness.clamp(0.32, 0.72);
    final saturation = hsl.saturation.clamp(0.35, 0.98);
    return hsl.withLightness(lightness).withSaturation(saturation).toColor();
  }

  static List<_ScoredCluster> _scoreClusters(
    List<_ColorCluster> clusters,
    int totalSamples,
  ) {
    final scored = <_ScoredCluster>[];
    for (final cluster in clusters) {
      final color = cluster.color.toColor();
      final score = _scoreColor(color, cluster.count / totalSamples);
      scored.add(_ScoredCluster(color, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  static double _scoreColor(Color color, double dominance) {
    final rgb = _toUnitRgb(color);
    final redGreenness = rgb.r - rgb.g;
    final yellowBlueness = (rgb.r + rgb.g) / 2 - rgb.b;
    final chroma = math.sqrt(
      redGreenness * redGreenness + yellowBlueness * yellowBlueness,
    );
    final luminance = math.sqrt(
      0.299 * rgb.r * rgb.r +
          0.587 * rgb.g * rgb.g +
          0.114 * rgb.b * rgb.b,
    );
    final darkness = 1 - luminance;
    return chroma * _scoreColorfulness +
        darkness * _scoreDarkness +
        dominance * _scoreDominance;
  }

  static Color _sanitizeColor(Color color) {
    final rgb = _toUnitRgb(color);
    final luminance = math.sqrt(
      0.299 * rgb.r * rgb.r +
          0.587 * rgb.g * rgb.g +
          0.114 * rgb.b * rgb.b,
    );
    if (luminance <= _minLuminance || luminance >= _maxLuminance) {
      final target = luminance <= _minLuminance ? 0.18 : 0.82;
      return HSLColor.fromColor(color).withLightness(target).toColor();
    }
    return _boostContrast(color);
  }

  static Color _boostContrast(Color color) {
    final hsl = HSLColor.fromColor(color);
    final boosted = hsl
        .withSaturation((hsl.saturation * _saturationBoost).clamp(0, 1))
        .withLightness((hsl.lightness * _brightnessFactor).clamp(0, 1));
    return boosted.toColor();
  }

  static _UnitRgb _toUnitRgb(Color color) {
    return _UnitRgb(
      ((color.r * 255.0).round().clamp(0, 255)) / 255.0,
      ((color.g * 255.0).round().clamp(0, 255)) / 255.0,
      ((color.b * 255.0).round().clamp(0, 255)) / 255.0,
    );
  }

  static Color _bestOnColor(Color color) {
    return color.computeLuminance() > 0.6 ? Colors.black : Colors.white;
  }
}

class _ColorSample {
  _ColorSample(this.r, this.g, this.b);

  double r;
  double g;
  double b;

  void add(_ColorSample other) {
    r += other.r;
    g += other.g;
    b += other.b;
  }

  _ColorSample divide(int count) {
    return _ColorSample(r / count, g / count, b / count);
  }

  _ColorSample copy() => _ColorSample(r, g, b);

  double distanceSquared(_ColorSample other) {
    final dr = r - other.r;
    final dg = g - other.g;
    final db = b - other.b;
    return dr * dr + dg * dg + db * db;
  }

  Color toColor() {
    return Color.fromARGB(255, r.round(), g.round(), b.round());
  }
}

class _ColorCluster {
  _ColorCluster(this.color, this.count);

  final _ColorSample color;
  final int count;
}

class _ScoredCluster {
  _ScoredCluster(this.color, this.score);

  final Color color;
  final double score;
}

class _UnitRgb {
  _UnitRgb(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;
}
