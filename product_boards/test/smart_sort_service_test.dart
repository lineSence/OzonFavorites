import 'package:flutter_test/flutter_test.dart';
import 'package:pinzon/models/archive_item.dart';
import 'package:pinzon/services/product_features.dart';
import 'package:pinzon/services/smart_sort_service.dart';

ArchiveItem item(String title, {String note = '', String url = 'https://example.com', String? imageUrl}) {
  final now = DateTime(2026, 1, 1);
  return ArchiveItem(id: title, url: url, title: title, titleSource: TitleSource.automatic, imageUrl: imageUrl, imageStatus: imageUrl == null ? ImageStatus.failed : ImageStatus.success, note: note, categoryId: null, metadataStatus: MetadataStatus.success, createdAt: now, updatedAt: now);
}

void main() {
  final service = SmartSortService();

  test('classifies Russian clothing', () {
    final result = service.classify(item('Худи оверсайз чёрное'));
    expect(result.category, 'Одежда');
    expect(result.isConfident, isTrue);
    expect(result.matchedKeywords, contains('худи'));
  });

  test('classifies electronics from note', () {
    final result = service.classify(item('Новая вещь', note: 'Беспроводные наушники и зарядка'));
    expect(result.category, 'Электроника');
  });

  test('uses URL text', () {
    final result = service.classify(item('Товар', url: 'https://example.com/product/%D0%BA%D0%BE%D1%84%D0%B5-%D0%B7%D0%B5%D1%80%D0%BD%D0%BE'));
    expect(result.category, 'Продукты');
    expect(result.matchedKeywords, contains('кофе'));
  });

  test('returns other for unrelated text', () {
    final result = service.classify(item('Красивый предмет без описания'));
    expect(result.category, 'Другое');
    expect(result.score, 0);
  });

  test('builds classifier features', () {
    final features = ProductFeatures.fromItem(item('Товар', url: 'https://www.ozon.ru/product/example', imageUrl: 'https://cdn.example/image.jpg'));
    expect(features.source, 'ozon');
    expect(features.hasImage, isTrue);
    expect(features.text, 'Товар');
  });
}
