import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/archive_item.dart';
import 'models/category.dart';
import 'repositories/archive_repository.dart';
import 'repositories/local_archive_repository.dart';
import 'screens/smart_sort_page.dart';
import 'services/metadata_queue.dart';
import 'services/url_normalizer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = LocalArchiveRepository();
  await repository.init();
  final queue = MetadataQueue(repository: repository);
  unawaited(queue.resumePending().catchError((_) {}));
  runApp(PinzonApp(repository: repository, queue: queue));
}

class PinzonApp extends StatefulWidget {
  const PinzonApp({super.key, required this.repository, required this.queue});
  final ArchiveRepository repository;
  final MetadataQueue queue;
  @override State<PinzonApp> createState() => _PinzonAppState();
}

class _PinzonAppState extends State<PinzonApp> {
  static const _channel = MethodChannel('product_boards/share');
  Map<Object?, Object?>? _sharedData;
  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedData' && call.arguments is Map) {
        if (mounted) setState(() => _sharedData = Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    unawaited(_loadInitialShare());
  }
  Future<void> _loadInitialShare() async {
    try {
      final value = await _channel.invokeMethod('getInitialSharedData');
      if (mounted && value is Map) setState(() => _sharedData = Map<Object?, Object?>.from(value));
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Pinzon',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.black), scaffoldBackgroundColor: const Color(0xfff6f6f4)),
    home: ArchiveScreen(repository: widget.repository, queue: widget.queue, sharedData: _sharedData, onSharedDataConsumed: () => setState(() => _sharedData = null)),
  );
}

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.repository, required this.queue, required this.sharedData, required this.onSharedDataConsumed});
  final ArchiveRepository repository;
  final MetadataQueue queue;
  final Map<Object?, Object?>? sharedData;
  final VoidCallback onSharedDataConsumed;
  @override State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _normalizer = UrlNormalizer();
  List<ArchiveItem> _items = const [];
  List<Category> _categories = const [];
  String? _categoryId;
  bool _loading = true;
  String? _loadError;
  bool _selectionMode = false;
  final _selected = <String>{};

  @override
  void initState() { super.initState(); unawaited(_reload()); WidgetsBinding.instance.addPostFrameCallback((_) => _consumeShare()); }
  @override
  void didUpdateWidget(covariant ArchiveScreen oldWidget) { super.didUpdateWidget(oldWidget); if (widget.sharedData != null && widget.sharedData != oldWidget.sharedData) unawaited(_consumeShare()); }
  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final categories = await widget.repository.getCategories();
      final items = await widget.repository.getItems(categoryId: _categoryId);
      if (!mounted) return;
      setState(() { _categories = categories; _items = items; _loading = false; _loadError = null; _selected.removeWhere((id) => !items.any((item) => item.id == id)); });
    } catch (error) { if (!mounted) return; setState(() { _loading = false; _loadError = error.toString(); }); }
  }
  Future<void> _consumeShare() async { final data = widget.sharedData; if (data == null) return; final url = data['url']?.toString().trim(); if (url == null || url.isEmpty) return; final success = await _addUrl(url, initialTitle: data['title']?.toString().trim()); if (success && mounted) widget.onSharedDataConsumed(); }
  Future<bool> _addUrl(String raw, {String? initialTitle}) async {
    try {
      final uri = Uri.tryParse(raw.trim());
      if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) { _snack('Нужна ссылка http/https'); return false; }
      final duplicates = await widget.repository.findByNormalizedUrl(_normalizer.normalize(uri.toString()));
      if (duplicates.isNotEmpty) { final proceed = await _confirmDuplicate(duplicates); if (!proceed) return false; }
      final now = DateTime.now();
      final item = ArchiveItem(id: widget.repository.newId(), url: uri.toString(), title: initialTitle?.isNotEmpty == true ? initialTitle! : '...', titleSource: TitleSource.automatic, imageStatus: ImageStatus.loading, note: '', categoryId: _categoryId, metadataStatus: MetadataStatus.loading, createdAt: now, updatedAt: now);
      await widget.repository.upsertItem(item); unawaited(widget.queue.enqueue(item)); await _reload(); if (mounted) await _openEditor(item); return true;
    } catch (error) { _snack('Не удалось добавить ссылку: $error'); return false; }
  }
  Future<bool> _confirmDuplicate(List<ArchiveItem> duplicates) async {
    final locations = duplicates.map((item) { final category = item.categoryId == null ? null : _categories.firstWhereOrNull((c) => c.id == item.categoryId); return '• ${category == null ? 'Неразобранное' : '«${category.name}»'}'; }).join('\n');
    return await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Эта ссылка уже есть'), content: Text('$locations\n\nСоздать новый независимый объект?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отменить сохранение')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Всё равно сохранить'))])) ?? false;
  }
  Future<void> _openEditor(ArchiveItem item) async { final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item))); if (!mounted) return; if (result != null) { await widget.repository.upsertItem(result); unawaited(widget.queue.enqueue(result)); } await _reload(); }
  Future<void> _openDetail(ArchiveItem item) async { final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => ArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item, categories: _categories))); if (!mounted) return; if (result != null) { await widget.repository.upsertItem(result); unawaited(widget.queue.enqueue(result)); } await _reload(); }
  Future<void> _openSmartSort() async { if (_items.isEmpty) { _snack('В текущей подборке нет товаров'); return; } final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SmartSortPage(repository: widget.repository, items: _items))); if (changed == true && mounted) await _reload(); }
  Future<void> _addDialog() async { final controller = TextEditingController(); final raw = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Добавить ссылку'), content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Вставьте ссылку...')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить'))])); controller.dispose(); final value = raw?.trim() ?? ''; if (value.isNotEmpty) await _addUrl(value); }
  Future<void> _createCategory() async { final controller = TextEditingController(); final raw = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Новая подборка'), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Название')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Создать'))])); controller.dispose(); final name = raw?.trim() ?? ''; if (name.isEmpty) return; if (await widget.repository.findCategoryByName(name) != null) { _snack('Такая подборка уже существует'); return; } final now = DateTime.now(); await widget.repository.upsertCategory(Category(id: widget.repository.newId(), name: name, createdAt: now, updatedAt: now)); await _reload(); }
  Future<void> _renameCategory(Category category) async { final controller = TextEditingController(text: category.name); final raw = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Переименовать подборку'), content: TextField(controller: controller, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Сохранить'))])); controller.dispose(); final name = raw?.trim() ?? ''; if (name.isEmpty) return; if (await widget.repository.findCategoryByName(name) != null && name != category.name) { _snack('Такая подборка уже существует'); return; } await widget.repository.upsertCategory(category.copyWith(name: name, updatedAt: DateTime.now())); await _reload(); }
  Future<void> _deleteCategory(Category category) async { final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Удалить «${category.name}»?'), content: const Text('Ссылки останутся в Неразобранном.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))])) ?? false; if (!ok) return; await widget.repository.deleteCategory(category.id); if (_categoryId == category.id) _categoryId = null; await _reload(); }
  Future<String?> _pickCategory({String? excluded}) async { final value = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const ListTile(title: Text('Выбрать подборку', style: TextStyle(fontWeight: FontWeight.w800))), if (excluded != null) ListTile(title: const Text('Неразобранное'), onTap: () => Navigator.pop(context, '__none__')), ..._categories.where((c) => c.id != excluded).map((c) => ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c.id))), ListTile(title: const Text('Создать подборку'), onTap: () => Navigator.pop(context, '__create__'))]))); if (value == null) return '__cancel__'; if (value == '__create__') { await _createCategory(); return _pickCategory(excluded: excluded); } return value == '__none__' ? null : value; }
  Future<void> _moveOne(ArchiveItem item) async { final target = await _pickCategory(excluded: item.categoryId); if (target == '__cancel__' || target == item.categoryId) return; await widget.repository.upsertItem(item.copyWith(categoryId: target, updatedAt: DateTime.now())); await _reload(); _snack(target == null ? 'Перемещено в Неразобранное' : 'Перемещено'); }
  Future<void> _bulkMove() async { if (_selected.isEmpty) return; final target = await _pickCategory(excluded: _categoryId); if (target == '__cancel__' || target == _categoryId) return; final count = _selected.length; await widget.repository.assignCategory(_selected, target); _selected.clear(); _selectionMode = false; await _reload(); _snack('$count ${_plural(count)} перемещено'); }
  Future<void> _bulkDelete() async { if (_selected.isEmpty) return; final count = _selected.length; final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Удалить $count ${_plural(count, deleteForm: true)}?'), content: const Text('Объекты будут удалены из архива.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))])) ?? false; if (!ok) return; await widget.repository.deleteItems(_selected); _selected.clear(); _selectionMode = false; await _reload(); }
  String _plural(int n, {bool deleteForm = false}) { final x = n.abs() % 100; if (x >= 11 && x <= 14) return 'ссылок'; switch (x % 10) { case 1: return deleteForm ? 'ссылку' : 'ссылка'; case 2: case 3: case 4: return deleteForm ? 'ссылки' : 'ссылки'; default: return 'ссылок'; } }
  void _snack(String text) { if (!mounted) return; ScaffoldMessenger.of(context).hideCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  void _select(String id) { setState(() { if (_selected.contains(id)) _selected.remove(id); else _selected.add(id); }); }

  @override
  Widget build(BuildContext context) {
    final title = _categoryId == null ? 'Неразобранное' : _categories.firstWhereOrNull((c) => c.id == _categoryId)?.name ?? 'Подборка';
    return Scaffold(
      appBar: AppBar(leading: _selectionMode ? IconButton(onPressed: () => setState(() { _selectionMode = false; _selected.clear(); }), icon: const Icon(Icons.close)) : null, title: _selectionMode ? Text('Выбрано: ${_selected.length}') : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Мой архив', style: TextStyle(fontWeight: FontWeight.w900)), Text(title, style: Theme.of(context).textTheme.labelMedium)]), actions: [if (!_selectionMode) ...[IconButton(tooltip: 'Умная сортировка', onPressed: _openSmartSort, icon: const Icon(Icons.auto_awesome_outlined)), IconButton(tooltip: 'Сортировать', onPressed: () => setState(() => _selectionMode = true), icon: const Icon(Icons.checklist_outlined))]],
      drawer: _buildDrawer(), floatingActionButtonLocation: FloatingActionButtonLocation.startFloat, floatingActionButton: _selectionMode ? null : FloatingActionButton.extended(onPressed: _addDialog, icon: const Icon(Icons.add), label: const Text('Добавить ссылку')),
      bottomNavigationBar: _selectionMode && _selected.isNotEmpty ? SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _bulkDelete, icon: const Icon(Icons.delete_outline), label: const Text('Удалить'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: _bulkMove, icon: const Icon(Icons.drive_file_move_outline), label: Text(_categoryId == null ? 'В подборку' : 'Переместить')))]))) : null,
      body: _loading ? const Center(child: CircularProgressIndicator()) : _loadError != null ? _errorBody() : _items.isEmpty ? _emptyBody(title) : RefreshIndicator(onRefresh: _reload, child: GridView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 110), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .74), itemCount: _items.length, itemBuilder: (_, index) { final item = _items[index]; return ArchiveCard(item: item, selected: _selected.contains(item.id), selectionMode: _selectionMode, onTap: () => _selectionMode ? _select(item.id) : _openDetail(item), onAction: () => _moveOne(item)); })),
    );
  }
  Widget _buildDrawer() => Drawer(child: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [const Padding(padding: EdgeInsets.all(12), child: Text('Подборки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))), ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Неразобранное'), selected: _categoryId == null, onTap: () { Navigator.pop(context); setState(() => _categoryId = null); unawaited(_reload()); }), const Divider(), ..._categories.map((category) => ListTile(leading: const Icon(Icons.folder_outlined), title: Text(category.name), selected: _categoryId == category.id, onTap: () { Navigator.pop(context); setState(() => _categoryId = category.id); unawaited(_reload()); }, trailing: PopupMenuButton<String>(onSelected: (value) { if (value == 'rename') unawaited(_renameCategory(category)); if (value == 'delete') unawaited(_deleteCategory(category)); }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Переименовать')), PopupMenuItem(value: 'delete', child: Text('Удалить'))]))), const Divider(), ListTile(leading: const Icon(Icons.add), title: const Text('Создать подборку'), onTap: () { Navigator.pop(context); unawaited(_createCategory()); })])));
  Widget _emptyBody(String title) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('🐈', style: TextStyle(fontSize: 60)), const SizedBox(height: 12), Text(title == 'Неразобранное' ? 'Неразобранное пусто' : 'В этой подборке пока нет ссылок', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center), const SizedBox(height: 8), const Text('Сохраняйте ссылки через кнопку ниже или через Поделиться.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))])));
  Widget _errorBody() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, size: 56), const SizedBox(height: 12), const Text('Не удалось загрузить архив', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(_loadError ?? '', textAlign: TextAlign.center, maxLines: 5, overflow: TextOverflow.ellipsis), const SizedBox(height: 16), FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Повторить'))])));
}

class ArchiveCard extends StatelessWidget {
  const ArchiveCard({super.key, required this.item, required this.onTap, required this.onAction, required this.selected, required this.selectionMode});
  final ArchiveItem item; final VoidCallback onTap; final VoidCallback onAction; final bool selected; final bool selectionMode;
  ImageProvider<Object>? get _provider => _imageProvider(item.imageUrl);
  @override
  Widget build(BuildContext context) => Material(color: Colors.white, borderRadius: BorderRadius.circular(18), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Stack(children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _image()) , Padding(padding: const EdgeInsets.fromLTRB(12, 10, 44, 12), child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))) ]), if (!selectionMode) Positioned(right: 2, bottom: 2, child: IconButton(onPressed: onAction, icon: const Icon(Icons.north_east), tooltip: 'Переместить')), if (selectionMode) Positioned(top: 10, right: 10, child: Container(width: 28, height: 28, decoration: BoxDecoration(color: selected ? Colors.black : Colors.white70, shape: BoxShape.circle, border: Border.all(color: Colors.black38)), child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null)), if (item.metadataStatus == MetadataStatus.loading) const Positioned(left: 10, top: 10, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))])));
  Widget _image() { final provider = _provider; if (provider == null) return _placeholder(200); return Image(image: provider, fit: BoxFit.contain, width: double.infinity, errorBuilder: (_, __, ___) => _placeholder(200)); }
}

