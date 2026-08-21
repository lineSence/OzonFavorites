import '../models/archive_item.dart';

class ProductFeatures {
  const ProductFeatures({
    required this.item,
    required this.text,
    required this.url,
    required this.imageUrl,
    required this.hasImage,
    required this.source,
  });

  final ArchiveItem item;
  final String text;
  final String url;
  final String? imageUrl;
  final bool hasImage;
  final String source;

  factory ProductFeatures.fromItem(ArchiveItem item) => ProductFeatures(
        item: item,
        text: '${item.title} ${item.note}'.trim(),
        url: item.url,
        imageUrl: item.imageUrl,
        hasImage: item.imageUrl?.trim().isNotEmpty == true,
        source: _sourceFromUrl(item.url),
      );

  static String _sourceFromUrl(String value) {
    final url = value.toLowerCase();
    if (url.contains('ozon')) return 'ozon';
    if (url.contains('wildberries') || url.contains('wb.ru')) return 'wildberries';
    if (url.contains('market.yandex') || url.contains('yandex')) return 'yandex_market';
    return 'unknown';
  }
}
