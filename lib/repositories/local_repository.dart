import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/board.dart';
import '../models/price_point.dart';
import '../models/product.dart';
import '../models/tag.dart';
import 'product_repository.dart';

class LocalRepository implements ProductRepository {
  static const _dbName = 'product_boards.sqlite';
  static const _legacyProductsKey = 'products_v1';
  static const _legacyBoardsKey = 'boards_v1';

  final Uuid _uuid = const Uuid();
  final DatabaseFactory? factory;
  final String? dbPath;
  Database? _db;

  LocalRepository({this.factory, this.dbPath});

  @override
  Future<void> init() async {
    if (factory != null) databaseFactory = factory!;
    final path = dbPath ?? p.join((await getApplicationDocumentsDirectory()).path, _dbName);
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _migrateLegacyPreferences();
    if ((await getBoards()).isEmpty) await _seedBoards();
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
    await db.execute('CREATE TABLE boards (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
    await _createV2Tables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createV2Tables(db);
  }

  /// Таблицы версии 2: вложенные теги, связь товар-тег и история цен.
  /// Заодно переносит плоские теги старой версии (список строк в JSON
  /// товара) в сущность [Tag] и связи [product_tags].
  Future<void> _createV2Tables(Database db) async {
    await db.execute('CREATE TABLE tags (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
    await db.execute('CREATE TABLE product_tags (product_id TEXT NOT NULL, tag_id TEXT NOT NULL, PRIMARY KEY (product_id, tag_id))');
    await db.execute('CREATE TABLE price_history (product_id TEXT NOT NULL, data TEXT NOT NULL)');
    await db.execute('CREATE INDEX idx_price_history_product ON price_history (product_id)');

    final nameToId = <String, String>{};
    final existingTags = await db.query('tags');
    for (final row in existingTags) {
      final tag = Tag.fromJson(jsonDecode(row['data']! as String) as Map<String, dynamic>);
      nameToId[tag.name.toLowerCase()] = tag.id;
    }

    final productRows = await db.query('products');
    for (final row in productRows) {
      final map = Map<String, dynamic>.from(jsonDecode(row['data']! as String) as Map<String, dynamic>);
      final legacy = map['tags'];
      if (legacy is! List || legacy.isEmpty) continue;
      final ids = <String>[];
      for (final raw in legacy) {
        final name = raw.toString().trim();
        if (name.isEmpty) continue;
        var tagId = nameToId[name.toLowerCase()];
        if (tagId == null) {
          tagId = _uuid.v4();
          await db.insert('tags', {'id': tagId, 'data': jsonEncode(Tag(id: tagId, name: name).toJson())});
          nameToId[name.toLowerCase()] = tagId;
        }
        ids.add(tagId);
        await db.insert('product_tags', {'product_id': map['id'], 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      map.remove('tags');
      map['tagIds'] = ids;
      await db.update('products', {'data': jsonEncode(map)}, where: 'id = ?', whereArgs: [map['id']]);
    }
  }

  Database get _database => _db!;

  Future<void> _migrateLegacyPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final marker = await _database.query('settings', where: 'key = ?', whereArgs: ['legacy_migrated']);
    if (marker.isNotEmpty) return;
    final products = prefs.getString(_legacyProductsKey);
    final boards = prefs.getString(_legacyBoardsKey);
    if (products != null) {
      // Переносим и плоские теги (имена строк) старого MVP в сущность Tag.
      final rawList = jsonDecode(products) as List;
      final nameToId = <String, String>{};
      for (final t in await getTags()) { nameToId[t.name.toLowerCase()] = t.id; }
      final newTags = <Tag>[];
      final list = <Product>[];
      for (final e in rawList) {
        final map = Map<String, dynamic>.from(e as Map);
        final legacy = map['tags'];
        final tagIds = <String>[];
        if (legacy is List) {
          for (final raw in legacy) {
            final name = raw.toString().trim();
            if (name.isEmpty) continue;
            var tagId = nameToId[name.toLowerCase()];
            if (tagId == null) {
              tagId = _uuid.v4();
              nameToId[name.toLowerCase()] = tagId;
              newTags.add(Tag(id: tagId, name: name));
            }
            tagIds.add(tagId);
          }
        }
        list.add(Product.fromJson(map).copyWith(tagIds: tagIds));
      }
      if (newTags.isNotEmpty) await saveTags(newTags);
      await saveProducts(list);
    }
    if (boards != null) {
      final list = (jsonDecode(boards) as List).map((e) => Board.fromJson(Map<String, dynamic>.from(e))).toList();
      await saveBoards(list);
    }
    await _database.insert('settings', {'key': 'legacy_migrated', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _seedBoards() async {
    final now = DateTime.now();
    await saveBoards([
      Board(id: newId(), name: 'Хочу купить', createdAt: now, sortOrder: 0),
      Board(id: newId(), name: 'Идеи', createdAt: now, sortOrder: 1),
    ]);
  }

  @override
  Future<List<Product>> getProducts() async {
    final rows = await _database.query('products');
    return rows.map((r) => Product.fromJson(jsonDecode(r['data']! as String) as Map<String, dynamic>)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<Board>> getBoards() async {
    final rows = await _database.query('boards');
    return rows.map((r) => Board.fromJson(jsonDecode(r['data']! as String) as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<void> upsertProduct(Product product) async {
    await _database.transaction((txn) async {
      await txn.insert('products', {'id': product.id, 'data': jsonEncode(product.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('product_tags', where: 'product_id = ?', whereArgs: [product.id]);
      for (final tagId in product.tagIds) {
        await txn.insert('product_tags', {'product_id': product.id, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  @override
  Future<void> deleteProduct(String id) async {
    await _database.transaction((txn) async {
      await txn.delete('products', where: 'id = ?', whereArgs: [id]);
      await txn.delete('product_tags', where: 'product_id = ?', whereArgs: [id]);
      await txn.delete('price_history', where: 'product_id = ?', whereArgs: [id]);
    });
  }

  Future<void> saveProducts(List<Product> products) async {
    await _database.transaction((txn) async {
      for (final product in products) {
        await txn.insert('products', {'id': product.id, 'data': jsonEncode(product.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('product_tags', where: 'product_id = ?', whereArgs: [product.id]);
        for (final tagId in product.tagIds) {
          await txn.insert('product_tags', {'product_id': product.id, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  @override
  Future<void> upsertBoard(Board board) async => _database.insert(
        'boards',
        {'id': board.id, 'data': jsonEncode(board.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> deleteBoard(String id) async => _database.delete('boards', where: 'id = ?', whereArgs: [id]);

  Future<void> saveBoards(List<Board> boards) async {
    await _database.transaction((txn) async {
      for (final board in boards) {
        await txn.insert('boards', {'id': board.id, 'data': jsonEncode(board.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ── Теги (вложенные) ─────────────────────────────────────────────

  @override
  Future<List<Tag>> getTags() async {
    final rows = await _database.query('tags');
    return rows
        .map((r) => Tag.fromJson(jsonDecode(r['data']! as String) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<void> saveTags(List<Tag> tags) async {
    await _database.transaction((txn) async {
      for (final tag in tags) {
        await txn.insert('tags', {'id': tag.id, 'data': jsonEncode(tag.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> deleteTag(String id) async {
    await _database.transaction((txn) async {
      await txn.delete('tags', where: 'id = ?', whereArgs: [id]);
      await txn.delete('product_tags', where: 'tag_id = ?', whereArgs: [id]);
    });
  }

  // ── История цен ──────────────────────────────────────────────────

  @override
  Future<List<PricePoint>> getPriceHistory(String productId) async {
    final rows = await _database.query('price_history', where: 'product_id = ?', whereArgs: [productId]);
    final points = rows
        .map((r) => PricePoint.fromJson(jsonDecode(r['data']! as String) as Map<String, dynamic>))
        .toList();
    points.sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return points;
  }

  @override
  Future<void> recordPrice(Product product, PricePoint point) async {
    final history = await getPriceHistory(product.id);
    final last = history.isEmpty ? null : history.last;
    final unchanged = last != null && last.price == point.price && last.currency == point.currency;
    if (!unchanged) {
      await _database.insert('price_history', {'product_id': product.id, 'data': jsonEncode(point.toJson())});
    }
    // «Снизилась» — если новая цена ниже последней известной (из истории
    // либо из текущего состояния товара, когда истории ещё нет).
    final previousPrice = last?.price ?? product.price;
    final dropped = !unchanged && previousPrice != null && point.price < previousPrice;
    final previousLowest = product.priceLowest;
    final lowest = previousLowest == null || point.price < previousLowest ? point.price : previousLowest;
    await upsertProduct(product.copyWith(
      price: point.price,
      currency: point.currency.isEmpty ? product.currency : point.currency,
      priceLowest: lowest,
      lastCheckedAt: point.observedAt,
      updatedAt: point.observedAt,
      priceDrop: dropped,
    ));
  }

  @override
  Future<Map<String, dynamic>> exportData() async => {
        'schema': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'products': (await getProducts()).map((e) => e.toJson()).toList(),
        'boards': (await getBoards()).map((e) => e.toJson()).toList(),
        'tags': (await getTags()).map((e) => e.toJson()).toList(),
        'price_history': await _exportPriceHistory(),
      };

  Future<List<Map<String, dynamic>>> _exportPriceHistory() async {
    final rows = await _database.query('price_history');
    final grouped = <String, List<PricePoint>>{};
    for (final row in rows) {
      final productId = row['product_id'] as String;
      grouped.putIfAbsent(productId, () => []).add(PricePoint.fromJson(jsonDecode(row['data']! as String) as Map<String, dynamic>));
    }
    return grouped.entries.map((e) => {
      'product_id': e.key,
      'points': e.value.map((p) => p.toJson()).toList(),
    }).toList();
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    final products = (data['products'] as List? ?? const [])
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final boards = (data['boards'] as List? ?? const [])
        .map((e) => Board.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final tags = (data['tags'] as List? ?? const [])
        .map((e) => Tag.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    await _database.transaction((txn) async {
      await txn.delete('products');
      await txn.delete('boards');
      await txn.delete('tags');
      await txn.delete('product_tags');
      await txn.delete('price_history');
      for (final tag in tags) {
        await txn.insert('tags', {'id': tag.id, 'data': jsonEncode(tag.toJson())});
      }
      for (final product in products) {
        await txn.insert('products', {'id': product.id, 'data': jsonEncode(product.toJson())});
        for (final tagId in product.tagIds) {
          await txn.insert('product_tags', {'product_id': product.id, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      for (final board in boards) {
        await txn.insert('boards', {'id': board.id, 'data': jsonEncode(board.toJson())});
      }
    });
    await _importPriceHistory(data['price_history']);
    if ((await getBoards()).isEmpty) await _seedBoards();
  }

  Future<void> _importPriceHistory(Object? raw) async {
    if (raw is! List) return;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final productId = entry['product_id']?.toString();
      final points = entry['points'];
      if (productId == null || points is! List) continue;
      for (final point in points) {
        if (point is! Map) continue;
        await _database.insert('price_history', {
          'product_id': productId,
          'data': jsonEncode(PricePoint.fromJson(Map<String, dynamic>.from(point)).toJson()),
        });
      }
    }
  }

  @override
  String newId() => _uuid.v4();
  @override
  Future<void> close() async => _database.close();
}
