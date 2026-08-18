import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/price_point.dart';
import '../models/product.dart';
import '../models/tag.dart';
import '../repositories/product_repository.dart';
import '../services/price_tracker.dart';
import '../widgets/price_chart.dart';
import '../widgets/product_card.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product, this.tags = const [], this.repository});
  final Product product;
  final List<Tag> tags;
  final ProductRepository? repository;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
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
      if (mounted) setState(() => loadingHistory = false);
      return;
    }
    final loadedHistory = await repo.getPriceHistory(current.id);
    if (mounted) {
      setState(() {
        history = loadedHistory;
        loadingHistory = false;
      });
    }
  }

  List<Tag> get _productTags {
    final byId = {for (final tag in widget.tags) tag.id: tag};
    return current.tagIds.map((id) => byId[id]).whereType<Tag>().toList();
  }

  Future<void> _refreshPrice() async {
    final repo = widget.repository;
    if (repo == null || updatingPrice) return;
    setState(() => updatingPrice = true);
    final result = await PriceTracker(repository: repo).updatePrice(current);
    final products = await repo.getProducts();
    final updated = products.firstWhere((item) => item.id == current.id, orElse: () => current);
    final updatedHistory = await repo.getPriceHistory(current.id);
    if (!mounted) return;
    setState(() {
      current = updated;
      history = updatedHistory;
      updatingPrice = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_updateMessage(result))));
  }

  String _updateMessage(PriceUpdateResult result) => switch (result.status) {
        PriceUpdateStatus.updated => 'Цена обновлена: ${result.newPrice?.toStringAsFixed(0) ?? ''}',
        PriceUpdateStatus.unchanged => 'Цена не изменилась',
        PriceUpdateStatus.noPrice => 'Цена на странице не найдена',
        PriceUpdateStatus.failed => 'Не удалось обновить цену (сеть или сайт)',
      };

  Widget _image() {
    final value = current.imageUrl;
    if (value == null || value.isEmpty) return const PlaceholderImage();
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'file') {
      return Image.file(
        File(uri!.toFilePath()),
        fit: BoxFit.contain,
        errorBuilder: (_, error, stackTrace) => const PlaceholderImage(),
      );
    }
    return Image.network(
      value,
      fit: BoxFit.contain,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
        'Referer': current.url,
      },
      errorBuilder: (_, error, stackTrace) => const PlaceholderImage(),
    );
  }

  Future<void> _openSite() async {
    final uri = Uri.tryParse(current.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(current.source, style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        actions: [
          IconButton(tooltip: 'Открыть сайт', onPressed: _openSite, icon: const Icon(Icons.open_in_new_rounded)),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  color: scheme.surfaceContainerHighest,
                  height: 380,
                  alignment: Alignment.center,
                  child: _image(),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(current.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.12)),
                const SizedBox(height: 12),
                if (current.price != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${current.price!.toStringAsFixed(0)} ${current.currency}', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.5)),
                      if (current.priceDrop == true) ...[
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('↓ цена снизилась', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                      child: Text(current.source, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (current.quantity > 1) ...[
                      const SizedBox(width: 8),
                      Text('×${current.quantity}', style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _openSite,
                  icon: const Icon(Icons.arrow_outward_rounded),
                  label: Text('Открыть в ${current.source}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
                if (current.note.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Заметка', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                    child: Text(current.note, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
                  ),
                ],
                if (_productTags.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Теги', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _productTags.map((tag) => Chip(label: Text('#${tag.name}'), visualDensity: VisualDensity.compact)).toList(),
                  ),
                ],
                const SizedBox(height: 28),
                if (loadingHistory)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: CircularProgressIndicator()))
                else if (history.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('История цены', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text('${history.length} точек', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(18)),
                    child: PriceChart(points: history),
                  ),
                ],
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: updatingPrice ? null : _refreshPrice,
                  icon: updatingPrice ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
                  label: Text(updatingPrice ? 'Обновляю…' : 'Обновить цену'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
