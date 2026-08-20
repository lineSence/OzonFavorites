import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/archive_item.dart';
import 'models/category.dart';
import 'repositories/archive_repository.dart';
import 'repositories/local_archive_repository.dart';
import 'services/metadata_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = LocalArchiveRepository();
  await repository.init();
  final queue = MetadataQueue(repository: repository);
  unawaited(queue.resumePending());
  runApp(PinzonApp(repository: repository, queue: queue));
}

class PinzonApp extends StatefulWidget {
  const PinzonApp({super.key, required this.repository, required this.queue});
  final ArchiveRepository repository;
  final MetadataQueue queue;

  @override
  State<PinzonApp> createState() => _PinzonAppState();
}

class _PinzonAppState extends State<PinzonApp> {
  static const _shareChannel = MethodChannel('product_boards/share');
  Map<Object?, Object?>? _sharedData;

  @override
  void initState() {
    super.initState();
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedData' && call.arguments is Map && mounted) {
        setState(() => _sharedData = Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    _shareChannel.invokeMethod('getInitialSharedData').then((value) {
      if (value is Map && mounted) {
        setState(() => _sharedData = Map<Object?, Object?>.from(value));
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pinzon',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
          scaffoldBackgroundColor: const Color(0xfff6f6f4),
        ),
        home: ArchiveScreen(
          repository: widget.repository,
          queue: widget.queue,
          sharedData: _sharedData,
          consumeSharedData: () => setState(() => _sharedData = null),
        ),
      );
}

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.repository, required this.queue, required this.consumeSharedData, this.sharedData});
  final ArchiveRepository repository;
  final MetadataQueue queue;
  final Map<Object?, Object?>? sharedData;
  final VoidCallback consumeSharedData;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<ArchiveItem> _items = const [];
  List<Category> _categories = const [];
  String? _categoryId;
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeShared());
  }

  @override
  void didUpdateWidget(covariant ArchiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedData != null && widget.sharedData != oldWidget.sharedData) _consumeShared();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    final categories = await widget.repository.getCategories();
    final items = await widget.repository.getItems(categoryId: _categoryId);
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _items = items;
      _loading = false;
      _selected.removeWhere((id) => !items.any((item) => item.id == id));
    });
  }

  Future<void> _consumeShared() async {
    final data = widget.sharedData;
    if (data == null) return;
    final url = data['url']?.toString().trim();
    if (url == null || url.isEmpty) return;
    widget.consumeSharedData();
    await _addUrl(url, initialCategoryId: _categoryId);
  }

  Future<void> _addUrl(String raw, {String? initialCategoryId}) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      _snack('Нужна ссылка http/https');
      return;
    }

    final normalized = (widget.repository as LocalArchiveRepository).normalizer.normalize(uri.toString());
    final duplicates = await widget.repository.findByNormalizedUrl(normalized);
    if (duplicates.isNotEmpty && !await _confirmDuplicate(duplicates)) return;

    final now = DateTime.now();
    final item = ArchiveItem(
      id: widget.repository.newId(),
      url: uri.toString(),
      title: '...',
      titleSource: TitleSource.automatic,
      imageUrl: null,
      imageStatus: ImageStatus.loading,
      note: '',
      categoryId: initialCategoryId,
      metadataStatus: MetadataStatus.loading,
      createdAt: now,
      updatedAt: now,
    );
    await widget.repository.upsertItem(item);
    await _reload();
    await _openEditor(item, isNew: true);
  }

  Future<bool> _confirmDuplicate(List<ArchiveItem> duplicates) async {
    final locations = duplicates.map((e) => _location(e.categoryId)).join('\n');
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Эта ссылка уже есть'),
            content: Text('$locations\n\nСоздать новый независимый объект?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отменить сохранение')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Всё равно сохранить')),
            ],
          ),
        )) ??
        false;
  }

  String _location(String? categoryId) {
    if (categoryId == null) return '• Неразобранное';
    final category = _categories.where((c) => c.id == categoryId).firstOrNull;
    return '• ${category == null ? 'Подборка' : '«${category.name}»'}';
  }

  Future<void> _openEditor(ArchiveItem item, {bool isNew = false}) async {
    final result = await Navigator.push<ArchiveItem>(
      context,
      MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item)),
    );
    if (!mounted) return;
    if (result != null) {
      await widget.repository.upsertItem(result);
      unawaited(widget.queue.enqueue(result));
      await _reload();
    } else if (isNew) {
      unawaited(widget.queue.enqueue(item));
      await _reload();
    }
  }

  Future<void> _openDetail(ArchiveItem item) async {
    final result = await Navigator.push<ArchiveItem>(
      context,
      MaterialPageRoute(builder: (_) => ArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item)),
    );
    if (result != null && mounted) {
      await widget.repository.upsertItem(result);
      unawaited(widget.queue.enqueue(result));
      await _reload();
    }
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Новая подборка'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Создать')),
        ],
      ),
    );
    controller.dispose();
    final name = raw?.trim() ?? '';
    if (name.isEmpty) {
      if (raw != null) _snack('Название подборки обязательно');
      return;
    }
    if (await widget.repository.findCategoryByName(name) != null) {
      _snack('Такая подборка уже существует');
      return;
    }
    final now = DateTime.now();
    await widget.repository.upsertCategory(Category(id: widget.repository.newId(), name: name, createdAt: now, updatedAt: now));
    await _reload();
  }

  Future<void> _renameCategory(Category category) async {
    final controller = TextEditingController(text: category.name);
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Переименовать подборку'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    final name = raw?.trim() ?? '';
    if (name.isEmpty) return;
    final existing = await widget.repository.findCategoryByName(name);
    if (existing != null && existing.id != category.id) {
      _snack('Такая подборка уже существует');
      return;
    }
    await widget.repository.upsertCategory(category.copyWith(name: name, updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _deleteCategory(Category category) async {
    final count = (await widget.repository.getItems(categoryId: category.id)).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Удалить подборку «${category.name}»?'),
        content: Text('$count ссылок будут перемещены в Неразобранное.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repository.deleteCategory(category.id);
    if (_categoryId == category.id) _categoryId = null;
    await _reload();
  }

  Future<String?> _pickCategory({bool includeUnassigned = true, String? excludedCategoryId}) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Выбрать подборку', style: TextStyle(fontWeight: FontWeight.w800))),
          if (includeUnassigned) ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Не выбирать'), onTap: () => Navigator.pop(context, '__none__')),
          ..._categories.where((c) => c.id != excludedCategoryId).map((c) => ListTile(leading: const Icon(Icons.folder_outlined), title: Text(c.name), onTap: () => Navigator.pop(context, c.id))),
          ListTile(leading: const Icon(Icons.add), title: const Text('+ Создать подборку'), onTap: () => Navigator.pop(context, '__create__')),
        ]),
      ),
    );
    if (result == null) return '__cancel__';
    if (result == '__none__') return null;
    if (result == '__create__') {
      await _createCategory();
      await _reload();
      return _pickCategory(includeUnassigned: includeUnassigned, excludedCategoryId: excludedCategoryId);
    }
    return result;
  }

  Future<void> _singleMove(ArchiveItem item) async {
    final target = await _pickCategory(excludedCategoryId: item.categoryId);
    if (target == '__cancel__' || target == item.categoryId) return;
    final updated = item.copyWith(categoryId: target, updatedAt: DateTime.now());
    await widget.repository.upsertItem(updated);
    await _reload();
    _snack(target == null ? 'Перемещено в Неразобранное' : 'Перемещено');
  }

  Future<void> _bulkMove() async {
    if (_selected.isEmpty) return;
    final target = await _pickCategory(excludedCategoryId: _categoryId);
    if (target == '__cancel__' || target == _categoryId) return;
    final count = _selected.length;
    await widget.repository.assignCategory(_selected, target);
    _selected.clear();
    _selectionMode = false;
    await _reload();
    _snack(target == null ? '$count ссылок перемещено в Неразобранное' : '$count ${_plural(count, 'ссылка', 'ссылки', 'ссылок')} перемещено');
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Удалить $count ${_plural(count, 'ссылку', 'ссылки', 'ссылок')}?'),
        content: const Text('Объекты будут удалены из архива.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repository.deleteItems(_selected);
    _selected.clear();
    _selectionMode = false;
    await _reload();
  }

  Future<void> _addUrlFromDialog() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить ссылку'),
        content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Вставьте ссылку...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить')),
        ],
      ),
    );
    controller.dispose();
    final value = raw?.trim() ?? '';
    if (value.isNotEmpty) await _addUrl(value, initialCategoryId: _categoryId);
  }

  String _plural(int value, String one, String few, String many) {
    final n = value.abs() % 100;
    if (n >= 11 && n <= 14) return many;
    switch (n % 10) {
      case 1:
        return one;
      case 2:
      case 3:
      case 4:
        return few;
      default:
        return many;
    }
  }

  void _snack(String value) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final title = _categoryId == null ? 'Неразобранное' : _categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? 'Подборка';
    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode ? IconButton(onPressed: () => setState(() { _selectionMode = false; _selected.clear(); }), icon: const Icon(Icons.close)) : null,
        title: _selectionMode
            ? Text('Выбрано: ${_selected.length}', style: const TextStyle(fontWeight: FontWeight.w900))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Мой архив', style: TextStyle(fontWeight: FontWeight.w900)), Text(title, style: Theme.of(context).textTheme.labelMedium)]),
        actions: [
          if (!_selectionMode) IconButton(tooltip: 'Сортировать', onPressed: () => setState(() => _selectionMode = true), icon: const Icon(Icons.checklist_outlined)),
          Builder(builder: (context) => IconButton(tooltip: 'Подборки', onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu))),
        ],
      ),
      drawer: Drawer(child: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Подборки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
        ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Неразобранное'), selected: _categoryId == null, onTap: () { Navigator.pop(context); setState(() => _categoryId = null); _reload(); }),
        const Divider(),
        ..._categories.map((c) => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(c.name),
              selected: _categoryId == c.id,
              onTap: () { Navigator.pop(context); setState(() => _categoryId = c.id); _reload(); },
              trailing: PopupMenuButton<String>(
                onSelected: (value) { if (value == 'rename') _renameCategory(c); if (value == 'delete') _deleteCategory(c); },
                itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Переименовать')), PopupMenuItem(value: 'delete', child: Text('Удалить'))],
              ),
            )),
        const Divider(),
        ListTile(leading: const Icon(Icons.add), title: const Text('Создать подборку'), onTap: () { Navigator.pop(context); _createCategory(); }),
      ]))),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _selectionMode ? null : FloatingActionButton.extended(onPressed: _addUrlFromDialog, icon: const Icon(Icons.add), label: const Text('Добавить ссылку')),
      bottomNavigationBar: _selectionMode && _selected.isNotEmpty
          ? SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _bulkDelete, icon: const Icon(Icons.delete_outline), label: const Text('Удалить'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: _bulkMove, icon: const Icon(Icons.drive_file_move_outline), label: Text(_categoryId == null ? 'В подборку' : 'Переместить'))),
            ])))
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _empty(title)
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.74),
                    itemCount: _items.length,
                    itemBuilder: (_, index) {
                      final item = _items[index];
                      return ArchiveCard(
                        item: item,
                        selected: _selected.contains(item.id),
                        selectionMode: _selectionMode,
                        onTap: () {
                          if (_selectionMode) {
                            setState(() => _selected.contains(item.id) ? _selected.remove(item.id) : _selected.add(item.id));
                          } else {
                            _openDetail(item);
                          }
                        },
                        onAction: () => _singleMove(item),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _empty(String title) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🐈', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 12),
        Text(title == 'Неразобранное' ? 'Неразобранное пусто' : 'В этой подборке пока нет ссылок', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Сохраняйте ссылки через кнопку ниже или через Поделиться.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
      ])));
}

