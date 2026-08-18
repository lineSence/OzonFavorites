import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/product.dart';

class ProductDetailScreen extends StatelessWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Товар')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
          ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(product.imageUrl!, height: 340, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(height: 340, color: Colors.grey.shade200, child: const Icon(Icons.image_outlined, size: 60))))
        else
          Container(height: 340, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.image_outlined, size: 60)),
        const SizedBox(height: 18),
        Text(product.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (product.price != null) ...[
          const SizedBox(height: 8),
          Text('${product.price!.toStringAsFixed(0)} ₽', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
        const SizedBox(height: 4),
        Text(product.source, style: const TextStyle(color: Colors.black54)),
        if (product.note.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('Заметка', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(product.note),
        ],
        if (product.tags.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(spacing: 8, runSpacing: 6, children: product.tags.map((t) => Chip(label: Text('#$t'))).toList()),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: () async {
            final uri = Uri.tryParse(product.url);
            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.open_in_new), label: Text('Открыть в ${product.source}'),
        ),
      ]),
    );
  }
}