class ArchiveItemPage extends StatelessWidget {
  const ArchiveItemPage({super.key, required this.repository, required this.queue, required this.item, required this.categories});
  final ArchiveRepository repository; final MetadataQueue queue; final ArchiveItem item; final List<Category> categories;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Ссылка'), actions: [IconButton(onPressed: () => _move(context), icon: const Icon(Icons.north_east), tooltip: 'Переместить'), IconButton(onPressed: () => _edit(context), icon: const Icon(Icons.edit_outlined), tooltip: 'Редактировать')]), body: ListView(padding: const EdgeInsets.all(16), children: [Hero(tag: 'archive-image-${item.id}', child: ClipRRect(borderRadius: BorderRadius.circular(20), child: _image(item.imageUrl, 340, fit: BoxFit.contain))), const SizedBox(height: 18), Text(item.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), if (item.note.isNotEmpty) ...[const SizedBox(height: 22), const Text('Заметка', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(item.note)], const SizedBox(height: 18), ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.folder_outlined), title: Text(item.categoryId == null ? 'Неразобранное' : categories.firstWhereOrNull((c) => c.id == item.categoryId)?.name ?? 'Подборка')), ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(item.url, maxLines: 3, overflow: TextOverflow.ellipsis)), const SizedBox(height: 12), FilledButton.icon(onPressed: () => launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Открыть')), if (item.metadataStatus != MetadataStatus.success) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Не все метаданные удалось получить автоматически. Ссылка сохранена.'))]));
  Future<void> _edit(BuildContext context) async { final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => EditArchiveItemPage(repository: repository, queue: queue, item: item))); if (context.mounted && result != null) Navigator.pop(context, result); }
  Future<void> _move(BuildContext context) async { final value = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const ListTile(title: Text('Переместить', style: TextStyle(fontWeight: FontWeight.w800))), if (item.categoryId != null) ListTile(title: const Text('Неразобранное'), onTap: () => Navigator.pop(context, '__none__')), ...categories.where((c) => c.id != item.categoryId).map((c) => ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c.id)))]))); if (!context.mounted || value == null) return; final updated = item.copyWith(categoryId: value == '__none__' ? null : value, updatedAt: DateTime.now()); await repository.upsertItem(updated); if (context.mounted) Navigator.pop(context, updated); }
}

