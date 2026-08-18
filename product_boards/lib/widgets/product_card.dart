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
          if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
            AspectRatio(
              aspectRatio: 1,
              child: Image.network(product.imageUrl!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _PlaceholderImage()),
            )
          else
            const AspectRatio(aspectRatio: 1, child: _PlaceholderImage()),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, height: 1.15)),
              const SizedBox(height: 6),
              if (product.price != null)
                Text('${product.price!.toStringAsFixed(0)} ₽', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(product.source, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.grey.shade200,
        child: const Center(child: Icon(Icons.image_outlined, size: 42, color: Colors.black26)),
      );
}
