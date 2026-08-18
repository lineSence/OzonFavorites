import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/board.dart';
import 'models/product.dart';
import 'repositories/local_repository.dart';
import 'screens/product_detail_screen.dart';
import 'services/backup_service.dart';
import 'services/product_importer.dart';
import 'widgets/product_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = LocalRepository();
  await repository.init();
  runApp(ProductBoardsApp(repository: repository));
}

class ProductBoardsApp extends StatefulWidget {
  const ProductBoardsApp({super.key, required this.repository});
  final LocalRepository repository;
  @override State<ProductBoardsApp> createState() => _ProductBoardsAppState();
}

class _ProductBoardsAppState extends State<ProductBoardsApp> {
  static const shareChannel = MethodChannel('product_boards/share');
  SharePayload? sharedPayload;

  @override
  void initState() {
    super.initState();
    shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedData' && call.arguments is Map) {
        setState(() => sharedPayload = SharePayload.fromMap(Map<Object?, Object?>.from(call.arguments as Map)));
      }
    });
    shareChannel.invokeMethod('getInitialSharedData').then((value) {
      if (value is Map && mounted) {
        setState(() => sharedPayload = SharePayload.fromMap(Map<Object?, Object?>.from(value)));
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Product Boards',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.black), scaffoldBackgroundColor: const Color(0xfff6f6f4)),
    home: HomeScreen(repository: widget.repository, sharedPayload: sharedPayload, consumeSharedPayload: () => setState(() => sharedPayload = null)),
  );
}

class SharePayload {
  const SharePayload({this.url, this.title, this.imagePath});
  final String? url;
  final String? title;
  final String? imagePath;

  factory SharePayload.fromMap(Map<Object?, Object?> map) => SharePayload(
        url: map['url']?.toString(),
        title: map['title']?.toString(),
        imagePath: map['imagePath']?.toString(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.consumeSharedPayload, this.sharedPayload});
  final LocalRepository repository;
  final VoidCallback consumeSharedPayload;
  final SharePayload? sharedPayload;
  @override State<HomeScreen> createState() => _HomeScreenState();
}

enum SortMode { newest, oldest, priceUp, priceDown, name, priority }
enum LayoutMode { masonry, list }

class _HomeScreenState extends State<HomeScreen> {
  final importer = ProductImporter();
  final backupService = BackupService();
  List<Product> products = [];
  List<Board> boards = [];
  bool ready = false;
  bool importing = false;
  String query = '';
  int selectedBoard = 0;
  SortMode sort = SortMode.newest;
  LayoutMode layout = LayoutMode.masonry;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeIncoming());
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedPayload != null && widget.sharedPayload != oldWidget.sharedPayload) _consumeIncoming();
  }

  Future<void> _load() async {
    final p = await widget.repository.getProducts();
    final b = await widget.repository.getBoards();
    if (!mounted) return;
    setState(() { products = p; boards = b; ready = true; });
  }

  Future<void> _consumeIncoming() async {
    final payload = widget.sharedPayload;
    final url = payload?.url;
    if (url == null || url.isEmpty || importing) return;
    widget.consumeSharedPayload();
    await _addUrl(url, sharedTitle: payload?.title, sharedImagePath: payload?.imagePath);
  }

  Future<void> _addUrl(String raw, {String? sharedTitle, String? sharedImagePath}) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || !{'http', 'https'}.contains(uri.scheme)) {
      _snack('Нужна ссылка http/https');
      return;
    }
    final normalized = _normalize(uri.toString());
    final duplicate = products.cast<Product?>().firstWhere((p) => p != null && _normalize(p.url) == normalized, orElse: () => null);
    if (duplicate != null) { await _editProduct(duplicate); return; }
    setState(() => importing = true);
    ImportedProductData data = const ImportedProductData();
    try { data = await importer.fetch(uri); } catch (_) {}
    final product = Product(
      id: widget.repository.newId(), url: uri.toString(), source: _source(uri),
      title: data.title?.isNotEmpty == true ? data.title! : (sharedTitle?.trim().isNotEmpty == true ? _cleanSharedTitle(sharedTitle!) : _fallbackTitle(uri)),
      imageUrl: data.imageUrl ?? sharedImagePath,
      price: data.price, currency: data.currency ?? '₽', createdAt: DateTime.now(),
    );
    await widget.repository.upsertProduct(product);
    if (!mounted) return;
    setState(() { products = [product, ...products]; importing = false; });
    await _editProduct(product);
  }

  String _normalize(String value) => (Uri.tryParse(value)?.replace(query: '', fragment: '').toString() ?? value).replaceAll(RegExp(r'/$'), '').toLowerCase();
  String _source(Uri u) { final h = u.host.toLowerCase(); if (h.contains('ozon')) return 'OZON'; if (h.contains('wildberries')) return 'Wildberries'; if (h.contains('amazon')) return 'Amazon'; if (h.contains('market.yandex')) return 'Яндекс Маркет'; return h.isEmpty ? 'Другое' : h; }
  String _fallbackTitle(Uri u) {
    final segments = u.pathSegments;
    if (segments.length >= 2 && segments.first.toLowerCase() == 'product') {
      return 'Товар OZON ${segments.last}';
    }
    return 'Новый товар';
  }

  String _cleanSharedTitle(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.toLowerCase() == 'share' || normalized.toLowerCase() == 'ozon') return 'Товар OZON';
    return normalized;
  }

  List<Product> get visible {
    Iterable<Product> out = products;
    if (selectedBoard > 0 && selectedBoard <= boards.length) out = out.where((p) => p.boardIds.contains(boards[selectedBoard - 1].id));
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) out = out.where((p) => '${p.title} ${p.source} ${p.note} ${p.tags.join(' ')}'.toLowerCase().contains(q));
    final list = out.toList();
    switch (sort) {
      case SortMode.newest: list.sort((a,b) => b.createdAt.compareTo(a.createdAt));
      case SortMode.oldest: list.sort((a,b) => a.createdAt.compareTo(b.createdAt));
      case SortMode.priceUp: list.sort((a,b) => (a.price ?? double.infinity).compareTo(b.price ?? double.infinity));
      case SortMode.priceDown: list.sort((a,b) => (b.price ?? -1).compareTo(a.price ?? -1));
      case SortMode.name: list.sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SortMode.priority: list.sort((a,b) => b.priority.compareTo(a.priority));
    }
    return list;
  }

  Future<void> _editProduct(Product product) async {
    final result = await showModalBottomSheet<Product>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => ProductEditor(product: product, boards: boards));
    if (result == null) return;
    await widget.repository.upsertProduct(result);
    if (!mounted) return;
    final i = products.indexWhere((p) => p.id == result.id);
    setState(() { if (i >= 0) products[i] = result; });
  }

  Future<void> _createBoard() async {
    final c = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Новая доска'), content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Например, Мастерская')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Создать'))],
    ));
    c.dispose();
    if (name == null || name.isEmpty) return;
    final board = Board(id: widget.repository.newId(), name: name, createdAt: DateTime.now(), sortOrder: boards.length);
    await widget.repository.upsertBoard(board);
    if (mounted) setState(() => boards.add(board));
  }

  Future<void> _delete(Product p) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Удалить товар?'), content: Text(p.title),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))],
    ));
    if (ok != true) return;
    await widget.repository.deleteProduct(p.id);
    if (mounted) setState(() => products.removeWhere((x) => x.id == p.id));
  }

  Future<void> _settings() async {
    await showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Настройки', style: TextStyle(fontWeight: FontWeight.w800))),
      ListTile(leading: const Icon(Icons.upload_outlined), title: const Text('Поделиться резервной копией'), onTap: () async { Navigator.pop(context); await backupService.shareJson(await widget.repository.exportData()); }),
      ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Восстановить из буфера обмена'), onTap: () async { Navigator.pop(context); final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text; if (text == null) return; try { await widget.repository.importData(backupService.decode(text)); await _load(); _snack('Готово'); } catch (_) { _snack('Некорректная резервная копия'); } }),
      const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 20), child: Align(alignment: Alignment.centerLeft, child: Text('Только локальное хранение. Облачной синхронизации нет.', style: TextStyle(color: Colors.black54)))),
    ])));
  }

  void _snack(String s) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final items = visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Product Boards', style: TextStyle(fontWeight: FontWeight.w900)), actions: [
        IconButton(tooltip: 'Вид', onPressed: () => setState(() => layout = layout == LayoutMode.masonry ? LayoutMode.list : LayoutMode.masonry), icon: Icon(layout == LayoutMode.masonry ? Icons.view_list : Icons.grid_view)),
        IconButton(tooltip: 'Настройки', onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
      ]),
      drawer: Drawer(child: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Доски', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
        ListTile(leading: const Icon(Icons.home_outlined), title: const Text('Все товары'), selected: selectedBoard == 0, onTap: () { Navigator.pop(context); setState(() => selectedBoard = 0); }),
        ...boards.asMap().entries.map((e) => ListTile(leading: const Icon(Icons.dashboard_outlined), title: Text(e.value.name), selected: selectedBoard == e.key + 1, onTap: () { Navigator.pop(context); setState(() => selectedBoard = e.key + 1); })),
        const Divider(), ListTile(leading: const Icon(Icons.add), title: const Text('Создать доску'), onTap: () { Navigator.pop(context); _createBoard(); }),
      ]))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
          Expanded(child: TextField(onChanged: (v) => setState(() => query = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Поиск', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
          const SizedBox(width: 8), PopupMenuButton<SortMode>(onSelected: (v) => setState(() => sort = v), itemBuilder: (_) => const [PopupMenuItem(value: SortMode.newest, child: Text('Новые')), PopupMenuItem(value: SortMode.oldest, child: Text('Старые')), PopupMenuItem(value: SortMode.priceUp, child: Text('Цена ↑')), PopupMenuItem(value: SortMode.priceDown, child: Text('Цена ↓')), PopupMenuItem(value: SortMode.priority, child: Text('Приоритет')), PopupMenuItem(value: SortMode.name, child: Text('Название'))], child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.tune))),
        ])),
        if (importing) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: items.isEmpty ? _empty() : _content(items)),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _manualAdd, icon: const Icon(Icons.add), label: const Text('Добавить')),
    );
  }

  Widget _content(List<Product> items) {
    if (layout == LayoutMode.list) return ListView.builder(padding: const EdgeInsets.fromLTRB(12, 8, 12, 100), itemCount: items.length, itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: ProductListTile(product: items[i], onTap: () => _openDetail(items[i]), onLongPress: () => _menu(items[i]))));
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1200 ? 5 : width >= 900 ? 4 : width >= 600 ? 3 : 2;
    return MasonryGridView.count(padding: const EdgeInsets.fromLTRB(12, 8, 12, 100), crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, itemCount: items.length, itemBuilder: (_, i) => ProductCard(product: items[i], onTap: () => _openDetail(items[i]), onLongPress: () => _menu(items[i])));
  }

  Widget _empty() => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.bookmark_add_outlined, size: 64, color: Colors.black38), const SizedBox(height: 12), const Text('Пока пусто', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 8), const Text('Поделитесь товаром из OZON через системную кнопку «Поделиться».', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)), const SizedBox(height: 16), OutlinedButton(onPressed: _manualAdd, child: const Text('Добавить ссылку'))])));

  Future<void> _manualAdd() async {
    final c = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Добавить товар'), content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://www.ozon.ru/...')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Продолжить'))]));
    c.dispose();
    if (url != null && url.isNotEmpty) await _addUrl(url);
  }

  Future<void> _openDetail(Product product) async {
    final result = await Navigator.push<Product>(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)));
    if (result == null) return;
    await widget.repository.upsertProduct(result);
    final i = products.indexWhere((p) => p.id == result.id);
    if (i >= 0 && mounted) setState(() => products[i] = result);
  }

  Future<void> _menu(Product p) async {
    final action = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Изменить'), onTap: () => Navigator.pop(context, 'edit')), ListTile(leading: const Icon(Icons.open_in_new), title: const Text('Открыть магазин'), onTap: () => Navigator.pop(context, 'open')), ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Удалить'), onTap: () => Navigator.pop(context, 'delete'))])));
    if (action == 'edit') await _editProduct(p);
    if (action == 'open') await launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication);
    if (action == 'delete') await _delete(p);
  }
}