class EditArchiveItemPage extends StatefulWidget {
  const EditArchiveItemPage({super.key, required this.repository, required this.queue, required this.item});
  final ArchiveRepository repository; final MetadataQueue queue; final ArchiveItem item;
  @override State<EditArchiveItemPage> createState() => _EditArchiveItemPageState();
}
class _EditArchiveItemPageState extends State<EditArchiveItemPage> {
  late final TextEditingController _titleController = TextEditingController(text: widget.item.title);
  late final TextEditingController _noteController = TextEditingController(text: widget.item.note);
  String? _categoryId; bool _titleTouched = false; List<Category> _categories = const [];
  @override void initState() { super.initState(); _categoryId = widget.item.categoryId; unawaited(_loadCategories()); }
  Future<void> _loadCategories() async { try { final value = await widget.repository.getCategories(); if (mounted) setState(() => _categories = value); } catch (_) {} }
  @override void dispose() { _titleController.dispose(); _noteController.dispose(); super.dispose(); }
  Future<void> _chooseCategory() async { final value = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const ListTile(title: Text('Выбрать подборку', style: TextStyle(fontWeight: FontWeight.w800))), ListTile(title: const Text('Не выбирать'), onTap: () => Navigator.pop(context, '__none__')), ..._categories.map((c) => ListTile(title: Text(c.name), trailing: c.id == _categoryId ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, c.id)))]))); if (!mounted || value == null) return; setState(() => _categoryId = value == '__none__' ? null : value); }
  Future<void> _save() async { final entered = _titleController.text.trim(); final result = widget.item.copyWith(title: entered.isEmpty ? 'Без названия' : entered, titleSource: (_titleTouched || widget.item.titleSource == TitleSource.manual) ? TitleSource.manual : widget.item.titleSource, note: _noteController.text.trim(), categoryId: _categoryId, updatedAt: DateTime.now()); await widget.repository.upsertItem(result); if (mounted) Navigator.pop(context, result); }
  Future<void> _delete() async { final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Удалить эту ссылку?'), content: const Text('Объект будет удалён из архива.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))])) ?? false; if (ok != true) return; await widget.repository.deleteItem(widget.item.id); if (mounted) Navigator.pop(context); }
  @override Widget build(BuildContext context) { final categoryName = _categoryId == null ? 'Неразобранное' : _categories.firstWhereOrNull((c) => c.id == _categoryId)?.name ?? 'Подборка'; return Scaffold(appBar: AppBar(title: const Text('Редактировать')), body: ListView(padding: const EdgeInsets.all(16), children: [ClipRRect(borderRadius: BorderRadius.circular(18), child: _image(widget.item.imageUrl, 240, fit: BoxFit.contain)), const SizedBox(height: 18), TextField(controller: _titleController, onChanged: (_) => _titleTouched = true, decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())), const SizedBox(height: 12), TextField(controller: _noteController, maxLines: 4, decoration: const InputDecoration(labelText: 'Заметка', border: OutlineInputBorder())), const SizedBox(height: 12), ListTile(contentPadding: EdgeInsets.zero, title: const Text('Подборка', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(categoryName), trailing: const Icon(Icons.chevron_right), onTap: _chooseCategory), const SizedBox(height: 12), FilledButton(onPressed: _save, child: const Text('Сохранить')), const SizedBox(height: 8), OutlinedButton(onPressed: _delete, child: const Text('Удалить'))])); }
}

Widget _image(String? value, double height, {BoxFit fit = BoxFit.contain}) { final provider = _imageProvider(value); if (provider == null) return _placeholder(height); return Image(image: provider, height: height, fit: fit, width: double.infinity, errorBuilder: (_, __, ___) => _placeholder(height)); }
ImageProvider<Object>? _imageProvider(String? value) { if (value == null || value.isEmpty) return null; final uri = Uri.tryParse(value); if (uri?.scheme == 'file') return FileImage(File(uri!.toFilePath())); return NetworkImage(value); }
Widget _placeholder(double height) => Container(height: height, color: const Color(0xffecece9), alignment: Alignment.center, child: const Text('🐈', style: TextStyle(fontSize: 64)));
extension IterableFirstOrNull<E> on Iterable<E> { E? firstWhereOrNull(bool Function(E) test) { for (final value in this) { if (test(value)) return value; } return null; } }
