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

/// Conservative, CPU-light v1 cropper.
///
/// It only removes large near-white outer margins. It deliberately does not
/// try to identify the product itself yet, so text, price and the product
/// image are preserved. If detection is uncertain, the original image is
/// returned unchanged.
class SmartCropService {
  static const _whiteThreshold = 247;
  static const _requiredContentRatio = 0.015;
  static const _maxCropRatio = 0.20;

  Future<SmartCropResult?> process(String fileUri) async {
    final uri = Uri.tryParse(fileUri);
    if (uri?.scheme != 'file') return null;

    final source = File(uri!.toFilePath());
    if (!await source.exists()) return null;

    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width < 32 || decoded.height < 32) return null;

    final bounds = _detectBounds(decoded);
    if (bounds == null) return null;

    final cropWidth = bounds[2] - bounds[0];
    final cropHeight = bounds[3] - bounds[1];
    final originalArea = decoded.width * decoded.height;
    final cropArea = cropWidth * cropHeight;
    final removedRatio = 1 - cropArea / originalArea;

    // Never make an aggressive decision in v1.
    if (removedRatio < 0.02 || removedRatio > 0.60) {
      return SmartCropResult(
        originalPath: source.path,
        outputPath: source.path,
        changed: false,
        confidence: 0.0,
        left: 0,
        top: 0,
        right: decoded.width,
        bottom: decoded.height,
      );
    }

    final output = img.copyCrop(
      decoded,
      x: bounds[0],
      y: bounds[1],
      width: cropWidth,
      height: cropHeight,
    );

    final outputPath = p.join(
      source.parent.path,
      '${p.basenameWithoutExtension(source.path)}_smart.jpg',
    );
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(img.encodeJpg(output, quality: 90), flush: true);

    final confidence = math.min(1.0, removedRatio / 0.20);
    return SmartCropResult(
      originalPath: source.path,
      outputPath: outputFile.path,
      changed: true,
      confidence: confidence,
      left: bounds[0],
      top: bounds[1],
      right: bounds[2],
      bottom: bounds[3],
    );
  }

  List<int>? _detectBounds(img.Image image) {
    final left = _scanColumn(image, fromLeft: true);
    final right = _scanColumn(image, fromLeft: false);
    final top = _scanRow(image, fromTop: true);
    final bottom = _scanRow(image, fromTop: false);

    final maxXTrim = (image.width * _maxCropRatio).floor();
    final maxYTrim = (image.height * _maxCropRatio).floor();
    final safeLeft = math.min(left, maxXTrim);
    final safeRight = math.min(right, maxXTrim);
    final safeTop = math.min(top, maxYTrim);
    final safeBottom = math.min(bottom, maxYTrim);

    final x1 = safeLeft;
    final y1 = safeTop;
    final x2 = image.width - safeRight;
    final y2 = image.height - safeBottom;
    if (x2 - x1 < image.width * 0.65 || y2 - y1 < image.height * 0.65) return null;
    return [x1, y1, x2, y2];
  }

  int _scanColumn(img.Image image, {required bool fromLeft}) {
    final max = (image.width * _maxCropRatio).floor();
    for (var offset = 0; offset < max; offset++) {
      final x = fromLeft ? offset : image.width - 1 - offset;
      if (!_isMostlyWhiteColumn(image, x)) return offset;
    }
    return max;
  }

  int _scanRow(img.Image image, {required bool fromTop}) {
    final max = (image.height * _maxCropRatio).floor();
    for (var offset = 0; offset < max; offset++) {
      final y = fromTop ? offset : image.height - 1 - offset;
      if (!_isMostlyWhiteRow(image, y)) return offset;
    }
    return max;
  }

  bool _isMostlyWhiteColumn(img.Image image, int x) {
    var dark = 0;
    final step = math.max(1, image.height ~/ 80);
    var samples = 0;
    for (var y = 0; y < image.height; y += step) {
      final pixel = image.getPixel(x, y);
      if (pixel.r.toInt() < _whiteThreshold ||
          pixel.g.toInt() < _whiteThreshold ||
          pixel.b.toInt() < _whiteThreshold) {
        dark++;
      }
      samples++;
    }
    return dark / samples < _requiredContentRatio;
  }

  bool _isMostlyWhiteRow(img.Image image, int y) {
    var dark = 0;
    final step = math.max(1, image.width ~/ 80);
    var samples = 0;
    for (var x = 0; x < image.width; x += step) {
      final pixel = image.getPixel(x, y);
      if (pixel.r.toInt() < _whiteThreshold ||
          pixel.g.toInt() < _whiteThreshold ||
          pixel.b.toInt() < _whiteThreshold) {
        dark++;
      }
      samples++;
    }
    return dark / samples < _requiredContentRatio;
  }
}
