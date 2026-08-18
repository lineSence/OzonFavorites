import 'package:flutter_test/flutter_test.dart';
import 'package:product_boards/models/product.dart';

void main() {
  test('Product JSON round trip preserves fields', () {
    final original = Product(
      id: '1',
      url: 'https://www.ozon.ru/product/test-1/',
      source: 'OZON',
      title: 'Test product',
      imageUrl: 'https://example.com/image.jpg',
      price: 2490,
      createdAt: DateTime.utc(2026, 8, 17),
      note: 'Сравнить с другим',
      tags: const ['test', 'idea'],
      boardIds: const ['board-1'],
      status: ProductStatus.considering,
      priority: 2,
    );
    final restored = Product.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.price, 2490);
    expect(restored.tags, original.tags);
    expect(restored.status, ProductStatus.considering);
  });
}
