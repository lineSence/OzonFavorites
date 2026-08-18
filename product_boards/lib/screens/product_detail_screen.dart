import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/price_point.dart';
import '../models/product.dart';
import '../models/tag.dart';
import '../repositories/product_repository.dart';
import '../services/price_tracker.dart';
import '../widgets/price_chart.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product, this.tags = const [], this.repository});
  final Product product;
  final List<Tag> tags;
  final ProductRepository? repository;
  @override State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product current = widget.product;
  List<PricePoint> history = const [];
  bool loadingHistory = true;
  bool updatingPrice = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final repo = widget.repository;
    if (repo == null) {
      loadingHistory = false;
      return;
    }
    final h = await repo.getPriceHistory(widget.product.id);
    if (mounted) setState(() { history = h; loadingHistory = false; });
  }

  List<Tag> get _productTags {
    final byId = {for (final t in widget.tags) t.id: t};
    return current.tagIds.map((id) => byId[id]).whereType<Tag>().toList();
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _refreshPrice() async {
    final repo = widget.repository;
    if (repo == null || updatingPrice) return;
    setState(() => updatingPrice = true);
    final result = await PriceTracker(repository: repo).updatePrice(current);
    final products = await repo.getProducts();
    final updated = products.firstWhere((e) => e.id == current.id, orElse: () => current);
    final h = await repo.getPriceHistory(current.id);
    if (!mounted) return;
    setState(() { current = updated; history = h; updatingPrice = false; });
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(_updateMessage(result))));
  }

  String _updateMessage(PriceUpdateResult r) => switch (r.status) {
        PriceUpdateStatus.updated => 'Цена обновлена: ${r.newPrice?.toStringAsFixed(0) ?? ''}',
        PriceUpdateStatus.unchanged => 'Цена не изменилась',
        PriceUpdateStatus.noPrice => 'Цена на странице не найдена',
        PriceUpdateStatus.failed => 'Не удалось обновить цену (сеть или сайт)',
      };

  Widget _imagePlaceholder() => Container(
        height: 340,
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.image_outlined, size: 60),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Товар')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (current.imageUrl != null && current.imageUrl!.isNotEmpty)
          ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(current.imageUrl!, height: 340, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imagePlaceholder()))
        else
          _imagePlaceholder(),
        const SizedBox(height: 18),
        Text(current.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (current.price != null) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('${current.price!.toStringAsFixed(0)} ${current.currency}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (current.priceDrop == true) ...[
              const SizedBox(width: 8),
              const Icon(Icons.trending_down, size: 18, color: Colors.green),
              const Text('снизилась', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
            ],
          ]),
        ],
        if (current.quantity > 1) ...[
          const SizedBox(height: 4),
          Text('Количество: ${current.quantity}', style: const TextStyle(color: Colors.black54)),
        ],
        if (current.comparisonUrl != null && current.comparisonUrl!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Сравнение цен: ${current.comparisonUrl}', style: const TextStyle(color: Colors.black54)),
        ],
        if (current.desiredPurchaseDate != null) ...[
          const SizedBox(height: 4),
          Text('Купить до: ${_formatDate(current.desiredPurchaseDate!)}', style: const TextStyle(color: Colors.black54)),
        ],
        const SizedBox(height: 4),
        Text(current.source, style: const TextStyle(color: Colors.black54)),
        if (current.note.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('Заметка', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(current.note),
        ],
        if (_productTags.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(spacing: 8, runSpacing: 6, children: _productTags.map((t) => Chip(label: Text('#${t.name}'))).toList()),
        ],
        const SizedBox(height: 20),
        if (loadingHistory)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Center(child: CircularProgressIndicator()))
        else if (history.isNotEmpty) ...[
          const Text('История цен', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          PriceChart(points: history),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: updatingPrice ? null : _refreshPrice,
          icon: updatingPrice ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          label: Text(updatingPrice ? 'Обновляю…' : 'Обновить цену'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final uri = Uri.tryParse(current.url);
            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.open_in_new), label: Text('Открыть в ${current.source}'),
        ),
      ]),
    );
  }
}
