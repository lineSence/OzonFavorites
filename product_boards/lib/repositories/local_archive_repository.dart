import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/archive_item.dart';
import '../models/category.dart';
import '../services/url_normalizer.dart';
import 'archive_repository.dart';

class LocalArchiveRepository implements ArchiveRepository {
  static const _dbName = 'product_boards.sqlite';
  static const _version = 3;

  final Uuid _uuid = const Uuid();
  final UrlNormalizer normalizer;
  Database? _db;

  LocalArchiveRepository({UrlNormalizer? normalizer}) : normalizer = normalizer ?? UrlNormalizer();

  @override
  Future<void> init() async {
    final path = p.join((await getApplicationDocumentsDirectory()).path, _dbName);
    _db = await openDatabase(path, version: _version, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('CREATE TABLE archive_items (id TEXT PRIMARY KEY, data TEXT NOT NULL, normalized_url TEXT NOT NULL)');
    await db.execute('CREATE INDEX idx_archive_items_normalized_url ON archive_items(normalized_url)');
    await db.execute('CREATE TABLE categories (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion >= 3) return;
    await _onCreate(db, _version);
    await _migrateLegacy(db);
  }

  Future<void> _migrateLegacy(Database db) async {
    final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final names = rows.map((r) => r['name']?.toString()).toSet();
    if (!names.contains('products')) return;

    final categoryMap = <String, String>{};
    if (names.contains('boards')) {
      for (final row in await db.query('boards')) {
        try {
          final raw = jsonDecode(row['data']! as String) as Map<String, dynamic>;
          final legacyId = raw['id']?.toString();
          final name = raw['name']?.toString().trim();
          if (legacyId == null || name == null || name.isEmpty) continue;
          var category = await _findCategoryByNameIn(db, name);
          if (category == null) {
            final now = DateTime.now();
            category = Category(id: newId(), name: name, createdAt: now, updatedAt: now);
            await db.insert('categories', {'id': category.id, 'data': jsonEncode(category.toJson())});
          }
          categoryMap[legacyId] = category.id;
        } catch (_) {}
      }
    }

    for (final row in await db.query('products')) {
      try {
        final raw = Map<String, dynamic>.from(jsonDecode(row['data']! as String) as Map);
        final id = raw['id']?.toString();
        final url = raw['url']?.toString() ?? '';
        if (id == null || url.isEmpty) continue;
        final boardIds = (raw['boardIds'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
        final categoryId = boardIds.isEmpty ? null : categoryMap[boardIds.first];
        final title = raw['title']?.toString().trim();
        final image = raw['imageUrl']?.toString();
        final now = DateTime.tryParse(raw['updatedAt']?.toString() ?? '') ?? DateTime.now();
        final created = DateTime.tryParse(raw['createdAt']?.toString() ?? '') ?? now;
        final item = ArchiveItem(
          id: id,
          url: url,
          title: title == null || title.isEmpty ? 'Без названия' : title,
          titleSource: TitleSource.manual,
          imageUrl: image,
          imageStatus: image == null || image.isEmpty ? ImageStatus.failed : ImageStatus.success,
          note: raw['note']?.toString() ?? '',
          categoryId: categoryId,
          metadataStatus: MetadataStatus.success,
          createdAt: created,
          updatedAt: now,
        );
        await db.insert('archive_items', {'id': id, 'data': jsonEncode(item.toJson()), 'normalized_url': normalizer.normalize(url)}, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }
  }

  Future<Category?> _findCategoryByNameIn(Database db, String name) async {
    final key = name.trim().toLowerCase();
    final rows = await db.query('categories');
    for (final row in rows) {
      final category = Category.fromJson(jsonDecode(row['data']! as String) as Map<String, dynamic>);
      if (category.name.trim().toLowerCase() == key) return category;
    }
    return null;
  }

  @override
  String newId() => _uuid.v4();

  Database get _database => _db!;

  @override
  Future<List<ArchiveItem>> getItems({String? categoryId}) async {
    final rows = categoryId == null
        ? await _database.query('archive_items', where: "json_extract(data, '\$.categoryId') IS NULL")
        : await _database.query('archive_items', where: "json_extract(data, '\$.categoryId') = ?", whereArgs: [categoryId]);
    final items = rows.map((row) => ArchiveItem.fromJson(jsonDecode(row['data']! as String) as Map<String, dynamic>)).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<ArchiveItem?> getItem(String id) async {
    final rows = await _database.query('archive_items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ArchiveItem.fromJson(jsonDecode(rows.first['data']! as String) as Map<String, dynamic>);
  }

  @override
  Future<List<ArchiveItem>> findByNormalizedUrl(String normalizedUrl) async {
    final rows = await _database.query('archive_items', where: 'normalized_url = ?', whereArgs: [normalizedUrl]);
    return rows.map((row) => ArchiveItem.fromJson(jsonDecode(row['data']! as String) as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> upsertItem(ArchiveItem item) async => _database.insert('archive_items', {'id': item.id, 'data': jsonEncode(item.toJson()), 'normalized_url': normalizer.normalize(item.url)}, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> deleteItem(String id) async => _database.delete('archive_items', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> deleteItems(Iterable<String> ids) async {
    await _database.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('archive_items', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  @override
  Future<void> assignCategory(Iterable<String> ids, String? categoryId) async {
    await _database.transaction((txn) async {
      for (final id in ids) {
        final rows = await txn.query('archive_items', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) continue;
        final item = ArchiveItem.fromJson(jsonDecode(rows.first['data']! as String) as Map<String, dynamic>);
        await txn.update('archive_items', {'data': jsonEncode(item.copyWith(categoryId: categoryId, updatedAt: DateTime.now()).toJson())}, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  @override
  Future<List<Category>> getCategories() async {
    final rows = await _database.query('categories');
    final categories = rows.map((row) => Category.fromJson(jsonDecode(row['data']! as String) as Map<String, dynamic>)).toList();
    categories.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return categories;
  }

  @override
  Future<Category?> getCategory(String id) async {
    final rows = await _database.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Category.fromJson(jsonDecode(rows.first['data']! as String) as Map<String, dynamic>);
  }

  @override
  Future<Category?> findCategoryByName(String name) => _findCategoryByNameIn(_database, name);

  @override
  Future<void> upsertCategory(Category category) async => _database.insert('categories', {'id': category.id, 'data': jsonEncode(category.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> deleteCategory(String id) async {
    await _database.transaction((txn) async {
      final rows = await txn.query('archive_items', columns: ['id', 'data']);
      for (final row in rows) {
        final item = ArchiveItem.fromJson(jsonDecode(row['data']! as String) as Map<String, dynamic>);
        if (item.categoryId == id) {
          await txn.update('archive_items', {'data': jsonEncode(item.copyWith(categoryId: null, updatedAt: DateTime.now()).toJson())}, where: 'id = ?', whereArgs: [item.id]);
        }
      }
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> close() async => _database.close();
}
