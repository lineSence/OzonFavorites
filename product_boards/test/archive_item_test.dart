import 'package:flutter_test/flutter_test.dart';
import 'package:pinzon/models/archive_item.dart';

defaultItem() => ArchiveItem(
      id: '1',
      url: 'https://example.com/item',
      title: '...',
      titleSource: TitleSource.automatic,
      imageStatus: ImageStatus.loading,
      note: '',
      categoryId: null,
      metadataStatus: MetadataStatus.loading,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('manual title remains manual after clearing', () {
    final item = defaultItem().copyWith(title: 'My title', titleSource: TitleSource.manual);
    final cleared = item.copyWith(title: 'Без названия');
    expect(cleared.titleSource, TitleSource.manual);
  });

  test('category can be removed to return to unassigned', () {
    final item = defaultItem().copyWith(categoryId: 'cat');
    expect(item.copyWith(categoryId: null).categoryId, isNull);
  });
}
