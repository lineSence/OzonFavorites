import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/archive_item.dart';
import '../models/category.dart';
import '../repositories/archive_repository.dart';
import '../services/metadata_queue.dart';
import '../widgets/archive_image.dart';
import 'edit_archive_item_page.dart';

class ArchiveItemPage extends StatelessWidget {
  const ArchiveItemPage({super.key, required this.repository, required this.queue, required this.item, required this.categories});

  final ArchiveRepository repository;
  final MetadataQueue queue;
  final ArchiveItem item;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Ссылка'),
          actions: [
            IconButton(onPressed: () => _move(context), icon: const Icon(Icons.north_east), tooltip: 'Переместить'),
            IconButton(onPressed: () => _edit(context), icon: const Icon(Icons.edit_outlined), tooltip: 'Редактировать'),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ArchiveImage(value: item.imageUrl, height: 340, borderRadius: BorderRadius.circular(20)),
            const SizedBox(height: 18),
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (item.note.isNotEmpty) ...[const SizedBox(height: 22), const Text('Заметка', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(item.note)],
            const SizedBox(height: 18),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.folder_outlined), title: Text(item.categoryId == null ? 'Неразобранное' : _categoryName(item.categoryId))),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(item.url, maxLines: 3, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Открыть')),
            if (item.metadataStatus != MetadataStatus.success) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Не все метаданные удалось получить автоматически. Ссылка сохранена.')),
          ],
        ),
      );

  String _categoryName(String? id) {
    for (final category in categories) {
      if (category.id == id) return category.name;
    }
    return 'Подборка';
  }

  Future<void> _edit(BuildContext context) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: repository, queue: queue, item: item)));
    if (context.mounted && result != null) Navigator.pop(context, result);
  }

  Future<void> _move(BuildContext context) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Переместить', style: TextStyle(fontWeight: FontWeight.w800))),
        if (item.categoryId != null) ListTile(title: const Text('Неразобранное'), onTap: () => Navigator.pop(context, '__none__')),
        ...categories.where((c) => c.id != item.categoryId).map((c) => ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c.id))),
      ])),
    );
    if (!context.mounted || value == null) return;
    final updated = item.copyWith(categoryId: value == '__none__' ? null : value, updatedAt: DateTime.now());
    await repository.upsertItem(updated);
    if (context.mounted) Navigator.pop(context, updated);
  }
}
