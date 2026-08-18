import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:product_boards/models/product.dart';
import 'package:product_boards/repositories/local_repository.dart';
import 'package:product_boards/services/price_tracker.dart';
import 'package:product_boards/services/product_importer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  String pageWithPrice(double price) => '''
    <html><head>
      <meta property="og:title" content="Товар" />
      <meta property="product:price:amount" content="${price.toStringAsFixed(0)}" />
      <meta property="product:price:currency" content="RUB" />
    </head></html>
  ''';

  http.Response utf8Response(String body, int statusCode) =>
      http.Response.bytes(utf8.encode(body), statusCode, headers: {'content-type': 'text/html; charset=utf-8'});

  test('updatePrice records a lower price and marks priceDrop', () async {
    final dir = await Directory.systemTemp.createTemp('price_tracker_');
    final repo = LocalRepository(factory: databaseFactoryFfi, dbPath: p.join(dir.path, 'test.sqlite'));
    await repo.init();
    final product = Product(id: 'p1', url: 'https://www.ozon.ru/product/1234567/', source: 'OZON', title: 'Товар', price: 5000, createdAt: DateTime.now());
    await repo.upsertProduct(product);

    final client = MockClient((request) async => utf8Response(pageWithPrice(4500), 200));
    final tracker = PriceTracker(repository: repo, importer: ProductImporter(client: client));
    final result = await tracker.updatePrice(product);
    expect(result.status, PriceUpdateStatus.updated);
    expect(result.newPrice, 4500);

    final updated = (await repo.getProducts()).first;
    expect(updated.price, 4500);
    expect(updated.priceLowest, 4500);
    expect(updated.priceDrop, isTrue);
    expect((await repo.getPriceHistory('p1')).map((h) => h.price), [4500]);
    await repo.close();
    await dir.delete(recursive: true);
  });

  test('updatePrice reports unchanged and failed', () async {
    final dir = await Directory.systemTemp.createTemp('price_tracker_');
    final repo = LocalRepository(factory: databaseFactoryFfi, dbPath: p.join(dir.path, 'test.sqlite'));
    await repo.init();
    final product = Product(id: 'p1', url: 'https://www.ozon.ru/product/1234567/', source: 'OZON', title: 'Товар', price: 5000, createdAt: DateTime.now());
    await repo.upsertProduct(product);

    // Та же цена — unchanged.
    var client = MockClient((request) async => utf8Response(pageWithPrice(5000), 200));
    var tracker = PriceTracker(repository: repo, importer: ProductImporter(client: client));
    expect((await tracker.updatePrice(product)).status, PriceUpdateStatus.unchanged);

    // Сетевая ошибка — failed.
    client = MockClient((request) async => http.Response('denied', 403));
    tracker = PriceTracker(repository: repo, importer: ProductImporter(client: client));
    expect((await tracker.updatePrice(product)).status, PriceUpdateStatus.failed);
    await repo.close();
    await dir.delete(recursive: true);
  });
}
