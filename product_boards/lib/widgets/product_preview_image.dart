import 'dart:io';

import 'package:flutter/material.dart';

import '../models/product_preview.dart';
import '../screens/image_diagnostics_screen.dart';

class ProductPreviewImage extends StatelessWidget {
  const ProductPreviewImage({super.key, required this.preview, this.fit = BoxFit.cover});

  final ProductPreview preview;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final value = preview.image;
    final image = value == null || value.isEmpty
        ? const PlaceholderImage()
        : _buildImage(value);

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.black.withValues(alpha: .48),
            shape: const CircleBorder(),
            child: PopupMenuButton<String>(
              tooltip: 'Диагностика изображения',
              icon: const Icon(Icons.bug_report_outlined, color: Colors.white, size: 20),
              onSelected: (value) {
                if (value == 'diagnostics') {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImageDiagnosticsScreen()));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'diagnostics', child: Text('Диагностика изображения')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(String value) {
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

class PlaceholderImage extends StatelessWidget {
  const PlaceholderImage({super.key});

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xffecece9),
        alignment: Alignment.center,
        child: const Text('🐈', style: TextStyle(fontSize: 52)),
      );
}
