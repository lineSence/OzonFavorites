import '../models/product_preview.dart';
import 'image_cache_service.dart';
import 'product_importer.dart';

class ProductPreviewResolver {
  ProductPreviewResolver({ProductImporter? importer, ImageCacheService? imageCache})
      : _importer = importer ?? ProductImporter(),
        _imageCache = imageCache ?? ImageCacheService();

  final ProductImporter _importer;
  final ImageCacheService _imageCache;

  Future<ProductPreview> resolve(
    Uri uri, {
    String? sharedTitle,
    String? sharedImageUri,
  }) async {
    ImportedProductData data = const ImportedProductData();
    try {
      data = await _importer.fetch(uri);
    } catch (_) {
      // A preview can still be created from the shared title/image or URL.
    }

    final title = data.title?.trim().isNotEmpty == true
        ? data.title!.trim()
        : (sharedTitle?.trim().isNotEmpty == true ? sharedTitle!.trim() : _fallbackTitle(uri));

    String? localImage;
    if (sharedImageUri != null && sharedImageUri.isNotEmpty) {
      localImage = await _imageCache.cacheLocalUri(sharedImageUri);
    }
    localImage ??= await _tryCache(data.imageUrl, uri);

    return ProductPreview(
      url: uri,
      title: title,
      description: data.description,
      imageUrl: data.imageUrl,
      localImageUri: localImage,
      price: data.price,
      currency: data.currency ?? '₽',
      siteName: _siteName(uri),
    );
  }

  Future<String?> _tryCache(String? imageUrl, Uri referer) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    return _imageCache.cacheUrl(imageUrl, referer: referer);
  }

  static String _siteName(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.contains('ozon')) return 'Ozon';
    if (host.contains('wildberries')) return 'Wildberries';
    if (host.contains('avito')) return 'Avito';
    if (host.contains('market.yandex')) return 'Яндекс Маркет';
    return uri.host;
  }

  static String _fallbackTitle(Uri uri) => uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.host;
}
