import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/board.dart';
import '../models/product.dart';

class LocalRepository {
  static const _dbName = 'product_boards.sqlite';
  static const _legacyProductsKey = 'products_v1';
  static const _legacyBoardsKey = 'boards_v1';

  final Uuid _uuid = const Uuid();
  Database? _db;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, _dbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
        await db.execute('CREATE TABLE boards (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
      },
    );
    await _migrateLegacyPreferences();
    if ((await getBoards()).isEmpty) await _seedBoards();
  }

  Database get _database => _db!;

  Future<void> _migrateLegacyPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final marker = await _database.query('settings', where: 'key = ?', whereArgs: ['legacy_migrated']);
    if (marker.isNotEmpty) return;
    final products = prefs.getString(_legacyProductsKey);
    final boards = prefs.getString(_legacyBoardsKey);
    if (products != null) {
      final list = (jsonDecode(products) as List).map((e) => Product.fromJson(Map<String, dynamic>.from(e))).toList();
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

  Future<List<Product>> getProducts() async {
    final rows = await _database.query('products');
    return rows.map((r) => Product.fromJson(jsonDecode(r['data']! as String) as Map<String, dynamic>)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Board>> getBoards() async {
    final rows = await _database.query('boards');
    return rows.map((r) => Board.fromJson(jsonDecode(r['data']! as String) as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<void> upsertProduct(Product product) async => _database.insert(
        'products',
        {'id': product.id, 'data': jsonEncode(product.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteProduct(String id) async => _database.delete('products', where: 'id = ?', whereArgs: [id]);

  Future<void> saveProducts(List<Product> products) async {
    await _database.transaction((txn) async {
      for (final product in products) {
        await txn.insert('products', {'id': product.id, 'data': jsonEncode(product.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> upsertBoard(Board board) async => _database.insert(
        'boards',
        {'id': board.id, 'data': jsonEncode(board.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteBoard(String id) async => _database.delete('boards', where: 'id = ?', whereArgs: [id]);

  Future<void> saveBoards(List<Board> boards) async {
    await _database.transaction((txn) async {
      for (final board in boards) {
        await txn.insert('boards', {'id': board.id, 'data': jsonEncode(board.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<Map<String, dynamic>> exportData() async => {
        'schema': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'products': (await getProducts()).map((e) => e.toJson()).toList(),
        'boards': (await getBoards()).map((e) => e.toJson()).toList(),
      };

  Future<void> importData(Map<String, dynamic> data) async {
    final products = (data['products'] as List? ?? const [])
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final boards = (data['boards'] as List? ?? const [])
        .map((e) => Board.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    await _database.transaction((txn) async {
      await txn.delete('products');
      await txn.delete('boards');
      for (final product in products) {
        await txn.insert('products', {'id': product.id, 'data': jsonEncode(product.toJson())});
      }
      for (final board in boards) {
        await txn.insert('boards', {'id': board.id, 'data': jsonEncode(board.toJson())});
      }
    });
    if ((await getBoards()).isEmpty) await _seedBoards();
  }

  String newId() => _uuid.v4();
  Future<void> close() async => _database.close();
}
