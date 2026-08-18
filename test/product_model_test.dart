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
      tagIds: const ['tag-1', 'tag-2'],
      boardIds: const ['board-1'],
      status: ProductStatus.considering,
      priority: 2,
      quantity: 3,
      comparisonUrl: 'https://example.com/comparison',
      desiredPurchaseDate: DateTime.utc(2026, 12, 31),
      lastCheckedAt: DateTime.utc(2026, 8, 17, 12),
      priceLowest: 1990,
      priceDrop: true,
    );
    final restored = Product.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.price, 2490);
    expect(restored.tagIds, original.tagIds);
    expect(restored.status, ProductStatus.considering);
    expect(restored.quantity, 3);
    expect(restored.comparisonUrl, 'https://example.com/comparison');
    expect(restored.desiredPurchaseDate, DateTime.utc(2026, 12, 31));
    expect(restored.lastCheckedAt, DateTime.utc(2026, 8, 17, 12));
    expect(restored.priceLowest, 1990);
    expect(restored.priceDrop, true);
  });
}