class ArchiveCard extends StatelessWidget {
  const ArchiveCard({super.key, required this.item, required this.onTap, required this.onAction, required this.selected, required this.selectionMode});
  final ArchiveItem item;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _image()),
              Padding(padding: const EdgeInsets.fromLTRB(12, 10, 46, 12), child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            if (!selectionMode) Positioned(right: 2, bottom: 2, child: IconButton(onPressed: onAction, icon: const Icon(Icons.north_east), tooltip: 'Переместить')),
            if (selectionMode) Positioned(top: 10, right: 10, child: Container(width: 28, height: 28, decoration: BoxDecoration(color: selected ? Colors.black : Colors.white70, shape: BoxShape.circle, border: Border.all(color: Colors.black38)), child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null)),
            if (item.metadataStatus == MetadataStatus.loading) const Positioned(left: 10, top: 10, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
      );

  Widget _image() {
    if (item.imageUrl == null || item.imageUrl!.isEmpty) return Container(color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 52)));
    return Image.network(item.imageUrl!, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 52))));
  }
}

class ArchiveItemPage extends StatelessWidget {
  const ArchiveItemPage({super.key, required this.repository, required this.queue, required this.item});
  final ArchiveRepository repository;
  final MetadataQueue queue;
  final ArchiveItem item;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Ссылка'),
          actions: [
            IconButton(onPressed: () => _move(context), icon: const Icon(Icons.north_east), tooltip: 'Переместить'),
            IconButton(onPressed: () => _edit(context), icon: const Icon(Icons.edit_outlined), tooltip: 'Редактировать'),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(borderRadius: BorderRadius.circular(20), child: item.imageUrl == null ? _placeholder() : Image.network(item.imageUrl!, height: 340, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())),
          const SizedBox(height: 18),
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (item.note.isNotEmpty) ...[
            const SizedBox(height: 22), const Text('Заметка', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(item.note),
          ],
          const SizedBox(height: 18),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.folder_outlined), title: Text(item.categoryId == null ? 'Неразобранное' : 'Подборка')),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(item.url, maxLines: 3, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Открыть')),
          if (item.metadataStatus != MetadataStatus.success) ...[const SizedBox(height: 10), const Text('Не все метаданные удалось получить автоматически. Ссылка сохранена.')],
        ]),
      );

  Widget _placeholder() => Container(height: 340, color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 72)));

  Future<void> _edit(BuildContext context) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: repository, queue: queue, item: item)));
    if (result != null && context.mounted) Navigator.pop(context, result);
  }

  Future<void> _move(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Переместить', style: TextStyle(fontWeight: FontWeight.w800))),
        ListTile(title: const Text('Неразобранное'), onTap: () => Navigator.pop(context, '__none__')),
      ])),
    );
    if (!context.mounted || result == null) return;
    final target = result == '__none__' ? null : result;
    final updated = item.copyWith(categoryId: target, updatedAt: DateTime.now());
    await repository.upsertItem(updated);
    if (context.mounted) Navigator.pop(context, updated);
  }
}

