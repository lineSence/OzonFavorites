import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class SmartCropResult {
  const SmartCropResult({required this.originalPath, required this.outputPath, required this.changed, required this.confidence, required this.left, required this.top, required this.right, required this.bottom});
  final String originalPath, outputPath;
  final bool changed;
  final double confidence;
  final int left, top, right, bottom;
}

/// Smart Crop v2: removes probable marketplace UI chrome rather than relying
/// only on empty white margins. Ozon commonly has a promo/app banner at the
/// top and a bottom navigation bar; detection stays conservative when evidence
/// is weak and returns the original screenshot.
class SmartCropService {
  static const _version = 2;

  Future<SmartCropResult?> process(String fileUri) async {
    final uri = Uri.tryParse(fileUri);
    if (uri?.scheme != 'file') return null;
    final source = File(uri!.toFilePath());
    if (!await source.exists()) return null;
    final image = img.decodeImage(await source.readAsBytes());
    if (image == null || image.width < 64 || image.height < 64) return null;

    final top = _findTopChrome(image);
    final bottom = _findBottomChrome(image);
    final maxTop = (image.height * .22).floor();
    final maxBottom = (image.height * .12).floor();
    final topCrop = (top?.crop ?? 0).clamp(0, maxTop).toInt();
    final bottomCrop = (bottom?.crop ?? 0).clamp(0, maxBottom).toInt();
    final width = image.width;
    final height = image.height - topCrop - bottomCrop;
    final removed = 1 - (width * height) / (image.width * image.height);
    final confidence = ((top?.confidence ?? 0) * .58 + (bottom?.confidence ?? 0) * .42).clamp(0.0, 1.0).toDouble();

    if (height < image.height * .65 || removed < .025 || confidence < .62) {
      return SmartCropResult(originalPath: source.path, outputPath: source.path, changed: false, confidence: confidence, left: 0, top: 0, right: width, bottom: image.height);
    }

    final cropped = img.copyCrop(image, x: 0, y: topCrop, width: width, height: height);
    final outputPath = p.join(source.parent.path, '${p.basenameWithoutExtension(source.path)}_smart_v$_version.jpg');
    await File(outputPath).writeAsBytes(img.encodeJpg(cropped, quality: 92), flush: true);
    return SmartCropResult(originalPath: source.path, outputPath: outputPath, changed: true, confidence: confidence, left: 0, top: topCrop, right: width, bottom: image.height - bottomCrop);
  }

  _Band? _findBottomChrome(img.Image image) {
    final start = (image.height * .84).floor();
    _Band? best;
    final step = math.max(2, image.height ~/ 240).toInt();
    for (var y = start; y < image.height - 4; y += step) {
      final stats = _rowStats(image, y);
      final bandHeight = image.height - y;
      if (bandHeight < image.height * .035 || bandHeight > image.height * .12) continue;
      if (stats.light < .62 || stats.dark < .015 || stats.dark > .32) continue;
      final structure = _transitionScore(image, y, image.height - 1);
      if (structure < .22) continue;
      final confidence = (stats.light * .48 + structure * .37 + (1 - stats.dark) * .15).clamp(0.0, 1.0).toDouble();
      if (best == null || confidence > best.confidence) {
        best = _Band(bandHeight, confidence);
      }
    }
    return best;
  }

  _Band? _findTopChrome(img.Image image) {
    final max = (image.height * .22).floor();
    _Band? best;
    final step = math.max(2, image.height ~/ 240).toInt();
    for (var y = (image.height * .035).floor(); y < max; y += step) {
      final stats = _rowStats(image, y);
      final nextY = math.min(image.height - 1, y + math.max(10, image.height ~/ 45)).toInt();
      final below = _rowStats(image, nextY);
      final varianceDelta = (stats.variance - below.variance).abs();
      final colorDelta = (stats.color - below.color).abs();
      final structure = _transitionScore(image, y, nextY);
      final confidence = (varianceDelta * 3.0 + colorDelta * 2.0 + structure * .35).clamp(0.0, 1.0).toDouble();
      if (y < image.height * .055 || confidence < .52) continue;
      if (best == null || confidence > best.confidence) {
        best = _Band(y, confidence);
      }
    }
    return best;
  }

  _Stats _rowStats(img.Image image, int y) {
    final step = math.max(1, image.width ~/ 120).toInt();
    var light = 0, dark = 0, n = 0;
    var sum = 0.0, sumSq = 0.0, color = 0.0;
    for (var x = 0; x < image.width; x += step) {
      final px = image.getPixel(x, y);
      final r = px.r.toDouble(), g = px.g.toDouble(), b = px.b.toDouble();
      final l = (.2126 * r + .7152 * g + .0722 * b) / 255;
      if (l > .90) light++;
      if (l < .32) dark++;
      color += (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))) / 255;
      sum += l;
      sumSq += l * l;
      n++;
    }
    final mean = n == 0 ? 0 : sum / n;
    return _Stats(light: n == 0 ? 0 : light / n, dark: n == 0 ? 0 : dark / n, variance: n == 0 ? 0 : math.max(0.0, sumSq / n - mean * mean), color: n == 0 ? 0 : color / n);
  }

  double _transitionScore(img.Image image, int y1, int y2) {
    final sx = math.max(1, image.width ~/ 100).toInt();
    final sy = math.max(1, (y2 - y1) ~/ 20).toInt();
    var transitions = 0, n = 0;
    var previous = false;
    for (var y = y1; y <= y2; y += sy) {
      for (var x = 0; x < image.width; x += sx) {
        final px = image.getPixel(x, y);
        final l = (.2126 * px.r + .7152 * px.g + .0722 * px.b) / 255;
        final dark = l < .42;
        if (dark != previous) transitions++;
        previous = dark;
        n++;
      }
    }
    return n == 0 ? 0 : (transitions / n * 4).clamp(0.0, 1.0).toDouble();
  }
}

class _Band {
  const _Band(this.crop, this.confidence);
  final int crop;
  final double confidence;
}

class _Stats {
  const _Stats({required this.light, required this.dark, required this.variance, required this.color});
  final double light, dark, variance, color;
}
