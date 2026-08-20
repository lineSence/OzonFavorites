import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/archive_item.dart';
import 'models/category.dart';
import 'repositories/archive_repository.dart';
import 'repositories/local_archive_repository.dart';
import 'services/metadata_queue.dart';
import 'services/url_normalizer.dart';

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
  static const channel = MethodChannel('product_boards/share');
  Map<Object?, Object?>? sharedData;

  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedData' && call.arguments is Map && mounted) {
        setState(() => sharedData = Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    channel.invokeMethod('getInitialSharedData').then((value) {
      if (value is Map && mounted) setState(() => sharedData = Map<Object?, Object?>.from(value));
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
          sharedData: sharedData,
          consumeSharedData: () => setState(() => sharedData = null),
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
  final _normalizer = UrlNormalizer();
  List<ArchiveItem> items = const [];
  List<Category> categories = const [];
  String? categoryId;
  bool loading = true;
  bool selectionMode = false;
  final selected = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeShare());
  }

  @override
  void didUpdateWidget(covariant ArchiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedData != null && widget.sharedData != oldWidget.sharedData) _consumeShare();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => loading = true);
    final loadedCategories = await widget.repository.getCategories();
    final loadedItems = await widget.repository.getItems(categoryId: categoryId);
    if (!mounted) return;
    setState(() {
      categories = loadedCategories;
      items = loadedItems;
      loading = false;
      selected.removeWhere((id) => !loadedItems.any((item) => item.id == id));
    });
  }

  Future<void> _consumeShare() async {
    final data = widget.sharedData;
    if (data == null) return;
    final url = data['url']?.toString().trim();
    if (url == null || url.isEmpty) return;
    widget.consumeSharedData();
    await _addUrl(url, initialTitle: data['title']?.toString().trim());
  }

  Future<void> _addUrl(String raw, {String? initialTitle, String? initialCategoryId}) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      _snack('Нужна ссылка http/https');
      return;
    }
    final duplicates = await widget.repository.findByNormalizedUrl(_normalizer.normalize(uri.toString()));
    if (duplicates.isNotEmpty && !await _confirmDuplicate(duplicates)) return;

    final now = DateTime.now();
    final item = ArchiveItem(
      id: widget.repository.newId(),
      url: uri.toString(),
      title: initialTitle?.isNotEmpty == true ? initialTitle! : '...',
      titleSource: TitleSource.automatic,
      imageStatus: ImageStatus.loading,
      note: '',
      categoryId: initialCategoryId ?? categoryId,
      metadataStatus: MetadataStatus.loading,
      createdAt: now,
      updatedAt: now,
    );
    await widget.repository.upsertItem(item);
    unawaited(widget.queue.enqueue(item));
    await _reload();
    await _openEditor(item);
  }

  Future<bool> _confirmDuplicate(List<ArchiveItem> duplicates) async {
    final locations = duplicates.map((item) {
      if (item.categoryId == null) return '• Неразобранное';
      final category = categories.where((c) => c.id == item.categoryId).firstOrNull;
      return '• ${category == null ? 'Подборка' : '«${category.name}»'}';
    }).join('\n');
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

  Future<void> _openEditor(ArchiveItem item) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item)));
    if (!mounted) return;
    if (result != null) {
      await widget.repository.upsertItem(result);
      unawaited(widget.queue.enqueue(result));
    }
    await _reload();
  }

  Future<void> _openDetail(ArchiveItem item) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => ArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item, categories: categories)));
    if (result != null) {
      await widget.repository.upsertItem(result);
      unawaited(widget.queue.enqueue(result));
    }
    await _reload();
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
    if (name.isEmpty) return;
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
        content: TextField(controller: controller, autofocus: true),
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
    if (categoryId == category.id) categoryId = null;
    await _reload();
  }

  Future<String?> _pickCategory({String? excluded}) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Выбрать подборку', style: TextStyle(fontWeight: FontWeight.w800))),
        ListTile(title: const Text('Не выбирать'), onTap: () => Navigator.pop(context, '__none__')),
        ...categories.where((c) => c.id != excluded).map((c) => ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c.id))),
        ListTile(leading: const Icon(Icons.add), title: const Text('+ Создать подборку'), onTap: () => Navigator.pop(context, '__create__')),
      ])),
    );
    if (value == null) return '__cancel__';
    if (value == '__create__') {
      await _createCategory();
      await _reload();
      return _pickCategory(excluded: excluded);
    }
    return value == '__none__' ? null : value;
  }

  Future<void> _moveOne(ArchiveItem item) async {
    final target = await _pickCategory(excluded: item.categoryId);
    if (target == '__cancel__' || target == item.categoryId) return;
    await widget.repository.upsertItem(item.copyWith(categoryId: target, updatedAt: DateTime.now()));
    await _reload();
    _snack(target == null ? 'Перемещено в Неразобранное' : 'Перемещено');
  }

  Future<void> _bulkMove() async {
    if (selected.isEmpty) return;
    final target = await _pickCategory(excluded: categoryId);
    if (target == '__cancel__' || target == categoryId) return;
    final count = selected.length;
    await widget.repository.assignCategory(selected, target);
    selected.clear();
    selectionMode = false;
    await _reload();
    _snack('$count ${_plural(count, 'ссылка', 'ссылки', 'ссылок')} перемещено');
  }

  Future<void> _bulkDelete() async {
    if (selected.isEmpty) return;
    final count = selected.length;
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
    await widget.repository.deleteItems(selected);
    selected.clear();
    selectionMode = false;
    await _reload();
  }

  Future<void> _addDialog() async {
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
    if (value.isNotEmpty) await _addUrl(value);
  }

  String _plural(int n, String one, String few, String many) {
    final x = n.abs() % 100;
    if (x >= 11 && x <= 14) return many;
    switch (x % 10) {
      case 1: return one;
      case 2:
      case 3:
      case 4: return few;
      default: return many;
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final title = categoryId == null ? 'Неразобранное' : categories.where((c) => c.id == categoryId).firstOrNull?.name ?? 'Подборка';
    return Scaffold(
      appBar: AppBar(
        leading: selectionMode ? IconButton(onPressed: () => setState(() { selectionMode = false; selected.clear(); }), icon: const Icon(Icons.close)) : null,
        title: selectionMode ? Text('Выбрано: ${selected.length}') : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Мой архив', style: TextStyle(fontWeight: FontWeight.w900)), Text(title, style: Theme.of(context).textTheme.labelMedium)]),
        actions: [
          if (!selectionMode) IconButton(tooltip: 'Сортировать', onPressed: () => setState(() => selectionMode = true), icon: const Icon(Icons.checklist_outlined)),
          Builder(builder: (context) => IconButton(tooltip: 'Подборки', onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu))),
        ],
      ),
      drawer: Drawer(child: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Подборки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
        ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Неразобранное'), selected: categoryId == null, onTap: () { Navigator.pop(context); setState(() => categoryId = null); _reload(); }),
        const Divider(),
        ...categories.map((c) => ListTile(
              leading: const Icon(Icons.folder_outlined), title: Text(c.name), selected: categoryId == c.id,
              onTap: () { Navigator.pop(context); setState(() => categoryId = c.id); _reload(); },
              trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'rename') _renameCategory(c); if (v == 'delete') _deleteCategory(c); }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Переименовать')), PopupMenuItem(value: 'delete', child: Text('Удалить'))]),
            )),
        const Divider(),
        ListTile(leading: const Icon(Icons.add), title: const Text('Создать подборку'), onTap: () { Navigator.pop(context); _createCategory(); }),
      ]))),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: selectionMode ? null : FloatingActionButton.extended(onPressed: _addDialog, icon: const Icon(Icons.add), label: const Text('Добавить ссылку')),
      bottomNavigationBar: selectionMode && selected.isNotEmpty ? SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _bulkDelete, icon: const Icon(Icons.delete_outline), label: const Text('Удалить'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: _bulkMove, icon: const Icon(Icons.drive_file_move_outline), label: Text(categoryId == null ? 'В подборку' : 'Переместить')))]))) : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? _empty(title)
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .74),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return ArchiveCard(item: item, selected: selected.contains(item.id), selectionMode: selectionMode, onTap: () {
                        if (selectionMode) {
                          setState(() => selected.contains(item.id) ? selected.remove(item.id) : selected.add(item.id));
                        } else {
                          _openDetail(item);
                        }
                      }, onAction: () => _moveOne(item));
                    },
                  ),
                ),
    );
  }

  Widget _empty(String title) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('🐈', style: TextStyle(fontSize: 60)), const SizedBox(height: 12), Text(title == 'Неразобранное' ? 'Неразобранное пусто' : 'В этой подборке пока нет ссылок', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center), const SizedBox(height: 8), const Text('Сохраняйте ссылки через кнопку ниже или через Поделиться.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))])));
}

