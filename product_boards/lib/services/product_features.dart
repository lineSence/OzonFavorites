import '../models/archive_item.dart';

/// Normalized, classifier-friendly representation of an archive item.
///
/// Keeping this separate from [ArchiveItem] lets experimental classifiers use
/// richer signals without coupling the domain model to a particular ML stack.
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

  factory ProductFeatures.fromItem(ArchiveItem item) {
    return ProductFeatures(
      item: item,
      text: '${item.title} ${item.note}'.trim(),
      url: item.url,
      imageUrl: item.imageUrl,
      hasImage: item.imageUrl != null && item.imageUrl!.trim().isNotEmpty,
      source: _sourceFromUrl(item.url),
    );
  }

  static String _sourceFromUrl(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('ozon')) return 'ozon';
    if (normalized.contains('wildberries') || normalized.contains('wb.ru')) {
      return 'wildberries';
    }
    if (normalized.contains('market.yandex') || normalized.contains('yandex')) {
      return 'yandex_market';
    }
    return 'unknown';
  }
}
