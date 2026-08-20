import 'dart:io';

import '../models/product_preview.dart';
import 'image_cache_service.dart';
import 'image_diagnostics.dart';
import 'marketplace_search_resolver.dart';
import 'product_importer.dart';

class ProductPreviewResolver {
  ProductPreviewResolver({
    ProductImporter? importer,
    ImageCacheService? imageCache,
    MarketplaceSearchResolver? searchResolver,
  })  : _importer = importer ?? ProductImporter(),
        _imageCache = imageCache ?? ImageCacheService(),
        _searchResolver = searchResolver ?? MarketplaceSearchResolver();

  final ProductImporter _importer;
  final ImageCacheService _imageCache;
  final MarketplaceSearchResolver _searchResolver;

  Future<ProductPreview> resolve(
    Uri uri, {
    String? sharedTitle,
    String? sharedImageUri,
  }) async {
    final isOzon = uri.host.toLowerCase().contains('ozon');
    final isOzonShortLink = isOzon && _isOzonShortLink(uri);

    ImageDiagnostics.log('SHARE_INPUT', {
      'url': uri.toString(),
      'source': _siteName(uri),
      'sharedTitlePresent': sharedTitle?.trim().isNotEmpty == true,
      'sharedTitle': sharedTitle,
      'sharedImagePresent': sharedImageUri?.trim().isNotEmpty == true,
      'sharedImageUri': sharedImageUri,
      'isOzonShortLink': isOzonShortLink,
      'shortLinkCode': isOzonShortLink ? uri.pathSegments.last : null,
    });

    if (isOzonShortLink) {
      ImageDiagnostics.log('OZON_SHORT_LINK', {
        'url': uri.toString(),
        'code': uri.pathSegments.last,
        'strategy': 'http_and_webview_then_title_search_then_shared_intent_fallback',
      });
    }

    ImportedProductData data = const ImportedProductData();
    try {
      data = await _importer.fetch(uri);
    } catch (error, stackTrace) {
      ImageDiagnostics.failure('RESOLVER', error, url: uri.toString(), stackTrace: stackTrace);
    }

    Uri? resolvedProductUrl;
    if (isOzonShortLink && sharedTitle != null && sharedTitle.trim().isNotEmpty && _needsSearchFallback(data)) {
      final candidate = await _searchResolver.findOzonProduct(sharedTitle.trim());
      if (candidate != null) {
        resolvedProductUrl = candidate.url;
        ImageDiagnostics.log('OZON_SEARCH_CANDIDATE', {
          'sourceUrl': uri.toString(),
          'candidateUrl': candidate.url.toString(),
          'candidateTitle': candidate.title,
          'score': candidate.score,
          'engine': candidate.engine,
        });
        try {
          final candidateData = await _importer.fetch(candidate.url);
          data = data.merge(candidateData);
          ImageDiagnostics.log('OZON_SEARCH_RESOLVE_RESULT', {
            'candidateUrl': candidate.url.toString(),
            'title': candidateData.title,
            'price': candidateData.price,
            'image': candidateData.imageUrl,
            'success': candidateData.title != null || candidateData.price != null || candidateData.imageUrl != null,
          });
        } catch (error, stackTrace) {
          ImageDiagnostics.failure('OZON_SEARCH_RESOLVE', error, url: candidate.url.toString(), stackTrace: stackTrace);
        }
      }
    } else if (isOzonShortLink) {
      ImageDiagnostics.log('OZON_SEARCH_SKIPPED', {
        'reason': sharedTitle?.trim().isNotEmpty == true ? 'importer already returned usable product data' : 'share title missing',
        'title': sharedTitle,
      });
    }

    final title = _chooseTitle(data.title, sharedTitle, uri);
    if (sharedTitle != null && sharedTitle.trim().isNotEmpty) {
      ImageDiagnostics.log('SHARED_TITLE', {
        'url': uri.toString(),
        'title': sharedTitle.trim(),
        'selectedTitle': title,
        'importedTitle': data.title,
      });
    }

    String? localImage;
    if (sharedImageUri != null && sharedImageUri.isNotEmpty) {
      final sharedFile = _describeLocalFile(sharedImageUri);
      ImageDiagnostics.log('SHARED_IMAGE_INPUT', {
        'url': uri.toString(),
        'sharedImageUri': sharedImageUri,
        ...sharedFile,
      });
      localImage = await _imageCache.cacheLocalUri(sharedImageUri);
      ImageDiagnostics.log('SHARED_IMAGE_RESULT', {
        'url': uri.toString(),
        'sharedImageUri': sharedImageUri,
        'path': localImage,
        'success': localImage != null,
      });
    } else {
      ImageDiagnostics.log('SHARED_IMAGE_ABSENT', {
        'url': uri.toString(),
        'reason': 'Android Share Intent did not provide a local image URI',
      });
    }

    if (localImage != null) {
      ImageDiagnostics.log('IMAGE_SOURCE_SELECTED', {
        'url': uri.toString(),
        'source': 'android_share_intent',
        'path': localImage,
      });
    } else if (data.imageUrl != null && data.imageUrl!.isNotEmpty) {
      ImageDiagnostics.log('IMAGE_SOURCE_SELECTED', {
        'url': uri.toString(),
        'source': resolvedProductUrl != null ? 'ozon_search' : 'importer',
        'imageUrl': data.imageUrl,
        'resolvedProductUrl': resolvedProductUrl?.toString(),
      });
    }

    localImage ??= await _tryCache(data.imageUrl, uri);

    ImageDiagnostics.log('PREVIEW_RESULT', {
      'url': uri.toString(),
      'title': title,
      'price': data.price,
      'image': data.imageUrl,
      'localImage': localImage,
      'imageSource': sharedImageUri?.isNotEmpty == true && localImage != null
          ? 'android_share_intent'
          : (resolvedProductUrl != null && data.imageUrl != null ? 'ozon_search' : (data.imageUrl != null ? 'importer' : null)),
      'resolvedProductUrl': resolvedProductUrl?.toString(),
      'isOzonShortLink': isOzonShortLink,
    });

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

  static bool _needsSearchFallback(ImportedProductData data) =>
      data.title == null || data.price == null || data.imageUrl == null;

  Future<String?> _tryCache(String? imageUrl, Uri referer) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      ImageDiagnostics.log('IMAGE_URL_MISSING', {
        'url': referer.toString(),
        'reason': 'No usable image URL was returned by HTTP/WebView/search import',
      });
      return null;
    }
    final cached = await _imageCache.cacheUrl(imageUrl, referer: referer);
    ImageDiagnostics.log('IMAGE_URL_CACHE_RESULT', {
      'url': referer.toString(),
      'imageUrl': imageUrl,
      'success': cached != null,
      'localImage': cached,
    });
    return cached;
  }

  static Map<String, Object?> _describeLocalFile(String value) {
    try {
      final uri = Uri.tryParse(value);
      if (uri?.scheme != 'file') {
        return {
          'scheme': uri?.scheme,
          'exists': false,
          'reason': 'shared URI is not file://',
        };
      }
      final file = File(uri!.toFilePath());
      final exists = file.existsSync();
      return {
        'scheme': 'file',
        'path': file.path,
        'exists': exists,
        'bytes': exists ? file.lengthSync() : null,
      };
    } catch (error) {
      return {
        'exists': false,
        'describeError': error.toString(),
      };
    }
  }

  static bool _isOzonShortLink(Uri uri) =>
      uri.host.toLowerCase().contains('ozon') &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first.toLowerCase() == 't';

  static String _chooseTitle(String? imported, String? sharedTitle, Uri uri) {
    final candidates = <String>[
      if (imported?.trim().isNotEmpty == true) imported!.trim(),
      if (sharedTitle?.trim().isNotEmpty == true) sharedTitle!.trim(),
    ];
    if (candidates.isEmpty) return _fallbackTitle(uri);
    candidates.sort((a, b) => _scoreTitle(b).compareTo(_scoreTitle(a)));
    return candidates.first;
  }

  static int _scoreTitle(String value) {
    var score = value.length.clamp(0, 500);
    if (RegExp(r'[А-Яа-яЁё]').hasMatch(value)) score += 1000;
    if (value.toLowerCase().contains('avito')) score -= 100;
    return score;
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
