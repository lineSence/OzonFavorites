import 'package:flutter/material.dart';

import '../models/archive_item.dart';
import '../services/smart_sort_service.dart';
import '../repositories/archive_repository.dart';

class SmartSortPage extends StatefulWidget {
  const SmartSortPage({super.key, required this.repository});
  final ArchiveRepository repository;

  @override
  State<SmartSortPage> createState() => _SmartSortPageState();
}

class _SmartSortPageState extends State<SmartSortPage> {
  final SmartSortService _service = SmartSortService();
  List<ArchiveItem> _items = const [];
  List<SmartSortResult> _results = const [];
  List<String> _categories = const [];
  bool _loading = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.getAllItems();
      final categories = await widget.repository.getCategories();
      if (!mounted) return;
      setState(() {
        _items = items;
        _categories = categories;
        _loading = false;
      });
      if (items.isNotEmpty) {
        final results = await _service.classifyAll(items, categories: categories);
        if (mounted) setState(() => _results = results);
      }
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

  Future<void> _apply() async {
    if (_applying) return;
    final confident = _results.where((r) => r.isConfident).toList(growable: false);
    if (confident.isEmpty) return;
    setState(() => _applying = true);
    try {
      for (final result in confident) {
        await widget.repository.updateCategory(result.itemId, result.category);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Распределено: ${confident.length}')),
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Умная сортировка'),
        actions: [
          if (_results.any((r) => r.isConfident))
            IconButton(
              onPressed: _applying ? null : _apply,
              icon: _applying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              tooltip: 'Применить уверенные результаты',
            ),
        ],
      ),
      body: _results.isEmpty
          ? const Center(child: Text('Нет элементов для сортировки'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _groups.entries.map((entry) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    title: Text(entry.key),
                    subtitle: Text('${entry.value.length} элементов'),
                    children: entry.value.map((result) {
                      final item = _items.cast<ArchiveItem?>().firstWhere(
                        (candidate) => candidate?.id == result.itemId,
                        orElse: () => null,
                      );
                      return ListTile(
                        title: Text(item?.title ?? result.itemId),
                        subtitle: Text('${result.confidence}% • ${result.reason}'),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
