import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/board.dart';
import 'models/product.dart';
import 'models/product_preview.dart';
import 'models/tag.dart';
import 'repositories/local_repository.dart';
import 'repositories/product_repository.dart';
import 'screens/product_detail_screen.dart';
import 'services/backup_service.dart';
import 'services/price_tracker.dart';
import 'services/product_preview_resolver.dart';
import 'widgets/product_card.dart';
import 'widgets/product_preview_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = LocalRepository();
  await repository.init();
  runApp(ProductBoardsApp(repository: repository));
}

class ProductBoardsApp extends StatefulWidget {
  const ProductBoardsApp({super.key, required this.repository});
  final ProductRepository repository;

  @override
  State<ProductBoardsApp> createState() => _ProductBoardsAppState();
}

class _ProductBoardsAppState extends State<ProductBoardsApp> {
  static const shareChannel = MethodChannel('product_boards/share');
  SharePayload? sharedPayload;
  ThemeMode themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
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

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('theme_mode');
    if (!mounted) return;
    setState(() {
      themeMode = switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  ThemeData _lightTheme() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xfff6f6f4),
        inputDecorationTheme: const InputDecorationTheme(filled: true),
      );

  ThemeData _darkTheme() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xff121212),
        cardColor: const Color(0xff1d1d1d),
        inputDecorationTheme: const InputDecorationTheme(filled: true),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pinzon',
        theme: _lightTheme(),
        darkTheme: _darkTheme(),
        themeMode: themeMode,
        home: HomeScreen(
          repository: widget.repository,
          sharedPayload: sharedPayload,
          themeMode: themeMode,
          onThemeModeChanged: _setThemeMode,
          consumeSharedPayload: () => setState(() => sharedPayload = null),
        ),
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

enum SortMode { newest, oldest, priceUp, priceDown, name, priority }
enum LayoutMode { masonry, list }

const _commonBoardFilter = '__common__';

