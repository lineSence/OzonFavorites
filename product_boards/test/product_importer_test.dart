import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:product_boards/services/product_importer.dart';

http.Response utf8Response(String body, int statusCode) =>
    http.Response.bytes(utf8.encode(body), statusCode, headers: {'content-type': 'text/html; charset=utf-8'});

void main() {
  group('ProductImporter', () {
    test('extracts Open Graph metadata and canonicalizes Ozon URLs', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://www.ozon.ru/product/1234567/');
        return utf8Response('''
          <html>
            <head>
              <meta property="og:title" content="Смартфон X" />
              <meta property="og:image" content="https://cdn.example.com/photo.jpg" />
              <meta property="og:description" content="Описание товара" />
              <meta property="product:price:amount" content="12 499" />
              <meta property="product:price:currency" content="RUB" />
            </head>
          </html>
        ''', 200);
      });
      final importer = ProductImporter(client: client);
      final data = await importer.fetch(Uri.parse('https://www.ozon.ru/product/nice-phone-1234567'));
      expect(data.title, 'Смартфон X');
      expect(data.imageUrl, 'https://cdn.example.com/photo.jpg');
      expect(data.price, 12499);
      expect(data.currency, 'RUB');
      expect(data.description, 'Описание товара');
    });

    test('extracts Ozon data from embedded price and gallery state', () async {
      final client = MockClient((request) async {
        return utf8Response('''
          <html>
            <body>
              <div data-widget="webProductHeading"><h1>Кофе в зернах Test</h1></div>
              <div id="state-webPrice-123-default-1" data-state='{"isAvailable":true,"price":"1 799 ₽","originalPrice":"2 399 ₽"}'></div>
              <div id="state-webGallery-123-default-1" data-state='{"images":[{"src":"https://cdn.example.com/coffee.webp","alt":"Кофе"}]}'></div>
            </body>
          </html>
        ''', 200);
      });
      final importer = ProductImporter(client: client);
      final data = await importer.fetch(Uri.parse('https://www.ozon.ru/product/1234567/'));
      expect(data.title, 'Кофе в зернах Test');
      expect(data.price, 1799);
      expect(data.currency, 'RUB');
      expect(data.imageUrl, 'https://cdn.example.com/coffee.webp');
    });

    test('falls back to JSON-LD when OG tags are missing', () async {
      final client = MockClient((request) async {
        return utf8Response('''
          <html>
            <head>
              <script type="application/ld+json">{"@context":"https://schema.org","@type":"Product","name":"Умные часы","image":"https://cdn.example.com/watch.jpg","offers":{"price":"8900.50","priceCurrency":"RUB"}}</script>
            </head>
          </html>
        ''', 200);
      });
      final importer = ProductImporter(client: client);
      final data = await importer.fetch(Uri.parse('https://www.wildberries.ru/catalog/1/detail.aspx'));
      expect(data.title, 'Умные часы');
      expect(data.imageUrl, 'https://cdn.example.com/watch.jpg');
      expect(data.price, 8900.5);
      expect(data.currency, 'RUB');
    });

    test('uses regex fallback for Ozon pages with inline state', () async {
      final client = MockClient((request) async {
        return utf8Response(
          '{\\"name\\":\\"Товар из OZON\\",\\"images\\":[\\"https://cdn.example.com/pic.webp\\"],\\"price\\":\\"4990\\"}',
          200,
        );
      });
      final importer = ProductImporter(client: client);
      final data = await importer.fetch(Uri.parse('https://www.ozon.ru/product/1234567/'));
      expect(data.title, 'Товар из OZON');
      expect(data.imageUrl, 'https://cdn.example.com/pic.webp');
      expect(data.price, 4990);
      expect(data.currency, 'RUB');
    });

    test('does not canonicalize non-Ozon URLs and uses <title>', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/product/abc');
        return utf8Response('<html><head><title>Example Store</title></head></html>', 200);
      });
      final importer = ProductImporter(client: client);
      final data = await importer.fetch(Uri.parse('https://example.com/product/abc'));
      expect(data.title, 'Example Store');
      expect(data.price, isNull);
    });

    test('throws on HTTP error status', () async {
      final client = MockClient((request) async => http.Response('nope', 403));
      final importer = ProductImporter(client: client);
      expect(importer.fetch(Uri.parse('https://example.com/')), throwsException);
    });
  });
}
