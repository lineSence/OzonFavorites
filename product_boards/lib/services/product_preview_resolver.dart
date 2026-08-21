import 'dart:io';

import '../models/product_preview.dart';
import 'image_cache_service.dart';
import 'image_diagnostics.dart';
import 'marketplace_search_resolver.dart';
import 'product_importer.dart';
import 'smart_crop_service.dart';

class ProductPreviewResolver {
  ProductPreviewResolver({ProductImporter? importer, ImageCacheService? imageCache, MarketplaceSearchResolver? searchResolver, SmartCropService? smartCrop})
      : _importer = importer ?? ProductImporter(), _imageCache = imageCache ?? ImageCacheService(), _searchResolver = searchResolver ?? MarketplaceSearchResolver(), _smartCrop = smartCrop ?? SmartCropService();

  final ProductImporter _importer;
  final ImageCacheService _imageCache;
  final MarketplaceSearchResolver _searchResolver;
  final SmartCropService _smartCrop;

  Future<ProductPreview> resolve(Uri uri, {String? sharedTitle, String? sharedImageUri}) async {
    final isOzon = uri.host.toLowerCase().contains('ozon');
    final isOzonShortLink = isOzon && _isOzonShortLink(uri);
    ImageDiagnostics.log('SHARE_INPUT', {'url': uri.toString(), 'source': _siteName(uri), 'sharedTitlePresent': sharedTitle?.trim().isNotEmpty == true, 'sharedTitle': sharedTitle, 'sharedImagePresent': sharedImageUri?.trim().isNotEmpty == true, 'isOzonShortLink': isOzonShortLink, 'imageStrategy': 'screenshot_only'});

    ImportedProductData data = const ImportedProductData();
    try {
      data = await _importer.fetch(uri);
    } catch (error, stackTrace) {
      ImageDiagnostics.failure('RESOLVER_IMPORT', error, url: uri.toString(), stackTrace: stackTrace);
    }

    Uri? resolvedProductUrl = data.resolvedUrl != null ? Uri.tryParse(data.resolvedUrl!) : null;
    if (isOzonShortLink && data.screenshotUri == null && sharedTitle?.trim().isNotEmpty == true) {
      ImageDiagnostics.log('OZON_SEARCH_FALLBACK_START', {'url': uri.toString(), 'title': sharedTitle!.trim()});
      try {
        final candidate = await _searchResolver.findOzonProduct(sharedTitle.trim());
        if (candidate != null) {
          resolvedProductUrl = candidate.url;
          final candidateData = await _importer.fetch(candidate.url);
          data = data.merge(candidateData);
          ImageDiagnostics.log('OZON_SCREENSHOT_RESOLVE_RESULT', {'candidateUrl': candidate.url.toString(), 'screenshotUri': candidateData.screenshotUri, 'success': candidateData.screenshotUri != null});
        } else {
          ImageDiagnostics.log('OZON_SEARCH_NOT_FOUND', {'url': uri.toString(), 'title': sharedTitle.trim()});
        }
      } catch (error, stackTrace) {
        ImageDiagnostics.failure('OZON_SEARCH_FALLBACK', error, url: uri.toString(), stackTrace: stackTrace);
      }
    }

    final title = _chooseTitle(data.title, sharedTitle, uri);
    String? localImage;

    // The product image is deliberately NOT obtained from the marketplace.
    // Ozon/WB/Avito may block image/CDN requests. The only supported source is
    // the rendered WebView screenshot returned by the Android bridge.
    if (data.screenshotUri?.trim().isNotEmpty == true) {
      final screenshotUri = data.screenshotUri!.trim();
      ImageDiagnostics.log('SCREENSHOT_SOURCE_SELECTED', {'url': uri.toString(), 'source': 'webview_screenshot', 'screenshotUri': screenshotUri});
      localImage = await _imageCache.cacheLocalUri(screenshotUri);
      ImageDiagnostics.log('SCREENSHOT_CACHE_RESULT', {'url': uri.toString(), 'screenshotUri': screenshotUri, 'localImage': localImage, 'success': localImage != null});
      if (localImage != null) {
        try {
          final crop = await _smartCrop.process(localImage);
          if (crop != null) {
            ImageDiagnostics.log('SMART_CROP_RESULT', {'version': 2, 'url': uri.toString(), 'changed': crop.changed, 'confidence': crop.confidence, 'left': crop.left, 'top': crop.top, 'right': crop.right, 'bottom': crop.bottom, 'originalPath': crop.originalPath, 'outputPath': crop.outputPath});
            if (crop.changed) localImage = File(crop.outputPath).uri.toString();
          }
        } catch (error, stackTrace) {
          ImageDiagnostics.failure('SMART_CROP_FAILED', error, url: uri.toString(), stackTrace: stackTrace);
        }
      }
    } else {
      ImageDiagnostics.log('SCREENSHOT_MISSING', {'url': uri.toString(), 'reason': 'WebView did not return a usable screenshot', 'imageFallback': 'disabled'});
    }

    ImageDiagnostics.log('PREVIEW_RESULT', {'url': uri.toString(), 'title': title, 'price': data.price, 'image': null, 'localImage': localImage, 'imageSource': localImage != null ? 'webview_screenshot_smart_crop_v2' : null, 'resolvedProductUrl': resolvedProductUrl?.toString()});
    return ProductPreview(url: uri, title: title, description: data.description, imageUrl: null, localImageUri: localImage, price: data.price, currency: data.currency ?? '₽', siteName: _siteName(uri));
  }

  static bool _isOzonShortLink(Uri uri) => uri.host.toLowerCase().contains('ozon') && uri.pathSegments.isNotEmpty && uri.pathSegments.first.toLowerCase() == 't';
  static String _chooseTitle(String? imported, String? sharedTitle, Uri uri) { final candidates = <String>[if (imported?.trim().isNotEmpty == true) imported!.trim(), if (sharedTitle?.trim().isNotEmpty == true) sharedTitle!.trim()]; if (candidates.isEmpty) return _fallbackTitle(uri); candidates.sort((a, b) => _scoreTitle(b).compareTo(_scoreTitle(a))); return candidates.first; }
  static int _scoreTitle(String value) { var score = value.length.clamp(0, 500); if (RegExp(r'[А-Яа-яЁё]').hasMatch(value)) score += 1000; return score; }
  static String _siteName(Uri uri) { final host = uri.host.toLowerCase(); if (host.contains('ozon')) return 'Ozon'; if (host.contains('wildberries')) return 'Wildberries'; if (host.contains('avito')) return 'Avito'; if (host.contains('market.yandex')) return 'Яндекс Маркет'; return uri.host; }
  static String _fallbackTitle(Uri uri) => uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.host;
}