class _BoardSelection {
  const _BoardSelection(this.boardIds);
  final List<String> boardIds;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.consumeSharedPayload,
    this.sharedPayload,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ProductRepository repository;
  final VoidCallback consumeSharedPayload;
  final SharePayload? sharedPayload;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final backupService = BackupService();
  final resolver = ProductPreviewResolver();
  late final PriceTracker priceTracker;
  List<Product> products = [];
  List<Board> boards = [];
  List<Tag> tags = [];
  bool ready = false;
  bool importing = false;
  bool refreshingPrices = false;
  String query = '';
  String? selectedBoardFilter;
  String? selectedSource;
  SortMode sort = SortMode.newest;
  LayoutMode layout = LayoutMode.masonry;
  late final Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    priceTracker = PriceTracker(repository: widget.repository);
    _loadFuture = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeIncoming());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPrices(showSummary: false));
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedPayload != null && widget.sharedPayload != oldWidget.sharedPayload) _consumeIncoming();
  }

  Future<void> _load() async {
    final loadedProducts = await widget.repository.getProducts();
    final loadedBoards = await widget.repository.getBoards();
    final loadedTags = await widget.repository.getTags();
    if (!mounted) return;
    setState(() {
      products = loadedProducts;
      boards = loadedBoards;
      tags = loadedTags;
      ready = true;
    });
  }

  Future<void> _consumeIncoming() async {
    await _loadFuture;
    if (!mounted) return;
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
    if (duplicate != null) {
      await _openProduct(duplicate);
      return;
    }

    setState(() => importing = true);
    try {
      final preview = await resolver.resolve(uri, sharedTitle: sharedTitle, sharedImageUri: sharedImagePath);
      if (!mounted) return;
      final selection = await _showSavePreview(preview);
      if (selection == null) return;
      final product = Product(
        id: widget.repository.newId(),
        url: uri.toString(),
        source: _source(uri),
        title: preview.title,
        imageUrl: preview.image,
        price: preview.price,
        currency: preview.currency,
        createdAt: DateTime.now(),
        note: preview.description ?? '',
        boardIds: selection.boardIds,
      );
      await widget.repository.upsertProduct(product);
      if (!mounted) return;
      setState(() => products = [product, ...products]);
      await _rememberBoardSelection(selection.boardIds);
      _snack('Товар сохранён');
    } catch (_) {
      if (mounted) _snack('Не удалось получить превью товара');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<_BoardSelection?> _showSavePreview(ProductPreview preview) async {
    final prefs = await SharedPreferences.getInstance();
    final lastBoardId = prefs.getString('last_board_id');
    var selected = lastBoardId != null && boards.any((b) => b.id == lastBoardId) ? <String>[lastBoardId] : <String>[];

    return showModalBottomSheet<_BoardSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Сохранить товар', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  if (preview.image != null)
                    ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(height: 220, width: double.infinity, child: ProductPreviewImage(preview: preview)))
                  else
                    Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                      child: const Icon(Icons.image_not_supported_outlined, size: 56),
                    ),
                  const SizedBox(height: 12),
                  Text(preview.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  if (preview.price != null) ...[
                    const SizedBox(height: 4),
                    Text('${preview.price!.toStringAsFixed(0)} ${preview.currency}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                  const SizedBox(height: 4),
                  Text(preview.siteName, style: Theme.of(context).textTheme.bodySmall),
                  if (preview.description != null && preview.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(preview.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 18),
                  Text('Сохранить в', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Общее'),
                        selected: selected.isEmpty,
                        onSelected: (_) => setSheetState(() => selected = []),
                      ),
                      ...boards.map((board) => FilterChip(
                            label: Text(board.name),
                            selected: selected.contains(board.id),
                            onSelected: (value) => setSheetState(() {
                              if (value) {
                                selected = [...selected.where((id) => id != board.id), board.id];
                              } else {
                                selected = selected.where((id) => id != board.id).toList();
                              }
                            }),
                          )),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, _BoardSelection(List.unmodifiable(selected))),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить товар'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _rememberBoardSelection(List<String> boardIds) async {
    final prefs = await SharedPreferences.getInstance();
    if (boardIds.isEmpty) {
      await prefs.remove('last_board_id');
    } else {
      await prefs.setString('last_board_id', boardIds.first);
    }
  }

  String _normalize(String value) => (Uri.tryParse(value)?.replace(query: '', fragment: '').toString() ?? value).replaceAll(RegExp(r'/$'), '').toLowerCase();

  String _source(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.contains('ozon')) return 'OZON';
    if (host.contains('wildberries')) return 'Wildberries';
    if (host.contains('market.yandex')) return 'Яндекс Маркет';
    if (host.contains('avito')) return 'Avito';
    if (host.contains('amazon')) return 'Amazon';
    return host.isEmpty ? 'Другое' : host;
  }

  String _tagNames(Product product) {
    final byId = {for (final tag in tags) tag.id: tag};
    return product.tagIds.map((id) => byId[id]?.name ?? '').where((name) => name.isNotEmpty).join(' ');
  }

  List<String> get sources {
    final values = products.map((p) => p.source.trim()).where((s) => s.isNotEmpty).toSet().toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<Product> get visible {
    Iterable<Product> out = products;
    if (selectedSource != null) out = out.where((p) => p.source == selectedSource);
    if (selectedBoardFilter == _commonBoardFilter) {
      out = out.where((p) => p.boardIds.isEmpty);
    } else if (selectedBoardFilter != null) {
      out = out.where((p) => p.boardIds.contains(selectedBoardFilter));
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) out = out.where((p) => '${p.title} ${p.source} ${p.note} ${_tagNames(p)}'.toLowerCase().contains(q));
    final list = out.toList();
    switch (sort) {
      case SortMode.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortMode.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SortMode.priceUp:
        list.sort((a, b) => (a.price ?? double.infinity).compareTo(b.price ?? double.infinity));
      case SortMode.priceDown:
        list.sort((a, b) => (b.price ?? -1).compareTo(a.price ?? -1));
      case SortMode.name:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SortMode.priority:
        list.sort((a, b) => b.priority.compareTo(a.priority));
    }
    return list;
  }

  Future<void> _openProduct(Product product) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product, tags: tags, repository: widget.repository)));
    await _load();
  }

  Future<void> _editProduct(Product product) async {
    final result = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductEditor(product: product, boards: boards, tags: tags, repository: widget.repository),
    );
    if (result == null) return;
    await widget.repository.upsertProduct(result);
    if (!mounted) return;
    final index = products.indexWhere((p) => p.id == result.id);
    setState(() {
      if (index >= 0) products[index] = result;
    });
    await _rememberBoardSelection(result.boardIds);
  }

  Future<void> _showProductMenu(Product product) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Изменить'), onTap: () => Navigator.pop(context, 'edit')),
            ListTile(leading: const Icon(Icons.open_in_new), title: const Text('Открыть на сайте'), onTap: () => Navigator.pop(context, 'open')),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Удалить'), onTap: () => Navigator.pop(context, 'delete')),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'edit':
        await _editProduct(product);
      case 'open':
        final uri = Uri.tryParse(product.url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      case 'delete':
        await _deleteProduct(product);
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(product.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repository.deleteProduct(product.id);
    if (mounted) setState(() => products.removeWhere((p) => p.id == product.id));
  }

  Future<void> _createBoard() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Новая доска'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Например, Мастерская')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Создать')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final board = Board(id: widget.repository.newId(), name: name, createdAt: DateTime.now(), sortOrder: boards.length);
    await widget.repository.upsertBoard(board);
    if (mounted) setState(() => boards.add(board));
  }

  Future<void> _refreshPrices({bool showSummary = false}) async {
    if (refreshingPrices) return;
    await _loadFuture;
    if (!mounted) return;
    final active = products.where((p) => p.status == ProductStatus.wishlist || p.status == ProductStatus.considering).toList();
    if (active.isEmpty) {
      if (showSummary) _snack('Нет товаров для обновления цен');
      return;
    }
    setState(() => refreshingPrices = true);
    var updated = 0;
    var failed = 0;
    const batch = 3;
    for (var i = 0; i < active.length; i += batch) {
      final chunk = active.skip(i).take(batch).toList();
      final results = await Future.wait(chunk.map((product) => priceTracker.updatePrice(product)));
      for (final result in results) {
        if (result.status == PriceUpdateStatus.updated) updated++;
        if (result.status == PriceUpdateStatus.failed) failed++;
      }
    }
    if (!mounted) return;
    setState(() => refreshingPrices = false);
    await _load();
    if (showSummary) _snack(updated == 0 && failed == 0 ? 'Цены не изменились' : 'Обновлено цен: $updated, ошибок: $failed');
  }

  String _themeLabel() => switch (widget.themeMode) {
        ThemeMode.system => 'Системная',
        ThemeMode.light => 'Светлая',
        ThemeMode.dark => 'Тёмная',
      };

  Future<void> _chooseTheme() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Тема оформления'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, ThemeMode.system), child: const ListTile(leading: Icon(Icons.brightness_auto_outlined), title: Text('Системная'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, ThemeMode.light), child: const ListTile(leading: Icon(Icons.light_mode_outlined), title: Text('Светлая'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, ThemeMode.dark), child: const ListTile(leading: Icon(Icons.dark_mode_outlined), title: Text('Тёмная'))),
        ],
      ),
    );
    if (selected != null) await widget.onThemeModeChanged(selected);
  }

  Future<void> _settings() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Настройки', style: TextStyle(fontWeight: FontWeight.w800))),
            ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Тема оформления'), trailing: Text(_themeLabel()), onTap: () async { Navigator.pop(context); await _chooseTheme(); }),
            ListTile(leading: const Icon(Icons.upload_outlined), title: const Text('Поделиться резервной копией'), onTap: () async { Navigator.pop(context); await backupService.shareJson(await widget.repository.exportData()); }),
            ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Восстановить из буфера обмена'), onTap: () async {
              Navigator.pop(context);
              final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
              if (text == null) return;
              try {
                await widget.repository.importData(backupService.decode(text));
                await _load();
                if (mounted) _snack('Готово');
              } catch (_) {
                if (mounted) _snack('Некорректная резервная копия');
              }
            }),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), child: Align(alignment: Alignment.centerLeft, child: Text('Только локальное хранение. Облачной синхронизации нет.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))),
          ],
        ),
      ),
    );
  }

  void _snack(String message) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

  Widget _drawerItem({required IconData icon, required String title, required bool selected, required VoidCallback onTap}) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        selected: selected,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final items = visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pinzon', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Вид', onPressed: () => setState(() => layout = layout == LayoutMode.masonry ? LayoutMode.list : LayoutMode.masonry), icon: Icon(layout == LayoutMode.masonry ? Icons.view_list : Icons.grid_view)),
          IconButton(tooltip: refreshingPrices ? 'Обновление цен…' : 'Обновить цены', onPressed: refreshingPrices ? null : () => _refreshPrices(showSummary: true), icon: refreshingPrices ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh)),
          IconButton(tooltip: 'Настройки', onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(padding: EdgeInsets.all(12), child: Text('Pinzon', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
              _drawerItem(icon: Icons.home_outlined, title: 'Все товары', selected: selectedBoardFilter == null && selectedSource == null, onTap: () { Navigator.pop(context); setState(() { selectedBoardFilter = null; selectedSource = null; }); }),
              const Divider(),
              const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), child: Text('Без доски', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey))),
              _drawerItem(icon: Icons.inbox_outlined, title: 'Общее', selected: selectedBoardFilter == _commonBoardFilter, onTap: () { Navigator.pop(context); setState(() { selectedBoardFilter = _commonBoardFilter; selectedSource = null; }); }),
              const Divider(),
              const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), child: Text('Сайты', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey))),
              ...sources.map((source) => _drawerItem(icon: source == 'OZON' ? Icons.shopping_bag_outlined : source == 'Wildberries' ? Icons.storefront_outlined : source == 'Avito' ? Icons.local_offer_outlined : Icons.language_outlined, title: source, selected: selectedSource == source, onTap: () { Navigator.pop(context); setState(() { selectedSource = source; selectedBoardFilter = null; }); })),
              const Divider(),
              const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), child: Text('Доски', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey))),
              ...boards.map((board) => _drawerItem(icon: Icons.dashboard_outlined, title: board.name, selected: selectedBoardFilter == board.id, onTap: () { Navigator.pop(context); setState(() { selectedBoardFilter = board.id; selectedSource = null; }); })),
              const Divider(),
              ListTile(leading: const Icon(Icons.add), title: const Text('Создать доску'), onTap: () { Navigator.pop(context); _createBoard(); }),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Поиск по товарам', filled: true, border: const OutlineInputBorder(borderSide: BorderSide.none), fillColor: Theme.of(context).colorScheme.surfaceContainerHighest), onChanged: (value) => setState(() => query = value))),
                const SizedBox(width: 8),
                PopupMenuButton<SortMode>(initialValue: sort, onSelected: (value) => setState(() => sort = value), itemBuilder: (_) => const [
                  PopupMenuItem(value: SortMode.newest, child: Text('Новые')),
                  PopupMenuItem(value: SortMode.oldest, child: Text('Старые')),
                  PopupMenuItem(value: SortMode.priceUp, child: Text('Цена ↑')),
                  PopupMenuItem(value: SortMode.priceDown, child: Text('Цена ↓')),
                  PopupMenuItem(value: SortMode.name, child: Text('По названию')),
                  PopupMenuItem(value: SortMode.priority, child: Text('Приоритет')),
                ], icon: const Icon(Icons.sort)),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('Добавьте товар через кнопку + или поделитесь ссылкой из магазина.', textAlign: TextAlign.center)))
                : layout == LayoutMode.masonry
                    ? MasonryGridView.count(padding: const EdgeInsets.all(12), crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, itemCount: items.length, itemBuilder: (_, i) => ProductCard(product: items[i], onTap: () => _openProduct(items[i]), onLongPress: () => _showProductMenu(items[i])))
                    : ListView.separated(padding: const EdgeInsets.all(12), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) => ProductListTile(product: items[i], onTap: () => _openProduct(items[i]), onLongPress: () => _showProductMenu(items[i]))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _showAddDialog, icon: const Icon(Icons.add), label: const Text('Добавить')),
    );
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить товар'),
        content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://...')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Продолжить'))],
      ),
    );
    controller.dispose();
    if (url != null && url.isNotEmpty) await _addUrl(url);
  }
}

