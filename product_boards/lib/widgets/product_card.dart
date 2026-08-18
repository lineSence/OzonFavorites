import 'dart:io';

import 'package:flutter/material.dart';
import '../models/product.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ProductCard({super.key, required this.product, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.maxWidth.isFinite ? constraints.maxWidth.clamp(0.0, 320.0) : 320.0;
              return SizedBox(
                width: double.infinity,
                height: size,
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? _productImage(product.imageUrl!, fit: BoxFit.cover, referer: product.url)
                    : const PlaceholderImage(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.15)),
              const SizedBox(height: 6),
              if (product.price != null)
                Text('${product.price!.toStringAsFixed(0)} ${product.currency}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (product.priceDrop == true) ...[
                const SizedBox(height: 2),
                const Row(children: [Icon(Icons.trending_down, size: 13, color: Colors.green), SizedBox(width: 3), Text('снизилась', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))]),
              ],
              Text(product.source, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
            ]),
          ),
        ]),
      ),
    );
  }
}

Widget _productImage(String value, {BoxFit fit = BoxFit.cover, String? referer}) {
  final uri = Uri.tryParse(value);
  if (uri?.scheme == 'file') {
    return Image.file(File(uri!.toFilePath()), fit: fit, errorBuilder: (_, __, ___) => const PlaceholderImage());
  }
  return Image.network(
    value,
    fit: fit,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    },
    errorBuilder: (_, __, ___) => const PlaceholderImage(),
  );
}

class PlaceholderImage extends StatelessWidget {
  const PlaceholderImage({super.key});
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.grey.shade200,
        child: const Center(child: Icon(Icons.image_outlined, size: 42, color: Colors.black26)),
      );
}

class ProductListTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ProductListTile({super.key, required this.product, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        onTap: onTap,
        onLongPress: onLongPress,
        leading: SizedBox(
          width: 72,
          height: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                ? _productImage(product.imageUrl!, fit: BoxFit.cover, referer: product.url)
                : const PlaceholderImage(),
          ),
        ),
        title: Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (product.price != null)
              Text('${product.price!.toStringAsFixed(0)} ${product.currency}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (product.priceDrop == true)
              const Row(children: [Icon(Icons.trending_down, size: 13, color: Colors.green), SizedBox(width: 3), Text('снизилась', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))]),
            Text(product.source, style: const TextStyle(color: Colors.black54)),
          ]),
        ),
        isThreeLine: true,
      ),
    );
  }
}
