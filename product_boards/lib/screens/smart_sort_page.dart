import 'package:flutter/material.dart';

import '../models/archive_item.dart';
import '../models/category.dart';
import '../repositories/archive_repository.dart';
import '../services/smart_sort_service.dart';

class SmartSortPage extends StatefulWidget {
  const SmartSortPage({super.key, required this.repository, required this.items});

  final ArchiveRepository repository;
  final List<ArchiveItem> items;

  @override
  State<SmartSortPage> createState() => _SmartSortPageState();
}

class _SmartSortPageState extends State<SmartSortPage> {
  final SmartSortService _service = SmartSortService();
  List<SmartSortResult> _results = const [];
  List<Category> _categories = const [];
  bool _loading = true;
  bool _applying = false;
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final categories = await widget.repository.getCategories();
      final results = _service.classifyAll(widget.items);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<SmartSortResult>> get _groups {
    final groups = <String, List<SmartSortResult>>{};
    for (final result in _results) {
      groups.putIfAbsent(result.category, () => []).add(result);
    }
    return groups;
  }

  List<SmartSortResult> get _confident => _results.where((r) => r.isConfident).toList(growable: false);
  List<SmartSortResult> get _review => _results.where((r) => !r.isConfident).toList(growable: false);

  Future<Category?> _categoryFor(String name) async {
    final existing = _categories.where((c) => c.name.trim().toLowerCase() == name.trim().toLowerCase());
    if (existing.isNotEmpty) return existing.first;

    final now = DateTime.now();
    final category = Category(
      id: widget.repository.newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await widget.repository.upsertCategory(category);
    if (mounted) setState(() => _categories = [..._categories, category]);
    return category;
  }

  Future<void> _confirm(SmartSortResult result) async {
    if (_busyIds.contains(result.item.id)) return;
    setState(() => _busyIds.add(result.item.id));
    try {
      final category = await _categoryFor(result.category);
      if (category == null) return;
      await widget.repository.assignCategory([result.item.id], category.id);
      if (!mounted) return;
      setState(() => _results = _results.where((r) => r.item.id != result.item.id).toList(growable: false));
      _snack('Подтверждено: ${result.category}');
    } catch (error) {
      if (mounted) _snack('Не удалось подтвердить: $error');
    } finally {
      if (mounted) setState(() => _busyIds.remove(result.item.id));
    }
  }

  void _reject(SmartSortResult result) {
    if (_busyIds.contains(result.item.id)) return;
    // Deliberately do not assign a category. The item remains in the
    // unparsed collection and disappears only from this Smart Sort session.
    setState(() => _results = _results.where((r) => r.item.id != result.item.id).toList(growable: false));
    _snack('Отклонено — товар остался в неразобранном');
  }

  Future<void> _apply() async {
    if (_applying || _confident.isEmpty) return;
    setState(() => _applying = true);
    try {
      for (final result in _confident) {
        final category = await _categoryFor(result.category);
        if (category != null) {
          await widget.repository.assignCategory([result.item.id], category.id);
        }
      }
      if (!mounted) return;
      final appliedIds = _confident.map((r) => r.item.id).toSet();
      setState(() => _results = _results.where((r) => !appliedIds.contains(r.item.id)).toList(growable: false));
      _snack('Автоматически распределено: ${appliedIds.length}');
    } catch (error) {
      if (mounted) _snack('Не удалось применить сортировку: $error');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Умная сортировка'),
        actions: [
          if (_confident.isNotEmpty)
            IconButton(
              onPressed: _applying ? null : _apply,
              icon: _applying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              tooltip: 'Применить уверенные результаты',
            ),
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Повторить анализ'),
        ],
      ),
      body: _results.isEmpty
          ? const Center(child: Text('Нет элементов для сортировки'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                if (_review.isNotEmpty) ...[
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: Text('Требуют подтверждения: ${_review.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('Категория выбрана автоматически, но уверенность классификатора низкая.'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ...groups.entries.map((entry) => _groupCard(entry.key, entry.value)),
              ],
            ),
      bottomNavigationBar: _confident.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _applying ? null : _apply,
                icon: _applying
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_applying ? 'Применяем...' : 'Разложить уверенные товары'),
              ),
            ),
    );
  }

  Widget _groupCard(String category, List<SmartSortResult> results) {
    final confidentCount = results.where((r) => r.isConfident).length;
    final reviewCount = results.length - confidentCount;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(_iconFor(category)),
        title: Text(category, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          reviewCount == 0
              ? '$confidentCount будут перемещены автоматически'
              : '$confidentCount автоматически · $reviewCount требуют подтверждения',
        ),
        children: results.map(_resultTile).toList(growable: false),
      ),
    );
  }

  Widget _resultTile(SmartSortResult result) {
    final busy = _busyIds.contains(result.item.id);
    final confidence = (result.score * 100).round();
    final isReview = !result.isConfident;
    return ListTile(
      title: Text(result.item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${confidence}% • ${result.matchedKeywords.isEmpty ? 'Нет явных совпадений' : result.matchedKeywords.join(', ')}',
      ),
      trailing: result.isConfident
          ? const Icon(Icons.check_circle_outline)
          : busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Подтвердить ${result.category}',
                      onPressed: () => _confirm(result),
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Отклонить',
                      onPressed: () => _reject(result),
                      icon: const Icon(Icons.cancel_outlined),
                    ),
                  ],
                ),
      leading: isReview
          ? const Icon(Icons.help_outline)
          : null,
    );
  }

  IconData _iconFor(String category) => switch (category) {
        'Одежда' => Icons.checkroom_outlined,
        'Обувь' => Icons.hiking_outlined,
        'Электроника' => Icons.devices_other_outlined,
        'Дом' => Icons.home_outlined,
        'Инструменты' => Icons.handyman_outlined,
        'Игры' => Icons.sports_esports_outlined,
        'Спорт' => Icons.fitness_center_outlined,
        'Красота' => Icons.face_retouching_natural_outlined,
        'Авто' => Icons.directions_car_outlined,
        _ => Icons.inventory_2_outlined,
      };
}
