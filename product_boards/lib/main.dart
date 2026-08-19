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
import 'screens/image_diagnostics_screen.dart';
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
      if (value is Map && mounted) setState(() => sharedPayload = SharePayload.fromMap(Map<Object?, Object?>.from(value)));
    });
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('theme_mode');
    if (!mounted) return;
    setState(() => themeMode = switch (value) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
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
        scaffoldBackgroundColor: const Color(0xfff6f5f1),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, surfaceTintColor: Colors.transparent),
        inputDecorationTheme: const InputDecorationTheme(filled: true),
      );

  ThemeData _darkTheme() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xff111111),
        cardColor: const Color(0xff1a1a1a),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, surfaceTintColor: Colors.transparent),
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
  const HomeScreen({super.key, required this.repository, required this.consumeSharedPayload, this.sharedPayload, required this.themeMode, required this.onThemeModeChanged});
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
  final searchController = TextEditingController();
  final searchFocus = FocusNode();
  late final PriceTracker priceTracker;
  List<Product> products = [];
  List<Board> boards = [];
  List<Tag> tags = [];
  bool ready = false;
  bool importing = false;
  bool refreshingPrices = false;
  bool searchActive = false;
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
  void dispose() {
    searchController.dispose();
    searchFocus.dispose();
    super.dispose();
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
        imageUrl: preview.imageUrl,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Добавить товар', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 220,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  if (preview.imageUrl != null || preview.localImageUri != null)
                    ClipRRect(borderRadius: BorderRadius.circular(22), child: ProductPreviewImage(preview: preview))
                  else
                    Container(
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
                      child: const Center(child: Icon(Icons.image_not_supported_outlined, size: 52)),
                    ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: .52),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Диагностика изображения',
                        icon: const Icon(Icons.bug_report_outlined, color: Colors.white),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImageDiagnosticsScreen())),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Text(preview.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, height: 1.16)),
              const SizedBox(height: 5),
              Row(children: [
                if (preview.price != null) Text('${preview.price!.toStringAsFixed(0)} ${preview.currency}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const Spacer(),
                Text(preview.siteName, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
              if (preview.description != null && preview.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(preview.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 20),
              Text('Сохранить в', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: const Text('Общее'), selected: selected.isEmpty, onSelected: (_) => setSheetState(() => selected = [])),
                ...boards.map((board) => FilterChip(label: Text(board.name), selected: selected.contains(board.id), onSelected: (value) => setSheetState(() => selected = value ? [...selected.where((id) => id != board.id), board.id] : selected.where((id) => id != board.id).toList()))),
              ]),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(sheetContext, _BoardSelection(List.unmodifiable(selected))), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))), child: const Text('Сохранить товар'))),
            ]),
          ),
        ),
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
      case SortMode.newest: list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortMode.oldest: list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SortMode.priceUp: list.sort((a, b) => (a.price ?? double.infinity).compareTo(b.price ?? double.infinity));
      case SortMode.priceDown: list.sort((a, b) => (b.price ?? -1).compareTo(a.price ?? -1));
      case SortMode.name: list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SortMode.priority: list.sort((a, b) => b.priority.compareTo(a.priority));
    }
    return list;
  }

  Future<void> _openProduct(Product product) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product, tags: tags, repository: widget.repository)));
    await _load();
  }

  Future<void> _showSortMenu() async {
    final selected = await showModalBottomSheet<SortMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Сортировка', style: TextStyle(fontWeight: FontWeight.w900))),
        ...SortMode.values.map((mode) => ListTile(title: Text(switch (mode) { SortMode.newest => 'Новые', SortMode.oldest => 'Старые', SortMode.priceUp => 'Цена ↑', SortMode.priceDown => 'Цена ↓', SortMode.name => 'По названию', SortMode.priority => 'Приоритет' }), trailing: sort == mode ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(sheetContext, mode))),
        const SizedBox(height: 8),
      ])),
    );
    if (selected != null && mounted) setState(() => sort = selected);
  }

  Future<void> _showSourceMenu() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Магазин', style: TextStyle(fontWeight: FontWeight.w900))),
        ListTile(title: const Text('Все магазины'), trailing: selectedSource == null ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(sheetContext, '')),
        ...sources.map((source) => ListTile(title: Text(source), trailing: selectedSource == source ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(sheetContext, source))),
        const SizedBox(height: 8),
      ])),
    );
    if (selected != null && mounted) setState(() => selectedSource = selected.isEmpty ? null : selected);
  }

  Future<void> _showProductMenu(Product product) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 10), child: Align(alignment: Alignment.centerLeft, child: Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)))),
        ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Изменить'), onTap: () => Navigator.pop(sheetContext, 'edit')),
        ListTile(leading: const Icon(Icons.open_in_new_outlined), title: const Text('Открыть на сайте'), onTap: () => Navigator.pop(sheetContext, 'open')),
        ListTile(leading: const Icon(Icons.drive_file_move_outlined), title: const Text('Переместить в доску'), onTap: () => Navigator.pop(sheetContext, 'move')),
        ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Удалить'), onTap: () => Navigator.pop(sheetContext, 'delete')),
        const SizedBox(height: 8),
      ])),
    );
    switch (choice) {
      case 'edit': await _editProduct(product);
      case 'open':
        final uri = Uri.tryParse(product.url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      case 'move': await _moveProduct(product);
      case 'delete': await _deleteProduct(product);
    }
  }

  Future<void> _moveProduct(Product product) async {
    var selected = [...product.boardIds];
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Переместить товар', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('Общее'), selected: selected.isEmpty, onSelected: (_) => setSheetState(() => selected = [])),
          ...boards.map((board) => FilterChip(label: Text(board.name), selected: selected.contains(board.id), onSelected: (value) => setSheetState(() => selected = value ? [...selected.where((id) => id != board.id), board.id] : selected.where((id) => id != board.id).toList()))),
        ]),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(sheetContext, List.unmodifiable(selected)), child: const Text('Сохранить'))),
      ])))),
    );
    if (result == null) return;
    final updated = product.copyWith(boardIds: result);
    await widget.repository.upsertProduct(updated);
    if (mounted) setState(() => products = products.map((p) => p.id == updated.id ? updated : p).toList());
  }

  Future<void> _editProduct(Product product) async {
    final updated = await showModalBottomSheet<Product>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => ProductEditor(product: product, boards: boards, tags: tags, repository: widget.repository));
    if (updated == null) return;
    await widget.repository.upsertProduct(updated);
    if (mounted) setState(() => products = products.map((p) => p.id == updated.id ? updated : p).toList());
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
            ListTile(leading: const Icon(Icons.bug_report_outlined), title: const Text('Диагностика изображений'), onTap: () async { Navigator.pop(context); await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImageDiagnosticsScreen())); }),
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

  void _activateSearch() {
    setState(() {
      searchActive = true;
      searchController.text = query;
      searchController.selection = TextSelection.fromPosition(TextPosition(offset: searchController.text.length));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() {
      searchActive = false;
      query = searchController.text;
    });
    searchFocus.unfocus();
  }

  void _snack(String message) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

  Widget _boardChip(String title, String? id, {bool common = false}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = common ? selectedBoardFilter == _commonBoardFilter : selectedBoardFilter == id;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() {
        selectedBoardFilter = common ? _commonBoardFilter : id;
        selectedSource = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: selected ? scheme.onSurface : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
        child: Text(title, style: TextStyle(color: selected ? scheme.surface : scheme.onSurface, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final items = visible;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        leading: searchActive ? IconButton(tooltip: 'Закрыть поиск', onPressed: _closeSearch, icon: const Icon(Icons.arrow_back_rounded)) : null,
        title: searchActive
            ? TextField(
                controller: searchController,
                focusNode: searchFocus,
                autofocus: true,
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(hintText: 'Найти товар', border: InputBorder.none, suffixIcon: query.isEmpty ? null : IconButton(onPressed: () { searchController.clear(); setState(() => query = ''); }, icon: const Icon(Icons.close_rounded))),
              )
            : const Text('Pinzon', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.4)),
        actions: searchActive
            ? const []
            : [
                IconButton(tooltip: 'Поиск', onPressed: _activateSearch, icon: const Icon(Icons.search_rounded)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'sort', child: Text('Сортировка')),
                    PopupMenuItem(value: 'source', child: Text('Магазин')),
                    PopupMenuItem(value: 'layout', child: Text('Вид списка')),
                    PopupMenuItem(value: 'refresh', child: Text('Обновить цены')),
                    PopupMenuItem(value: 'diagnostics', child: Text('Диагностика изображений')),
                    PopupMenuItem(value: 'settings', child: Text('Настройки')),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'sort': _showSortMenu();
                      case 'source': _showSourceMenu();
                      case 'layout': setState(() => layout = layout == LayoutMode.masonry ? LayoutMode.list : LayoutMode.masonry);
                      case 'refresh': if (!refreshingPrices) _refreshPrices(showSummary: true);
                      case 'diagnostics': Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImageDiagnosticsScreen()));
                      case 'settings': _settings();
                    }
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 7),
              scrollDirection: Axis.horizontal,
              children: [
                _boardChip('Все', null),
                const SizedBox(width: 7),
                _boardChip('Общее', _commonBoardFilter, common: true),
                ...boards.map((board) => Padding(padding: const EdgeInsets.only(left: 7), child: _boardChip(board.name, board.id))),
                Padding(padding: const EdgeInsets.only(left: 7), child: ActionChip(label: const Text('＋ Доска'), onPressed: _createBoard)),
              ],
            ),
          ),
          if (importing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('Добавьте товар через кнопку + или поделитесь ссылкой из магазина.', textAlign: TextAlign.center)))
                : layout == LayoutMode.masonry
                    ? MasonryGridView.count(padding: const EdgeInsets.fromLTRB(14, 8, 14, 90), crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, itemCount: items.length, itemBuilder: (_, i) => ProductCard(product: items[i], onTap: () => _openProduct(items[i]), onLongPress: () => _showProductMenu(items[i])))
                    : ListView.separated(padding: const EdgeInsets.fromLTRB(14, 8, 14, 90), itemCount: items.length, separatorBuilder: (_, index) => const SizedBox(height: 10), itemBuilder: (_, i) => ProductListTile(product: items[i], onTap: () => _openProduct(items[i]), onLongPress: () => _showProductMenu(items[i]))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add_rounded)),
    );
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final url = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 18 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Добавить товар', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(height: 12),
          TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Вставьте ссылку на товар')),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(sheetContext, controller.text.trim()), child: const Text('Продолжить'))),
        ]),
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
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilterChip(label: const Text('Общее'), selected: selectedBoardIds.isEmpty, onSelected: (_) => setState(() => selectedBoardIds = [])),
                ...widget.boards.map((board) => FilterChip(label: Text(board.name), selected: selectedBoardIds.contains(board.id), onSelected: (value) => setState(() => selectedBoardIds = value ? [...selectedBoardIds.where((id) => id != board.id), board.id] : selectedBoardIds.where((id) => id != board.id).toList()))),
              ]),
              const SizedBox(height: 14),
              TextField(decoration: const InputDecoration(labelText: 'Заметка'), maxLines: 4, controller: TextEditingController(text: p.note), onChanged: (v) => p = p.copyWith(note: v)),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => Navigator.pop(context, p.copyWith(boardIds: selectedBoardIds)), child: const Text('Сохранить')),
            ],
          ),
        ),
      );
}