class ProductEditor extends StatefulWidget {
  const ProductEditor({super.key, required this.product, required this.boards});
  final Product product; final List<Board> boards;
  @override State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  late final title = TextEditingController(text: widget.product.title);
  late final price = TextEditingController(text: widget.product.price?.toString() ?? '');
  late final image = TextEditingController(text: widget.product.imageUrl ?? '');
  late final note = TextEditingController(text: widget.product.note);
  late final tags = TextEditingController(text: widget.product.tags.join(', '));
  late Set<String> selected = {...widget.product.boardIds};
  late ProductStatus status = widget.product.status;
  late int priority = widget.product.priority;
  @override void dispose() { title.dispose(); price.dispose(); image.dispose(); note.dispose(); tags.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(widget.product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 12),
    TextField(controller: title, decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())), const SizedBox(height: 10),
    Row(children: [Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена', border: OutlineInputBorder()))), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<ProductStatus>(initialValue: status, decoration: const InputDecoration(labelText: 'Статус', border: OutlineInputBorder()), items: ProductStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(_status(s)))).toList(), onChanged: (v) => setState(() => status = v ?? status)))]), const SizedBox(height: 10),
    TextField(controller: image, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL изображения', border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: tags, decoration: const InputDecoration(labelText: 'Теги через запятую', border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Заметка', border: OutlineInputBorder())),
    Row(children: [const Text('Приоритет'), Expanded(child: Slider(value: priority.toDouble(), min: 0, max: 3, divisions: 3, onChanged: (v) => setState(() => priority = v.round())))]), const Text('Доски', style: TextStyle(fontWeight: FontWeight.w800)),
    ...widget.boards.map((b) => CheckboxListTile(contentPadding: EdgeInsets.zero, value: selected.contains(b.id), title: Text(b.name), onChanged: (v) => setState(() { if (v == true) selected.add(b.id); else selected.remove(b.id); }))), const SizedBox(height: 8),
    SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Сохранить'))),
  ])));

  void _save() => Navigator.pop(context, widget.product.copyWith(title: title.text.trim().isEmpty ? 'Без названия' : title.text.trim(), price: double.tryParse(price.text.replaceAll(' ', '').replaceAll(',', '.')), imageUrl: image.text.trim().isEmpty ? null : image.text.trim(), note: note.text.trim(), tags: tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList(), boardIds: selected.toList(), status: status, priority: priority, updatedAt: DateTime.now()));
  String _status(ProductStatus s) => switch (s) { ProductStatus.wishlist => 'Хочу купить', ProductStatus.considering => 'Думаю', ProductStatus.purchased => 'Куплено', ProductStatus.archived => 'Архив' };
}
