import 'package:flutter/material.dart';

import '../models/archive_item.dart';
import '../models/category.dart';
import '../repositories/archive_repository.dart';
import '../services/smart_sort_service.dart';

class SmartSortPage extends StatefulWidget {
  const SmartSortPage({
    super.key,
    required this.repository,
    required this.items,
  });

  final ArchiveRepository repository;
  final List<ArchiveItem> items;

  @override
  State<SmartSortPage> createState() => _SmartSortPageState();
}

class _SmartSortPageState extends State<SmartSortPage> {
  final _service = SmartSortService();
  late List<SmartSortResult> _results;
  List<Category> _categories = const [];
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _results = _service.classifyAll(widget.items);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.repository.getCategories();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {}
  }

  Map<String, List<SmartSortResult>> get _groups {
    final groups = <String, List<SmartSortResult>>{};
    for (final result in _results) {
      groups.putIfAbsent(result.category, () => []).add(result);
    }
    return groups;
  }

  Future<void> _apply() async {
    if (_applying) return;
    final confident = _results.where((r) => r.isConfident).toList(growable: false);
    if (confident.isEmpty) {
      _snack('Нет достаточно уверенных совпадений');
      return;
    }

    setState(() => _applying = true);
    try {
      final byName = <String, Category>{
        for (final category in _categories) category.name.trim().toLowerCase(): category,
      };

      for (final group in confident.map((r) => r.category).toSet()) {
        if (byName.containsKey(group.toLowerCase())) continue;
        final now = DateTime.now();
        final category = Category(
          id: widget.repository.newId(),
          name: group,
          createdAt: now,
          updatedAt: now,
        );
        await widget.repository.upsertCategory(category);
        byName[group.toLowerCase()] = category;
      }

      for (final group in confident.map((r) => r.category).toSet()) {
        final category = byName[group.toLowerCase()];
        if (category == null) continue;
        final ids = confident.where((r) => r.category == group).map((r) => r.item.id).toSet();
        await widget.repository.assignCategory(ids, category.id);
      }

      if (!mounted) return;
      _snack('Распознано и разложено: ${confident.length}');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _applying = false);
        _snack('Не удалось применить сортировку: $error');
      }
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Умная сортировка'),
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              tooltip: 'Повторить анализ',
              onPressed: () => setState(() => _results = _service.classifyAll(widget.items)),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: widget.items.isEmpty
          ? const Center(child: Text('В текущей подборке нет товаров'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                const Text(
                  'Экспериментальный локальный классификатор',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Анализируются только название, заметка и ссылка. Данные никуда не отправляются.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                ...groups.entries.map((entry) => _groupCard(entry.key, entry.value)),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: _applying ? null : _apply,
          icon: _applying
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(_applying ? 'Применяем...' : 'Применить сортировку'),
        ),
      ),
    );
  }

  Widget _groupCard(String category, List<SmartSortResult> results) {
    final confidentCount = results.where((r) => r.isConfident).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(_iconFor(category)),
        title: Text(category, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$confidentCount из ${results.length} будут перемещены'),
        children: results
            .map(
              (result) => ListTile(
                dense: true,
                title: Text(result.item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  result.matchedKeywords.isEmpty
                      ? 'Нет совпадений — останется на месте'
                      : 'Совпадение: ${result.matchedKeywords.join(', ')} · ${(result.score * 100).round()}%',
                ),
                trailing: result.isConfident ? const Icon(Icons.check_circle_outline) : const Icon(Icons.help_outline),
              ),
            )
            .toList(growable: false),
      ),
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
