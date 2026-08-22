import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/archive_item.dart';
import '../models/category.dart';
import '../repositories/archive_repository.dart';
import '../services/metadata_queue.dart';
import '../services/url_normalizer.dart';
import '../widgets/archive_card.dart';
import 'archive_item_page.dart';
import 'edit_archive_item_page.dart';
import 'smart_sort_page.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.repository, required this.queue, required this.sharedData, required this.onSharedDataConsumed});
  final ArchiveRepository repository;
  final MetadataQueue queue;
  final Map<Object?, Object?>? sharedData;
  final VoidCallback onSharedDataConsumed;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  static const _shareChannel = MethodChannel('product_boards/share');
  final _normalizer = UrlNormalizer();
  List<ArchiveItem> _items = const [];
  List<Category> _categories = const [];
  String? _categoryId;
  bool _loading = true;
  String? _error;
  bool _selectionMode = false;
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeShare());
  }

  @override
  void didUpdateWidget(covariant ArchiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedData != null && widget.sharedData != oldWidget.sharedData) unawaited(_consumeShare());
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final categories = await widget.repository.getCategories();
      final items = await widget.repository.getItems(categoryId: _categoryId);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _items = items;
        _loading = false;
        _error = null;
        _selected.removeWhere((id) => !items.any((item) => item.id == id));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Future<void> _consumeShare() async {
    final data = widget.sharedData;
    final url = data?['url']?.toString().trim();
    if (url == null || url.isEmpty) return;
    final sharedImage = data?['imagePath']?.toString().trim();
    final added = await _addUrl(url, initialTitle: data?['title']?.toString().trim(), initialImageUri: sharedImage);
    if (added && mounted) widget.onSharedDataConsumed();
  }

  Future<String?> _resolveScreenshot(String url) async {
    try {
      final result = await _shareChannel.invokeMethod<Object?>('resolveProduct', {'url': url});
      if (result is! Map) return null;
      final value = result['screenshotUri']?.toString().trim();
      if (value == null || value.isEmpty || !value.startsWith('file:')) return null;
      return value;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveScreenshotInBackground(ArchiveItem initialItem) async {
    if (initialItem.imageUrl?.startsWith('file:') == true) return;
    try {
      final screenshot = await _resolveScreenshot(initialItem.url);
      final current = await widget.repository.getItems();
      ArchiveItem? item;
      for (final candidate in current) {
        if (candidate.id == initialItem.id) {
          item = candidate;
          break;
        }
      }
      if (item == null) return;
      final updated = screenshot == null
          ? item.copyWith(imageUrl: null, imageStatus: ImageStatus.failed, updatedAt: DateTime.now())
          : item.copyWith(imageUrl: screenshot, imageStatus: ImageStatus.success, updatedAt: DateTime.now());
      await widget.repository.upsertItem(updated);
      if (mounted) await _reload();
    } catch (_) {
      // Import itself has already succeeded. A screenshot failure must not
      // delay the user or turn a successful import into an error.
    }
  }

  Future<bool> _addUrl(String raw, {String? initialTitle, String? initialImageUri}) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      _snack('Нужна ссылка http/https');
      return false;
    }
    try {
      final duplicates = await widget.repository.findByNormalizedUrl(_normalizer.normalize(uri.toString()));
      if (duplicates.isNotEmpty && !await _confirmDuplicate(duplicates)) return false;
      final now = DateTime.now();
      final hasInitialImage = initialImageUri?.startsWith('file:') == true;
      final item = ArchiveItem(
        id: widget.repository.newId(),
        url: uri.toString(),
        title: initialTitle?.isNotEmpty == true ? initialTitle! : '...',
        titleSource: TitleSource.automatic,
        imageUrl: hasInitialImage ? initialImageUri : null,
        imageStatus: hasInitialImage ? ImageStatus.success : ImageStatus.loading,
        note: '',
        categoryId: _categoryId,
        metadataStatus: MetadataStatus.loading,
        createdAt: now,
        updatedAt: now,
      );
      await widget.repository.upsertItem(item);
      await _reload();

      // Import is intentionally non-blocking. The card is available immediately;
      // screenshot and metadata enrichment continue in the background.
      if (!hasInitialImage) unawaited(_resolveScreenshotInBackground(item));
      unawaited(widget.queue.enqueue(item));
      return true;
    } catch (error) {
      _snack('Не удалось добавить ссылку: $error');
      return false;
    }
  }

  Future<bool> _confirmDuplicate(List<ArchiveItem> duplicates) async {
    final names = duplicates.map((item) => _categoryName(item.categoryId)).join('\n• ');
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Эта ссылка уже есть'),
            content: Text('• $names\n\nСоздать новый независимый объект?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить копию')),
            ],
          ),
        ) ?? false;
  }

  String _categoryName(String? id) {
    if (id == null) return 'Неразобранное';
    for (final category in _categories) {
      if (category.id == id) return '«${category.name}»';
    }
    return 'Подборка';
  }

  Future<void> _openEditor(ArchiveItem item) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item)));
    if (!mounted) return;
    if (result != null) unawaited(widget.queue.enqueue(result));
    await _reload();
  }

  Future<void> _openDetail(ArchiveItem item) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => ArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item, categories: _categories)));
    if (!mounted) return;
    if (result != null) unawaited(widget.queue.enqueue(result));
    await _reload();
  }

  Future<void> _openSmartSort() async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SmartSortPage(repository: widget.repository, items: _items)));
    if (result == true && mounted) await _reload();
  }

  Future<void> _addDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить ссылку'),
        content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Вставьте ссылку...')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить'))],
      ),
    );
    controller.dispose();
    if (value?.trim().isNotEmpty == true) await _addUrl(value!);
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Новая подборка'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Название')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Создать'))],
      ),
    );
    controller.dispose();
    final name = value?.trim() ?? '';
    if (name.isEmpty || await widget.repository.findCategoryByName(name) != null) return;
    final now = DateTime.now();
    await widget.repository.upsertCategory(Category(id: widget.repository.newId(), name: name, createdAt: now, updatedAt: now));
    await _reload();
  }

  Future<void> _moveSelected() async {
    if (_selected.isEmpty) return;
    final target = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Переместить', style: TextStyle(fontWeight: FontWeight.w800))),
      ListTile(title: const Text('Неразобранное'), onTap: () => Navigator.pop(context, '__none__')),
      ..._categories.map((c) => ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c.id))),
      ListTile(leading: const Icon(Icons.add), title: const Text('Создать подборку'), onTap: () => Navigator.pop(context, '__create__')),
    ])));
    if (target == '__create__') { await _createCategory(); return _moveSelected(); }
    if (target == null) return;
    await widget.repository.assignCategory(_selected, target == '__none__' ? null : target);
    _selected.clear();
    setState(() => _selectionMode = false);
    await _reload();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Удалить ${_selected.length} ссылок?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))]));
    if (ok != true) return;
    await widget.repository.deleteItems(_selected);
    _selected.clear();
    setState(() => _selectionMode = false);
    await _reload();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final title = _categoryName(_categoryId);
    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode ? IconButton(onPressed: () => setState(() { _selectionMode = false; _selected.clear(); }), icon: const Icon(Icons.close)) : null,
        title: _selectionMode ? Text('Выбрано: ${_selected.length}') : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Мой архив', style: TextStyle(fontWeight: FontWeight.w900)), Text(title, style: Theme.of(context).textTheme.labelMedium)]),
        actions: [if (!_selectionMode) ...[
          IconButton(tooltip: 'Умная сортировка', onPressed: _items.isEmpty ? null : _openSmartSort, icon: const Icon(Icons.auto_awesome)),
          IconButton(tooltip: 'Выбрать', onPressed: () => setState(() => _selectionMode = true), icon: const Icon(Icons.checklist_outlined)),
        ]],
      ),
      drawer: _drawer(),
      floatingActionButton: _selectionMode ? null : FloatingActionButton.extended(onPressed: _addDialog, icon: const Icon(Icons.add), label: const Text('Добавить ссылку')),
      bottomNavigationBar: _selectionMode && _selected.isNotEmpty ? SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline), label: const Text('Удалить'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: _moveSelected, icon: const Icon(Icons.drive_file_move_outline), label: const Text('Переместить')))]))) : null,
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? _errorBody() : _items.isEmpty ? _emptyBody(title) : RefreshIndicator(onRefresh: _reload, child: GridView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 110), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .74), itemCount: _items.length, itemBuilder: (_, index) {
        final item = _items[index];
        return ArchiveCard(item: item, selected: _selected.contains(item.id), selectionMode: _selectionMode, onTap: () => _selectionMode ? setState(() => _selected.contains(item.id) ? _selected.remove(item.id) : _selected.add(item.id)) : _openDetail(item), onAction: () => _openDetail(item));
      })),
    );
  }

  Widget _drawer() => Drawer(child: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
    const Padding(padding: EdgeInsets.all(12), child: Text('Подборки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
    ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Неразобранное'), selected: _categoryId == null, onTap: () { Navigator.pop(context); setState(() => _categoryId = null); unawaited(_reload()); }),
    const Divider(),
    ..._categories.map((category) => ListTile(leading: const Icon(Icons.folder_outlined), title: Text(category.name), selected: _categoryId == category.id, onTap: () { Navigator.pop(context); setState(() => _categoryId = category.id); unawaited(_reload()); })),
    const Divider(),
    ListTile(leading: const Icon(Icons.add), title: const Text('Создать подборку'), onTap: () { Navigator.pop(context); unawaited(_createCategory()); }),
  ])));

  Widget _emptyBody(String title) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('🐈', style: TextStyle(fontSize: 60)), const SizedBox(height: 12), Text(title == 'Неразобранное' ? 'Неразобранное пусто' : 'В этой подборке пока нет ссылок', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center), const SizedBox(height: 8), const Text('Сохраняйте ссылки через кнопку ниже или через Поделиться.', textAlign: TextAlign.center)])));

  Widget _errorBody() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, size: 56), const SizedBox(height: 12), const Text('Не удалось загрузить архив', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(_error!, textAlign: TextAlign.center, maxLines: 5, overflow: TextOverflow.ellipsis), const SizedBox(height: 16), FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Повторить'))])));
}
