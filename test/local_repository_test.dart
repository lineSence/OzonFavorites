import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:product_boards/models/board.dart';
import 'package:product_boards/models/price_point.dart';
import 'package:product_boards/models/product.dart';
import 'package:product_boards/models/tag.dart';
import 'package:product_boards/repositories/local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<LocalRepository> tempRepo() async {
    final dir = await Directory.systemTemp.createTemp('product_boards_test_');
    return LocalRepository(
      factory: databaseFactoryFfi,
      dbPath: p.join(dir.path, 'test.sqlite'),
    );
  }

  test('upserts and reads products back', () async {
    final repo = await tempRepo();
    await repo.init();
    final product = Product(
      id: 'p1',
      url: 'https://www.ozon.ru/product/1111111/',
      source: 'OZON',
      title: 'Тестовый товар',
      price: 999,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await repo.upsertProduct(product);
    final products = await repo.getProducts();
    expect(products.length, 1);
    expect(products.first.id, 'p1');
    expect(products.first.title, 'Тестовый товар');
    expect(products.first.price, 999);
    await repo.close();
  });

  test('seeds default boards on first init', () async {
    final repo = await tempRepo();
    await repo.init();
    final boards = await repo.getBoards();
    expect(boards.map((b) => b.name), containsAll(['Хочу купить', 'Идеи']));
    await repo.close();
  });

  test('migrates legacy SharedPreferences data', () async {
    SharedPreferences.setMockInitialValues({
      'products_v1': '[{"id":"old","url":"https://a.b/c","source":"OZON","title":"Старый","createdAt":"2026-01-01T00:00:00.000"}]',
      'boards_v1': '[{"id":"b1","name":"Было","createdAt":"2026-01-01T00:00:00.000"}]',
    });
    final repo = await tempRepo();
    await repo.init();
    final products = await repo.getProducts();
    expect(products.length, 1);
    expect(products.first.id, 'old');
    expect(products.first.title, 'Старый');
    final boards = await repo.getBoards();
    expect(boards.any((b) => b.id == 'b1'), isTrue);
    await repo.close();
  });

  test('deleteProduct removes the product', () async {
    final repo = await tempRepo();
    await repo.init();
    final product = Product(id: 'p1', url: 'https://a.b/1', source: 'OZON', title: 'T', createdAt: DateTime.now());
    await repo.upsertProduct(product);
    await repo.deleteProduct('p1');
    expect(await repo.getProducts(), isEmpty);
    await repo.close();
  });

  test('importData replaces existing data', () async {
    final repo = await tempRepo();
    await repo.init();
    await repo.upsertProduct(Product(id: 'old', url: 'https://a.b/1', source: 'OZON', title: 'Удалить', createdAt: DateTime.now()));
    await repo.importData({
      'products': [
        Product(id: 'new', url: 'https://a.b/2', source: 'OZON', title: 'Новый', createdAt: DateTime.now()).toJson(),
      ],
      'boards': [
        Board(id: 'nb', name: 'Новая доска', createdAt: DateTime.now()).toJson(),
      ],
    });
    final products = await repo.getProducts();
    expect(products.map((p) => p.id), ['new']);
    final boards = await repo.getBoards();
    expect(boards.map((b) => b.id), contains('nb'));
    await repo.close();
  });

  test('saves tags and links them to products', () async {
    final repo = await tempRepo();
    await repo.init();
    final parent = Tag(id: 't1', name: 'Электроника');
    final child = Tag(id: 't2', name: 'Наушники', parentId: parent.id);
    await repo.saveTags([parent, child]);
    final product = Product(id: 'p1', url: 'https://a.b/1', source: 'OZON', title: 'T', createdAt: DateTime.now(), tagIds: const ['t1', 't2']);
    await repo.upsertProduct(product);
    final tags = await repo.getTags();
    expect(tags.map((t) => t.name), containsAll(['Электроника', 'Наушники']));
    expect(tags.firstWhere((t) => t.id == 't2').parentId, 't1');
    final restored = (await repo.getProducts()).first;
    expect(restored.tagIds, ['t1', 't2']);
    await repo.deleteTag('t2');
    expect((await repo.getTags()).map((t) => t.id), isNot(contains('t2')));
    await repo.close();
  });

  test('records price history and tracks the lowest price', () async {
    final repo = await tempRepo();
    await repo.init();
    final product = Product(id: 'p1', url: 'https://a.b/1', source: 'OZON', title: 'T', price: 5000, createdAt: DateTime.now());
    await repo.upsertProduct(product);
    await repo.recordPrice(product, PricePoint(price: 4500, currency: '₽', observedAt: DateTime.utc(2026, 1, 2)));
    await repo.recordPrice(product, PricePoint(price: 4200, currency: '₽', observedAt: DateTime.utc(2026, 1, 3)));
    // Повтор той же цены не плодит точки.
    await repo.recordPrice(product, PricePoint(price: 4200, currency: '₽', observedAt: DateTime.utc(2026, 1, 4)));
    final history = await repo.getPriceHistory('p1');
    expect(history.length, 2);
    expect(history.map((h) => h.price), [4500, 4200]);
    final updated = (await repo.getProducts()).first;
    expect(updated.price, 4200);
    expect(updated.priceLowest, 4200);
    expect(updated.lastCheckedAt, DateTime.utc(2026, 1, 4));
    // Рост цены не меняет минимум (передаём актуальное состояние товара).
    final latest = (await repo.getProducts()).first;
    await repo.recordPrice(latest, PricePoint(price: 4800, currency: '₽', observedAt: DateTime.utc(2026, 1, 5)));
    expect((await repo.getProducts()).first.priceLowest, 4200);
    await repo.close();
  });

  test('export and import round-trips tags and price history', () async {
    final repo = await tempRepo();
    await repo.init();
    final tag = Tag(id: 't1', name: 'Подарок');
    await repo.saveTags([tag]);
    final product = Product(id: 'p1', url: 'https://a.b/1', source: 'OZON', title: 'T', createdAt: DateTime.now(), tagIds: const ['t1']);
    await repo.upsertProduct(product);
    await repo.recordPrice(product, PricePoint(price: 1000, currency: '₽', observedAt: DateTime.utc(2026, 2, 1)));
    final exported = await repo.exportData();

    final repo2 = await tempRepo();
    await repo2.init();
    await repo2.importData(exported);
    expect((await repo2.getTags()).map((t) => t.name), ['Подарок']);
    expect((await repo2.getProducts()).first.tagIds, ['t1']);
    expect((await repo2.getPriceHistory('p1')).map((h) => h.price), [1000]);
    await repo.close();
    await repo2.close();
  });

  test('upgrades v1 database and migrates legacy flat tags', () async {
    final dir = await Directory.systemTemp.createTemp('product_boards_migrate_');
    final path = p.join(dir.path, 'test.sqlite');
    final factory = databaseFactoryFfi;

    // Создаём БД «как это делала старая версия» (схема v1 + JSON с 'tags').
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
          await db.execute('CREATE TABLE boards (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
        },
      ),
    );
    await db.insert('products', {
      'id': 'legacy',
      'data': jsonEncode({
        'id': 'legacy',
        'url': 'https://a.b/1',
        'source': 'OZON',
        'title': 'Старый',
        'createdAt': '2026-01-01T00:00:00.000',
        'tags': ['Подарок', 'Техника'],
      }),
    });
    await db.close();

    // Открытие репозиторием запускает миграцию v1 → v2.
    final repo = LocalRepository(factory: factory, dbPath: path);
    await repo.init();
    final tags = await repo.getTags();
    expect(tags.map((t) => t.name), containsAll(['Подарок', 'Техника']));
    final product = (await repo.getProducts()).first;
    expect(product.tagIds, isNotEmpty);
    await repo.close();
    await dir.delete(recursive: true);
  });
}
