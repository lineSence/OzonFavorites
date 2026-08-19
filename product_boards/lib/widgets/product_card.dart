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
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: product.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxWidth.isFinite ? constraints.maxWidth.clamp(0.0, 340.0) : 340.0;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: double.infinity,
                      height: size,
                      child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                          ? _productImage(product.imageUrl!, fit: BoxFit.cover, referer: product.url)
                          : const PlaceholderImage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 9),
              Text(
                product.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.16),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (product.price != null)
                    Text(
                      '${product.price!.toStringAsFixed(0)} ${product.currency}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  if (product.priceDrop == true) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.trending_down_rounded, size: 15, color: scheme.primary),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                product.source,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _productImage(String value, {BoxFit fit = BoxFit.cover, String? referer}) {
  final uri = Uri.tryParse(value);
  if (uri?.scheme == 'file') {
    return Image.file(
      File(uri!.toFilePath()),
      fit: fit,
      errorBuilder: (_, error, stackTrace) => const PlaceholderImage(),
    );
  }
  return Image.network(
    value,
    fit: fit,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    },
    errorBuilder: (_, error, stackTrace) => const PlaceholderImage(),
  );
}

class PlaceholderImage extends StatelessWidget {
  const PlaceholderImage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
      child: Center(
        child: Icon(Icons.image_outlined, size: 38, color: scheme.onSurfaceVariant.withValues(alpha: .45)),
      ),
    );
  }
}

class ProductListTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ProductListTile({super.key, required this.product, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                      ? _productImage(product.imageUrl!, fit: BoxFit.cover, referer: product.url)
                      : const PlaceholderImage(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.15)),
                    const SizedBox(height: 7),
                    if (product.price != null)
                      Text('${product.price!.toStringAsFixed(0)} ${product.currency}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (product.priceDrop == true) ...[
                      const SizedBox(height: 2),
                      Row(children: [Icon(Icons.trending_down_rounded, size: 15, color: scheme.primary), const SizedBox(width: 4), Text('Цена снизилась', style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600))]),
                    ],
                    const SizedBox(height: 3),
                    Text(product.source, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