class ProductEditor extends StatefulWidget {
  const ProductEditor({super.key, required this.product, required this.boards, required this.tags, required this.repository});
  final Product product;
  final List<Board> boards;
  final List<Tag> tags;
  final ProductRepository repository;

  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  late Product p;
  late List<String> selectedBoardIds;

  @override
  void initState() {
    super.initState();
    p = widget.product;
    selectedBoardIds = [...widget.product.boardIds];
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .86,
        maxChildSize: .95,
        builder: (_, controller) => Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              TextField(decoration: const InputDecoration(labelText: 'Название'), controller: TextEditingController(text: p.title), onChanged: (v) => p = p.copyWith(title: v)),
              const SizedBox(height: 10),
              TextField(decoration: const InputDecoration(labelText: 'URL'), controller: TextEditingController(text: p.url), onChanged: (v) => p = p.copyWith(url: v)),
              const SizedBox(height: 10),
              TextField(decoration: const InputDecoration(labelText: 'Цена'), keyboardType: TextInputType.number, controller: TextEditingController(text: p.price?.toStringAsFixed(0) ?? ''), onChanged: (v) => p = p.copyWith(price: double.tryParse(v.replaceAll(',', '.')))),
              const SizedBox(height: 14),
              const Text('Доски', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(label: const Text('Общее'), selected: selectedBoardIds.isEmpty, onSelected: (_) => setState(() => selectedBoardIds = [])),
                  ...widget.boards.map((board) => FilterChip(
                        label: Text(board.name),
                        selected: selectedBoardIds.contains(board.id),
                        onSelected: (value) => setState(() {
                          if (value) {
                            selectedBoardIds = [...selectedBoardIds.where((id) => id != board.id), board.id];
                          } else {
                            selectedBoardIds = selectedBoardIds.where((id) => id != board.id).toList();
                          }
                        }),
                      )),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<ProductStatus>(initialValue: p.status, decoration: const InputDecoration(labelText: 'Статус'), items: ProductStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(), onChanged: (v) => setState(() => p = p.copyWith(status: v ?? p.status))),
              const SizedBox(height: 10),
              TextField(decoration: const InputDecoration(labelText: 'Заметка'), controller: TextEditingController(text: p.note), minLines: 3, maxLines: 6, onChanged: (v) => p = p.copyWith(note: v)),
              const SizedBox(height: 18),
              FilledButton(onPressed: () => Navigator.pop(context, p.copyWith(boardIds: selectedBoardIds)), child: const Text('Сохранить')),
            ],
          ),
        ),
      );
}

extension ProductStatusLabel on ProductStatus {
  String get label => switch (this) {
        ProductStatus.wishlist => 'Желаю',
        ProductStatus.considering => 'Рассматриваю',
        ProductStatus.purchased => 'Куплено',
        ProductStatus.archived => 'Архив',
      };
}
