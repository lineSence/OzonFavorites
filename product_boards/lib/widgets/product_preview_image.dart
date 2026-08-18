import 'dart:io';

import 'package:flutter/material.dart';
import '../models/product_preview.dart';
import 'product_card.dart';

class ProductPreviewImage extends StatelessWidget {
  const ProductPreviewImage({super.key, required this.preview, this.fit = BoxFit.cover});

  final ProductPreview preview;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final value = preview.image;
    if (value == null || value.isEmpty) return const PlaceholderImage();
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'file') {
      return Image.file(File(uri!.toFilePath()), fit: fit, errorBuilder: (_, __, ___) => const PlaceholderImage());
    }
    return Image.network(
      value,
      fit: fit,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
        'Referer': preview.url.toString(),
      },
      errorBuilder: (_, __, ___) => const PlaceholderImage(),
    );
  }
}
