import 'package:flutter/material.dart';

import '../models/archive_item.dart';
import '../models/category.dart';
import '../repositories/archive_repository.dart';
import '../services/metadata_queue.dart';

class EditArchiveItemPage extends StatefulWidget {
  const EditArchiveItemPage({super.key, required this.repository, required this.queue, required this.item});

  final ArchiveRepository repository;
  final MetadataQueue queue;
  final ArchiveItem item;

  @override
  State<EditArchiveItemPage> createState() => _EditArchiveItemPageState();
}

class _EditArchiveItemPageState extends State<EditArchiveItemPage> {
  late final TextEditingController _titleController = TextEditingController(text: widget.item.title);
  late final TextEditingController _noteController = TextEditingController(text: widget.item.note);
  String? _categoryId;
  bool _titleTouched = false;
  List<Category> _categories = const [];

  @override
  void initState() {
    super.initState();
    _categoryId = widget.item.categoryId;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final value = await widget.repository.getCategories();
      if (mounted) setState(() => _categories = value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _chooseCategory() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Выбрать подборку', style: TextStyle(fontWeight: FontWeight.w800))),
        ListTile(title: const Text('Не выбирать'), onTap: () => Navigator.pop(context, '__none__')),
        ..._categories.map((c) => ListTile(title: Text(c.name), trailing: c.id == _categoryId ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, c.id))),
      ])),
    );
    if (!mounted || value == null) return;
    setState(() => _categoryId = value == '__none__' ? null : value);
  }

  Future<void> _save() async {
    final entered = _titleController.text.trim();
    final result = widget.item.copyWith(
      title: entered.isEmpty ? 'Без названия' : entered,
      titleSource: (_titleTouched || widget.item.titleSource == TitleSource.manual) ? TitleSource.manual : widget.item.titleSource,
      note: _noteController.text.trim(),
      categoryId: _categoryId,
      updatedAt: DateTime.now(),
    );
    await widget.repository.upsertItem(result);
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить эту ссылку?'),
        content: const Text('Объект будет удалён из архива.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repository.deleteItem(widget.item.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categoryName = _categoryId == null ? 'Неразобранное' : _categories.firstWhereOrNull((c) => c.id == _categoryId)?.name ?? 'Подборка';
    return Scaffold(
      appBar: AppBar(title: const Text('Редактировать')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 180, child: Center(child: Icon(Icons.image_outlined, size: 56))),
        const SizedBox(height: 18),
        TextField(controller: _titleController, onChanged: (_) => _titleTouched = true, decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _noteController, maxLines: 4, decoration: const InputDecoration(labelText: 'Заметка', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Подборка', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(categoryName), trailing: const Icon(Icons.chevron_right), onTap: _chooseCategory),
        const SizedBox(height: 12),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _delete, child: const Text('Удалить')),
      ]),
    );
  }
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
