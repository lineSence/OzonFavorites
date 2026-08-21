import 'dart:io';

import 'package:flutter/material.dart';

import '../models/archive_item.dart';

class ArchiveCard extends StatelessWidget {
  const ArchiveCard({super.key, required this.item, required this.onTap, required this.onAction, required this.selected, required this.selectionMode});

  final ArchiveItem item;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final bool selected;
  final bool selectionMode;

  ImageProvider<Object>? get _provider {
    final value = item.imageUrl;
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'file') return FileImage(File(uri!.toFilePath()));
    return NetworkImage(value);
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _image()),
              Padding(padding: const EdgeInsets.fromLTRB(12, 10, 44, 12), child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            if (!selectionMode) Positioned(right: 2, bottom: 2, child: IconButton(onPressed: onAction, icon: const Icon(Icons.north_east), tooltip: 'Переместить')),
            if (selectionMode) Positioned(top: 10, right: 10, child: Container(width: 28, height: 28, decoration: BoxDecoration(color: selected ? Colors.black : Colors.white70, shape: BoxShape.circle, border: Border.all(color: Colors.black38)), child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null)),
            if (item.metadataStatus == MetadataStatus.loading) const Positioned(left: 10, top: 10, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
      );

  Widget _image() {
    final provider = _provider;
    if (provider == null) return _placeholder();
    return Image(image: provider, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => _placeholder());
  }

  Widget _placeholder() => Container(color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 52)));
}
