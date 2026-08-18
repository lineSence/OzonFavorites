import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_boards/models/product.dart';
import 'package:product_boards/widgets/product_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Product product({
    String id = '1',
    String url = 'https://www.ozon.ru/product/1234567/',
    String source = 'OZON',
    String title = 'Наушники',
    double? price = 1990,
    String currency = '₽',
  }) => Product(
        id: id,
        url: url,
        source: source,
        title: title,
        price: price,
        currency: currency,
        createdAt: DateTime.now(),
      );

  testWidgets('ProductCard shows title, price and source', (tester) async {
    await tester.pumpWidget(wrap(ProductCard(product: product(), onTap: () {}, onLongPress: () {})));
    expect(find.text('Наушники'), findsOneWidget);
    expect(find.text('1990 ₽'), findsOneWidget);
    expect(find.text('OZON'), findsOneWidget);
  });

  testWidgets('ProductCard renders price with product currency', (tester) async {
    await tester.pumpWidget(wrap(
      ProductCard(
        product: product(title: 'Куртка', price: 4500, currency: 'USD'),
        onTap: () {},
        onLongPress: () {},
      ),
    ));
    expect(find.text('4500 USD'), findsOneWidget);
  });

  testWidgets('ProductCard shows placeholder and omits price when missing', (tester) async {
    await tester.pumpWidget(wrap(ProductCard(product: product(price: null), onTap: () {}, onLongPress: () {})));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.textContaining('₽'), findsNothing);
  });

  testWidgets('ProductCard calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(ProductCard(product: product(), onTap: () => tapped = true, onLongPress: () {})));
    await tester.tap(find.text('Наушники'));
    expect(tapped, isTrue);
  });
}
