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
    expect(result.score, .58);
    expect(result.isConfident, isTrue);
  });

  test('returns ranked alternatives for ambiguous products', () {
    final result = service.classify(
      _item('Спортивная куртка для бега'),
    );

    expect(result.category, 'Спорт');
    expect(result.alternatives, isNotEmpty);
    expect(result.alternatives.first.category, 'Одежда');
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