class ArchiveCard extends StatelessWidget {
  const ArchiveCard({super.key, required this.item, required this.onTap, required this.onAction, required this.selected, required this.selectionMode});
  final ArchiveItem item;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final bool selected;
  final bool selectionMode;

  ImageProvider<Object>? get _provider {
    final value = item.imageUrl;
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'file') return FileImage(File(uri!.toFilePath()));
    return NetworkImage(value);
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _image()), Padding(padding: const EdgeInsets.fromLTRB(12, 10, 44, 12), child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))) ]),
          if (!selectionMode) Positioned(right: 2, bottom: 2, child: IconButton(onPressed: onAction, icon: const Icon(Icons.north_east), tooltip: 'Переместить')),
          if (selectionMode) Positioned(top: 10, right: 10, child: Container(width: 28, height: 28, decoration: BoxDecoration(color: selected ? Colors.black : Colors.white70, shape: BoxShape.circle, border: Border.all(color: Colors.black38)), child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null)),
          if (item.metadataStatus == MetadataStatus.loading) const Positioned(left: 10, top: 10, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        ])),
      );

  Widget _image() {
    final provider = _provider;
    if (provider == null) return Container(color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 52)));
    return Image(image: provider, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 52))));
  }
}

class ArchiveItemPage extends StatelessWidget {
  const ArchiveItemPage({super.key, required this.repository, required this.queue, required this.item, required this.categories});
  final ArchiveRepository repository;
  final MetadataQueue queue;
  final ArchiveItem item;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final provider = _imageProvider(item.imageUrl);
    return Scaffold(
      appBar: AppBar(title: const Text('Ссылка'), actions: [IconButton(onPressed: () => _move(context), icon: const Icon(Icons.north_east)), IconButton(onPressed: () => _edit(context), icon: const Icon(Icons.edit_outlined))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ClipRRect(borderRadius: BorderRadius.circular(20), child: provider == null ? _placeholder(340) : Image(image: provider, height: 340, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(340))),
        const SizedBox(height: 18),
        Text(item.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (item.note.isNotEmpty) ...[const SizedBox(height: 22), const Text('Заметка', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(item.note)],
        const SizedBox(height: 18),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.folder_outlined), title: Text(item.categoryId == null ? 'Неразобранное' : categories.where((c) => c.id == item.categoryId).firstOrNull?.name ?? 'Подборка')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(item.url, maxLines: 3, overflow: TextOverflow.ellipsis)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Открыть')),
        if (item.metadataStatus != MetadataStatus.success) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Не все метаданные удалось получить автоматически. Ссылка сохранена.')),
      ]),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: repository, queue: queue, item: item)));
    if (context.mounted && result != null) Navigator.pop(context, result);
    if (context.mounted && result == null && await repository.getItem(item.id) == null) Navigator.pop(context);
  }

  Future<void> _move(BuildContext context) async {
    final value = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const ListTile(title: Text('Переместить', style: TextStyle(fontWeight: FontWeight.w800))), if (item.categoryId != null) ListTile(title: const Text('Неразобранное'), onTap: () => Navigator.pop(context, '__none__')), ...categories.where((c) => c.id != item.categoryId).map((c) => ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c.id))) ])));
    if (!context.mounted || value == null) return;
    final updated = item.copyWith(categoryId: value == '__none__' ? null : value, updatedAt: DateTime.now());
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
  late final titleController = TextEditingController(text: widget.item.title);
  late final noteController = TextEditingController(text: widget.item.note);
  String? categoryId;
  bool titleTouched = false;
  List<Category> categories = const [];

  @override
  void initState() { super.initState(); categoryId = widget.item.categoryId; _loadCategories(); }
  Future<void> _loadCategories() async { final value = await widget.repository.getCategories(); if (mounted) setState(() => categories = value); }
  @override
  void dispose() { titleController.dispose(); noteController.dispose(); super.dispose(); }

  Future<void> _chooseCategory() async {
    final value = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Выбрать подборку', style: TextStyle(fontWeight: FontWeight.w800))),
      ListTile(title: const Text('Не выбирать'), onTap: () => Navigator.pop(context, '__none__')),
      ...categories.map((c) => ListTile(title: Text(c.name), trailing: c.id == categoryId ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, c.id))),
    ])));
    if (!mounted || value == null) return;
    setState(() => categoryId = value == '__none__' ? null : value);
  }

  Future<void> _save() async {
    final entered = titleController.text.trim();
    final manual = titleTouched || widget.item.titleSource == TitleSource.manual;
    final result = widget.item.copyWith(title: entered.isEmpty ? 'Без названия' : entered, titleSource: manual ? TitleSource.manual : widget.item.titleSource, note: noteController.text.trim(), categoryId: categoryId, updatedAt: DateTime.now());
    await widget.repository.upsertItem(result);
    unawaited(widget.queue.enqueue(result));
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Удалить эту ссылку?'), content: const Text('Объект будет удалён из архива.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))]));
    if (ok != true) return;
    await widget.repository.deleteItem(widget.item.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _imageProvider(widget.item.imageUrl);
    final categoryName = categoryId == null ? 'Неразобранное' : categories.where((c) => c.id == categoryId).firstOrNull?.name ?? 'Подборка';
    return Scaffold(appBar: AppBar(title: const Text('Редактировать')), body: ListView(padding: const EdgeInsets.all(16), children: [
      ClipRRect(borderRadius: BorderRadius.circular(18), child: provider == null ? _placeholder(240) : Image(image: provider, height: 240, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(240))),
      const SizedBox(height: 18),
      TextField(controller: titleController, onChanged: (_) => titleTouched = true, decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: noteController, maxLines: 4, decoration: const InputDecoration(labelText: 'Заметка', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Подборка', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(categoryName), trailing: const Icon(Icons.chevron_right), onTap: _chooseCategory),
      const SizedBox(height: 12),
      FilledButton(onPressed: _save, child: const Text('Сохранить')),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _delete, child: const Text('Удалить')),
    ]));
  }
}

ImageProvider<Object>? _imageProvider(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri?.scheme == 'file') return FileImage(File(uri!.toFilePath()));
  return NetworkImage(value);
}

Widget _placeholder(double height) => Container(height: height, color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 64)));

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
