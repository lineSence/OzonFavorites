import 'package:flutter_test/flutter_test.dart';

import 'package:pinzon/models/archive_item.dart';

void main() {
  test('manual title survives empty value as manual mode', () {
    final now = DateTime.now();
    final item = ArchiveItem(
      id: '1',
      url: 'https://example.com/item',
      title: 'Custom',
      titleSource: TitleSource.manual,
      imageUrl: null,
      imageStatus: ImageStatus.loading,
      note: '',
      categoryId: null,
      metadataStatus: MetadataStatus.loading,
      createdAt: now,
      updatedAt: now,
    );

    final updated = item.copyWith(title: 'Без названия', titleSource: TitleSource.manual);
    expect(updated.titleSource, TitleSource.manual);
    expect(updated.title, 'Без названия');
  });

  test('category can be removed to return item to unassigned', () {
    final now = DateTime.now();
    final item = ArchiveItem(
      id: '1',
      url: 'https://example.com/item',
      title: 'Item',
      titleSource: TitleSource.automatic,
      imageUrl: 'https://example.com/image.jpg',
      imageStatus: ImageStatus.success,
      note: '',
      categoryId: 'cat',
      metadataStatus: MetadataStatus.success,
      createdAt: now,
      updatedAt: now,
    );
    expect(item.copyWith(categoryId: null).categoryId, isNull);
  });
}
