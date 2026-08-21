import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class SmartCropResult {
  const SmartCropResult({required this.originalPath, required this.outputPath, required this.changed, required this.confidence, required this.left, required this.top, required this.right, required this.bottom});
  final String originalPath;
  final String outputPath;
  final bool changed;
  final double confidence;
  final int left;
  final int top;
  final int right;
  final int bottom;
}

/// Conservative CPU-only screenshot cleaner. It only removes obvious bright
/// top/bottom chrome and otherwise keeps the original image unchanged.
class SmartCropService {
  static const _version = 2;

  Future<SmartCropResult?> process(String fileUri) async {
    final uri = Uri.tryParse(fileUri);
    if (uri?.scheme != 'file') return null;
    final source = File(uri!.toFilePath());
    if (!await source.exists()) return null;
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null || decoded.width < 64 || decoded.height < 64) return null;

    final top = _brightBandFromTop(decoded);
    final bottom = _brightBandFromBottom(decoded);
    final maxTop = (decoded.height * .12).floor();
    final maxBottom = (decoded.height * .12).floor();
    final topCrop = math.min(top, maxTop);
    final bottomCrop = math.min(bottom, maxBottom);
    final width = decoded.width;
    final height = decoded.height - topCrop - bottomCrop;
    if (height < decoded.height * .75 || topCrop + bottomCrop < decoded.height * .025) {
      return SmartCropResult(originalPath: source.path, outputPath: source.path, changed: false, confidence: 0, left: 0, top: 0, right: width, bottom: decoded.height);
    }

    final cropped = img.copyCrop(decoded, x: 0, y: topCrop, width: width, height: height);
    final outputPath = p.join(source.parent.path, '${p.basenameWithoutExtension(source.path)}_smart_v$_version.jpg');
    await File(outputPath).writeAsBytes(img.encodeJpg(cropped, quality: 92), flush: true);
    final confidence = ((topCrop + bottomCrop) / decoded.height).clamp(0.0, .25).toDouble() / .25;
    return SmartCropResult(originalPath: source.path, outputPath: outputPath, changed: true, confidence: confidence, left: 0, top: topCrop, right: width, bottom: decoded.height - bottomCrop);
  }

  int _brightBandFromTop(img.Image image) {
    final max = (image.height * .12).floor();
    for (var y = 4; y < max; y += math.max(2, image.height ~/ 160)) {
      if (_lightRatio(image, y) < .94) return y < image.height * .055 ? 0 : y;
    }
    return 0;
  }

  int _brightBandFromBottom(img.Image image) {
    final max = (image.height * .12).floor();
    for (var offset = 4; offset < max; offset += math.max(2, image.height ~/ 160)) {
      final y = image.height - 1 - offset;
      if (_lightRatio(image, y) < .94) return offset < image.height * .035 ? 0 : offset;
    }
    return 0;
  }

  double _lightRatio(img.Image image, int y) {
    final step = math.max(1, image.width ~/ 120);
    var light = 0;
    var count = 0;
    for (var x = 0; x < image.width; x += step) {
      final px = image.getPixel(x, y);
      final luma = (.2126 * px.r + .7152 * px.g + .0722 * px.b) / 255;
      if (luma > .92) light++;
      count++;
    }
    return count == 0 ? 0 : light / count;
  }
}
