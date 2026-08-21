import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class SmartCropResult {
  const SmartCropResult({
    required this.originalPath,
    required this.outputPath,
    required this.changed,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String originalPath;
  final String outputPath;
  final bool changed;
  final double confidence;
  final int left;
  final int top;
  final int right;
  final int bottom;
}

/// CPU-light screenshot cleaner for marketplace pages.
///
/// v2 no longer relies on white margins. It looks for UI chrome bands that
/// commonly surround a product page: a bottom navigation bar and a top promo
/// / application banner. Detection is deliberately conservative and falls
/// back to the original screenshot whenever the evidence is weak.
class SmartCropService {
  static const _version = 2;

  // The cropper never removes more than these fractions from any edge.
  static const _maxTopCrop = 0.22;
  static const _maxBottomCrop = 0.12;
  static const _maxSideCrop = 0.04;

  Future<SmartCropResult?> process(String fileUri) async {
    final uri = Uri.tryParse(fileUri);
    if (uri?.scheme != 'file') return null;

    final source = File(uri!.toFilePath());
    if (!await source.exists()) return null;

    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width < 64 || decoded.height < 64) return null;

    final bottom = _detectBottomNavigation(decoded);
    final top = _detectTopPromo(decoded, bottom);

    final maxTop = (decoded.height * _maxTopCrop).floor();
    final maxBottom = (decoded.height * _maxBottomCrop).floor();
    final maxSide = (decoded.width * _maxSideCrop).floor();

    final topCrop = top?.crop.clamp(0, maxTop) ?? 0;
    final bottomCrop = bottom?.crop.clamp(0, maxBottom) ?? 0;

    // Side trimming is intentionally tiny in v2. The marketplace screenshot
    // is usually full-width and side cropping risks losing the product.
    final left = maxSide > 0 ? _detectSideChrome(decoded, fromLeft: true, max: maxSide) : 0;
    final right = maxSide > 0 ? _detectSideChrome(decoded, fromLeft: false, max: maxSide) : 0;

    final x1 = left;
    final y1 = topCrop;
    final x2 = decoded.width - right;
    final y2 = decoded.height - bottomCrop;

    final cropWidth = x2 - x1;
    final cropHeight = y2 - y1;
    if (cropWidth < decoded.width * 0.90 || cropHeight < decoded.height * 0.65) {
      return _unchanged(source, decoded);
    }

    final removedRatio = 1 - (cropWidth * cropHeight) / (decoded.width * decoded.height);
    final confidence = _confidence(top, bottom, removedRatio);
    if (removedRatio < 0.025 || confidence < 0.62) {
      return _unchanged(source, decoded, confidence: confidence);
    }

    final output = img.copyCrop(
      decoded,
      x: x1,
      y: y1,
      width: cropWidth,
      height: cropHeight,
    );

    final outputPath = p.join(
      source.parent.path,
      '${p.basenameWithoutExtension(source.path)}_smart_v$_version.jpg',
    );
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(img.encodeJpg(output, quality: 92), flush: true);

    return SmartCropResult(
      originalPath: source.path,
      outputPath: outputFile.path,
      changed: true,
      confidence: confidence,
      left: x1,
      top: y1,
      right: x2,
      bottom: y2,
    );
  }

  SmartCropResult _unchanged(File source, img.Image image, {double confidence = 0}) => SmartCropResult(
        originalPath: source.path,
        outputPath: source.path,
        changed: false,
        confidence: confidence,
        left: 0,
        top: 0,
        right: image.width,
        bottom: image.height,
      );

  double _confidence(_Band? top, _Band? bottom, double removedRatio) {
    var score = 0.0;
    if (top != null) score += top.confidence * 0.55;
    if (bottom != null) score += bottom.confidence * 0.35;
    if (removedRatio >= 0.05) score += 0.10;
    return score.clamp(0.0, 1.0);
  }

  _Band? _detectBottomNavigation(img.Image image) {
    // Ozon's bottom navigation is a shallow, mostly light band containing
    // several dark icon/text clusters spread across the width. We sample rows
    // instead of every pixel to keep CPU usage low.
    final start = (image.height * 0.84).floor();
    final end = image.height - 2;
    _Band? best;

    for (var y = start; y < end; y += math.max(2, image.height ~/ 320)) {
      final stats = _rowStats(image, y);
      if (stats.lightRatio < 0.72 || stats.darkRatio < 0.015 || stats.darkRatio > 0.28) continue;

      final bandHeight = image.height - y;
      if (bandHeight < image.height * 0.035 || bandHeight > image.height * 0.12) continue;

      final clusterScore = _horizontalClusterScore(image, y, image.height - 1);
      if (clusterScore < 0.45) continue;

      final confidence = (0.45 * stats.lightRatio + 0.35 * clusterScore + 0.20 * (1 - stats.darkRatio)).clamp(0.0, 1.0);
      if (best == null || confidence > best.confidence) {
        best = _Band(crop: bandHeight, confidence: confidence);
      }
    }
    return best;
  }

  _Band? _detectTopPromo(img.Image image, _Band? bottom) {
    // Search only the upper part. We look for a wide, bounded visual block
    // followed by a transition into normal page content. This catches the
    // common "open in Ozon / promo" banner without assuming its exact color.
    final maxY = (image.height * _maxTopCrop).floor();
    final bottomLimit = math.min(maxY, (image.height * 0.34).floor());
    final step = math.max(2, image.height ~/ 320);
    _Band? best;

    for (var y = (image.height * 0.035).floor(); y < bottomLimit; y += step) {
      final above = _rowStats(image, y);
      final belowY = math.min(image.height - 1, y + math.max(8, image.height ~/ 45));
      final below = _rowStats(image, belowY);

      // A promo band tends to have noticeably different luminance/variance
      // from the content immediately below it. Avoid plain headers by requiring
      // enough horizontal visual structure in the band.
      final varianceDelta = (above.lumaVariance - below.lumaVariance).abs();
      final colorDelta = (above.colorfulness - below.colorfulness).abs();
      final structure = _horizontalClusterScore(image, math.max(0, y - 2), belowY);
      final score = (varianceDelta * 2.4 + colorDelta * 1.8 + structure * 0.45).clamp(0.0, 1.0);
      if (score < 0.50) continue;

      // Do not crop through the probable product region. A top crop should
      // remain modest unless the evidence is particularly strong.
      final crop = y;
      if (crop < image.height * 0.055 || crop > maxY) continue;
      final confidence = math.min(0.96, score * (crop / image.height > 0.08 ? 1.0 : 0.82));
      if (best == null || confidence > best.confidence) {
        best = _Band(crop: crop, confidence: confidence);
      }
    }

    return best;
  }

  int _detectSideChrome(img.Image image, {required bool fromLeft, required int max}) {
    // Only remove a side strip when it is consistently near-uniform. This is
    // mostly useful for browser/WebView gutters, not marketplace content.
    for (var offset = 0; offset < max; offset++) {
      final x = fromLeft ? offset : image.width - 1 - offset;
      final stats = _columnStats(image, x);
      if (stats.lightRatio < 0.94) return offset;
    }
    return 0;
  }

  _RowStats _rowStats(img.Image image, int y) {
    var light = 0;
    var dark = 0;
    var lumaSum = 0.0;
    var lumaSq = 0.0;
    var colorSum = 0.0;
    final step = math.max(1, image.width ~/ 120);
    var samples = 0;

    for (var x = 0; x < image.width; x += step) {
      final px = image.getPixel(x, y);
      final r = px.r.toDouble();
      final g = px.g.toDouble();
      final b = px.b.toDouble();
      final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
      if (luma > 0.92) light++;
      if (luma < 0.32) dark++;
      final maxChannel = math.max(r, math.max(g, b));
      final minChannel = math.min(r, math.min(g, b));
      colorSum += (maxChannel - minChannel) / 255.0;
      lumaSum += luma;
      lumaSq += luma * luma;
      samples++;
    }

    final mean = samples == 0 ? 0.0 : lumaSum / samples;
    final variance = samples == 0 ? 0.0 : math.max(0.0, lumaSq / samples - mean * mean);
    return _RowStats(
      lightRatio: samples == 0 ? 0 : light / samples,
      darkRatio: samples == 0 ? 0 : dark / samples,
      lumaVariance: variance,
      colorfulness: samples == 0 ? 0 : colorSum / samples,
    );
  }

  _RowStats _columnStats(img.Image image, int x) {
    var light = 0;
    final step = math.max(1, image.height ~/ 120);
    var samples = 0;
    for (var y = 0; y < image.height; y += step) {
      final px = image.getPixel(x, y);
      final luma = (0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b) / 255.0;
      if (luma > 0.92) light++;
      samples++;
    }
    return _RowStats(lightRatio: samples == 0 ? 0 : light / samples, darkRatio: 0, lumaVariance: 0, colorfulness: 0);
  }

  double _horizontalClusterScore(img.Image image, int y1, int y2) {
    final width = image.width;
    final stepX = math.max(1, width ~/ 100);
    final stepY = math.max(1, (y2 - y1) ~/ 20);
    var transitions = 0;
    var samples = 0;
    var previousDark = false;

    for (var y = y1; y <= y2; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final px = image.getPixel(x, y);
        final luma = (0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b) / 255.0;
        final dark = luma < 0.42;
        if (dark != previousDark) transitions++;
        previousDark = dark;
        samples++;
      }
    }
    if (samples == 0) return 0;
    return (transitions / samples * 4.0).clamp(0.0, 1.0);
  }
}

class _Band {
  const _Band({required this.crop, required this.confidence});
  final int crop;
  final double confidence;
}

class _RowStats {
  const _RowStats({required this.lightRatio, required this.darkRatio, required this.lumaVariance, required this.colorfulness});
  final double lightRatio;
  final double darkRatio;
  final double lumaVariance;
  final double colorfulness;
}