class EditArchiveItemPage extends StatefulWidget {
  const EditArchiveItemPage({super.key, required this.repository, required this.queue, required this.item});
  final ArchiveRepository repository;
  final MetadataQueue queue;
  final ArchiveItem item;

  @override
  State<EditArchiveItemPage> createState() => _EditArchiveItemPageState();
}

class _EditArchiveItemPageState extends State<EditArchiveItemPage> {
  late final TextEditingController _title = TextEditingController(text: widget.item.title);
  late final TextEditingController _note = TextEditingController(text: widget.item.note);
  String? _categoryId;
  bool _titleTouched = false;
  bool _saving = false;
  List<Category> _categories = const [];

  @override
  void initState() {
    super.initState();
    _categoryId = widget.item.categoryId;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await widget.repository.getCategories();
    if (mounted) setState(() => _categories = categories);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _chooseCategory() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Выбрать подборку', style: TextStyle(fontWeight: FontWeight.w800))),
        ListTile(title: const Text('Не выбирать'), subtitle: const Text('Неразобранное'), onTap: () => Navigator.pop(context, '__none__')),
        ..._categories.map((c) => ListTile(title: Text(c.name), trailing: c.id == _categoryId ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, c.id))),
        ListTile(leading: const Icon(Icons.add), title: const Text('+ Создать подборку'), onTap: () => Navigator.pop(context, '__create__')),
      ])),
    );
    if (!mounted || result == null) return;
    if (result == '__create__') {
      final controller = TextEditingController();
      final raw = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Новая подборка'), content: TextField(controller: controller, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Создать'))]));
      controller.dispose();
      final name = raw?.trim() ?? '';
      if (name.isEmpty) return;
      if (await widget.repository.findCategoryByName(name) != null) {
        if (mounted) _snack('Такая подборка уже существует');
        return;
      }
      final now = DateTime.now();
      final category = Category(id: widget.repository.newId(), name: name, createdAt: now, updatedAt: now);
      await widget.repository.upsertCategory(category);
      await _loadCategories();
      if (mounted) setState(() => _categoryId = category.id);
      return;
    }
    setState(() => _categoryId = result == '__none__' ? null : result);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final title = _title.text.trim();
    final manual = _titleTouched || widget.item.titleSource == TitleSource.manual;
    final result = widget.item.copyWith(
      title: title.isEmpty ? 'Без названия' : title,
      titleSource: manual ? TitleSource.manual : widget.item.titleSource,
      note: _note.text.trim(),
      categoryId: _categoryId,
      updatedAt: DateTime.now(),
    );
    await widget.repository.upsertItem(result);
    unawaited(widget.queue.enqueue(result));
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить эту ссылку?'),
        content: const Text('Объект будет удалён из архива.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))],
      ),
    );
    if (ok != true) return;
    await widget.repository.deleteItem(widget.item.id);
    if (mounted) Navigator.pop(context);
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final categoryName = _categoryId == null ? 'Неразобранное' : _categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? 'Подборка';
    return Scaffold(
      appBar: AppBar(title: const Text('Редактировать')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        if (widget.item.imageUrl != null)
          ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(widget.item.imageUrl!, height: 240, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder()))
        else
          _placeholder(),
        const SizedBox(height: 18),
        TextField(controller: _title, onChanged: (_) => _titleTouched = true, decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 4, decoration: const InputDecoration(labelText: 'Заметка', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Подборка', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(categoryName), trailing: const Icon(Icons.chevron_right), onTap: _chooseCategory),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Сохранение…' : 'Сохранить')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _delete, child: const Text('Удалить')),
      ]),
    );
  }

  Widget _placeholder() => Container(height: 240, decoration: BoxDecoration(color: const Color(0xffecece9), borderRadius: BorderRadius.circular(18)), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 64)));
}

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
