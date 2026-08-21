import 'dart:io';

import 'package:flutter/material.dart';

class ArchiveImage extends StatelessWidget {
  const ArchiveImage({super.key, required this.value, this.height, this.borderRadius});

  final String? value;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final provider = imageProvider(value);
    final child = provider == null
        ? _placeholder()
        : Image(image: provider, height: height, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    final sized = height == null ? SizedBox.expand(child: child) : child;
    return borderRadius == null ? sized : ClipRRect(borderRadius: borderRadius!, child: sized);
  }

  Widget _placeholder() => Container(height: height, color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 64)));
}

ImageProvider<Object>? imageProvider(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri?.scheme == 'file') return FileImage(File(uri!.toFilePath()));
  return NetworkImage(value);
}
