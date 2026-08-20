import 'package:flutter_test/flutter_test.dart';

import 'package:pinzon/models/archive_item.dart';
import 'package:pinzon/services/product_features.dart';
import 'package:pinzon/services/smart_sort_service.dart';

ArchiveItem _item(
  String title, {
  String note = '',
  String url = 'https://example.com',
  String? imageUrl,
}) {
  final now = DateTime(2026, 1, 1);
  return ArchiveItem(
    id: title,
    url: url,
    title: title,
    titleSource: TitleSource.automatic,
    imageUrl: imageUrl,
    imageStatus: imageUrl == null ? ImageStatus.failed : ImageStatus.success,
    note: note,
    categoryId: null,
    metadataStatus: MetadataStatus.success,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final service = SmartSortService();

  test('classifies Russian clothing title locally', () {
    final result = service.classify(_item('Худи оверсайз чёрное'));

    expect(result.category, 'Одежда');
    expect(result.isConfident, isTrue);
    expect(result.matchedKeywords, contains('худи'));
  });

  test('classifies electronics using title and note', () {
    final result = service.classify(
      _item('Новая вещь', note: 'Беспроводные наушники и зарядка'),
    );

    expect(result.category, 'Электроника');
    expect(result.score, greaterThanOrEqualTo(.55));
  });

  test('classifies a broad shopping item that was previously Other', () {
    final result = service.classify(
      _item('Скетчбук А5 120 листов для рисования'),
    );

    expect(result.category, 'Канцелярия');
    expect(result.isConfident, isTrue);
  });

  test('uses decoded URL text as a classification signal', () {
    final result = service.classify(
      _item(
        'Товар',
        url: 'https://example.com/product/%D0%BA%D0%BE%D1%84%D0%B5-%D0%B7%D0%B5%D1%80%D0%BD%D0%BE',
      ),
    );

    expect(result.category, 'Продукты');
    expect(result.matchedKeywords, contains('кофе'));
  });

  test('returns other for unrelated text', () {
    final result = service.classify(_item('Красивый предмет без описания'));

    expect(result.category, 'Другое');
    expect(result.score, 0);
    expect(result.isConfident, isFalse);
  });

  test('uses multiple URL tokens as a local classification signal', () {
    final result = service.classify(
      _item('Товар', url: 'https://example.com/minecraft-game'),
    );

    expect(result.category, 'Игры');
    expect(result.score, greaterThan(.40));
  });

  test('uses strong product phrases', () {
    final result = service.classify(
      _item('Новая модель', note: 'Игровая приставка для дома'),
    );

    expect(result.category, 'Электроника');
    expect(result.isConfident, isTrue);
  });

  test('returns ranked alternatives for ambiguous products', () {
    final result = service.classify(
      _item('Спортивная куртка для бега'),
    );

    expect(result.category, 'Одежда');
    expect(result.alternatives, isNotEmpty);
    expect(result.alternatives.first.category, 'Спорт');
    expect(result.needsReview, isTrue);
  });

  test('builds product features with marketplace and image signals', () {
    final features = ProductFeatures.fromItem(
      _item(
        'Товар',
        url: 'https://www.ozon.ru/product/example',
        imageUrl: 'https://cdn.example.com/image.jpg',
      ),
    );

    expect(features.source, 'ozon');
    expect(features.hasImage, isTrue);
    expect(features.text, 'Товар');
  });
}
