import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_boards/models/product.dart';
import 'package:product_boards/models/tag.dart';
import 'package:product_boards/screens/product_detail_screen.dart';

void main() {
  testWidgets('Detail screen renders product fields', (tester) async {
    final product = Product(
      id: '1',
      url: 'https://www.ozon.ru/product/1234567/',
      source: 'OZON',
      title: 'Умные часы',
      price: 8900,
      currency: '₽',
      createdAt: DateTime.now(),
      note: 'Сравнить с другим',
      tagIds: const ['tag-1', 'tag-2'],
      quantity: 2,
      comparisonUrl: 'https://example.com/comparison',
      desiredPurchaseDate: DateTime(2026, 12, 31),
    );
    final tags = [
      const Tag(id: 'tag-1', name: 'часы'),
      const Tag(id: 'tag-2', name: 'подарок'),
    ];
    await tester.pumpWidget(MaterialApp(home: ProductDetailScreen(product: product, tags: tags)));
    expect(find.text('Умные часы'), findsOneWidget);
    expect(find.text('8900 ₽'), findsOneWidget);
    expect(find.text('Сравнить с другим'), findsOneWidget);
    expect(find.text('#часы'), findsOneWidget);
    expect(find.text('#подарок'), findsOneWidget);
    expect(find.text('Количество: 2'), findsOneWidget);
    expect(find.text('Открыть в OZON'), findsOneWidget);
  });

  testWidgets('Detail screen shows placeholder when image is missing', (tester) async {
    final product = Product(
      id: '2',
      url: 'https://www.ozon.ru/product/7654321/',
      source: 'OZON',
      title: 'Без картинки',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(MaterialApp(home: ProductDetailScreen(product: product)));
    expect(find.text('Без картинки'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsWidgets);
    expect(find.text('Открыть в OZON'), findsOneWidget);
  });
}
