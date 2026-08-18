import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class ImportedProductData {
  const ImportedProductData({this.title, this.imageUrl, this.price, this.currency, this.description});
  final String? title;
  final String? imageUrl;
  final double? price;
  final String? currency;
  final String? description;

  ImportedProductData merge(ImportedProductData other) => ImportedProductData(
        title: title ?? other.title,
        imageUrl: imageUrl ?? other.imageUrl,
        price: price ?? other.price,
        currency: currency ?? other.currency,
        description: description ?? other.description,
      );
}

class ProductImporter {
  ProductImporter({
    http.Client? client,
    MethodChannel? browserChannel,
    bool enableBrowserFallback = true,
  })  : _client = client ?? http.Client(),
        _browserChannel = browserChannel ?? const MethodChannel('product_boards/share'),
        _enableBrowserFallback = enableBrowserFallback;

  final http.Client _client;
  final MethodChannel _browserChannel;
  final bool _enableBrowserFallback;

  Future<ImportedProductData> fetch(Uri uri) async {
    ImportedProductData data = const ImportedProductData();
    Object? httpError;
    try {
      data = await _fetchHttp(uri);
    } catch (error) {
      httpError = error;
    }

    if (_enableBrowserFallback && _needsBrowserFallback(uri) &&
        (httpError != null || data.price == null || data.imageUrl == null || data.title == null)) {
      try {
        final result = await _browserChannel.invokeMethod<dynamic>('resolveProduct', {'url': uri.toString()});
        if (result is Map) {
          final browserData = ImportedProductData(
            title: _nullableString(result['title']),
            imageUrl: _nullableString(result['imageUrl']),
            price: _nullableDouble(result['price']),
            currency: _nullableString(result['currency']),
            description: _nullableString(result['description']),
          );
          data = data.merge(browserData);
          if (data.title != null || data.imageUrl != null || data.price != null || data.description != null) {
            httpError = null;
          }
        }
      } on MissingPluginException {
        // Browser fallback is Android-specific.
      } on PlatformException {
        // A browser failure must never prevent basic import from working.
      }
    }

    if (httpError != null) throw httpError;
    return data;
  }

  Future<ImportedProductData> _fetchHttp(Uri uri) async {
    final response = await _client.get(_canonicalizeMarketplace(uri), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
      'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final document = html_parser.parse(response.body);
    String? meta(String property) =>
        document.querySelector('meta[property="$property"]')?.attributes['content'] ??
        document.querySelector('meta[name="$property"]')?.attributes['content'];

    String? title = meta('og:title') ??
        document.querySelector('meta[name="twitter:title"]')?.attributes['content'] ??
        document.querySelector('[itemprop="name"]')?.attributes['content'] ??
        document.querySelector('[data-widget="webProductHeading"] h1')?.text.trim() ??
        document.querySelector('[data-widget="webProductHeading"]')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        document.querySelector('title')?.text.trim();
    String? image = _usableImage(meta('og:image')) ?? _usableImage(meta('twitter:image'));
    String? description = meta('og:description') ?? meta('twitter:description');
    double? price = _parsePrice(meta('product:price:amount'));
    String? currency = meta('product:price:currency');

    for (final node in document.querySelectorAll('div[id^="state-webPrice-"]')) {
      final state = _decodeState(node.attributes['data-state']);
      if (state == null) continue;
      final rawPrice = '${state['price'] ?? state['currentPrice'] ?? state['salePrice'] ?? ''}';
      price ??= _parsePrice(rawPrice);
      currency ??= _currencyFromPrice(rawPrice);
      if (price != null) break;
    }

    for (final node in document.querySelectorAll('div[id^="state-webGallery-"]')) {
      final state = _decodeState(node.attributes['data-state']);
      if (state == null) continue;
      final candidate = _firstUsableImage(state['images']) ?? _firstUsableImage(state['items']);
      if (candidate != null) image = candidate;
      if (image != null) break;
    }

    for (final node in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(node.text.trim());
        final candidates = decoded is List ? decoded : [decoded];
        for (final candidate in candidates) {
          if (candidate is! Map) continue;
          final map = Map<String, dynamic>.from(candidate);
          final type = '${map['@type'] ?? ''}'.toLowerCase();
          if (type.contains('product') || map.containsKey('name') || map.containsKey('image')) {
            title = _string(map['name']) ?? title;
            final candidateImage = _firstUsableImage(map['image']);
            if (candidateImage != null) image = candidateImage;
            description ??= _string(map['description']);
            final offers = map['offers'];
            if (offers is Map) {
              price ??= _parsePrice('${offers['price'] ?? ''}');
              currency ??= _string(offers['priceCurrency']);
            }
          }
        }
      } catch (_) {
        // Some pages contain invalid JSON-LD; continue with other sources.
      }
    }

    // Avito and other marketplaces can put a generic site image into OG tags.
    // Search regular image attributes before falling back to that generic image.
    if (image == null || _isGenericImage(image, uri)) {
      final selectors = <String>[
        '[itemprop="image"]',
        '[class*="gallery"] img',
        '[class*="photo"] img',
        '[class*="image"] img',
        'picture img',
        'img',
      ];
      for (final selector in selectors) {
        for (final element in document.querySelectorAll(selector)) {
          final candidate = _imageFromElement(element);
          if (candidate != null && !_isGenericImage(candidate, uri)) {
            image = candidate;
            break;
          }
        }
        if (image != null && !_isGenericImage(image, uri)) break;
      }
    }

    final normalizedRaw = response.body.replaceAll(RegExp(r'\\+"'), '"');
    final inlineCandidates = <String>[response.body, normalizedRaw];
    for (final inline in inlineCandidates) {
      if (title == null) {
        final match = RegExp(r'"name"\s*:\s*"([^"\\]{3,500})"').firstMatch(inline);
        title = _jsonUnescape(match?.group(1));
      }
      if (image == null || _isGenericImage(image, uri)) {
        final matches = RegExp(
          r'"(?:image|images)"\s*:\s*(?:\[\s*)?"(https?[^"\\]+(?:\.(?:jpg|jpeg|png|webp)|(?:\?|$))[^"\\]*)',
          caseSensitive: false,
        ).allMatches(inline);
        for (final match in matches) {
          final candidate = _usableImage(match.group(1));
          if (candidate != null && !_isGenericImage(candidate, uri)) {
            image = candidate;
            break;
          }
        }
      }
      if (price == null) {
        final match = RegExp(
          r'"(?:price|currentPrice|salePrice)"\s*:\s*"?([0-9][0-9\s.,\u00A0\u202F]*)',
          caseSensitive: false,
        ).firstMatch(inline);
        if (match != null) {
          price = _parsePrice(match.group(1));
          currency ??= 'RUB';
        }
      }
      if (title != null && image != null && price != null) break;
    }

    return ImportedProductData(
      title: _clean(title),
      imageUrl: _absoluteImage(uri, image),
      price: price,
      currency: currency,
      description: _clean(description),
    );
  }

  static bool _needsBrowserFallback(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('ozon') || host.contains('wildberries');
  }

  static String? _nullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  static double? _nullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  static Map<String, dynamic>? _decodeState(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      try {
        final decoded = jsonDecode(_htmlUnescape(raw));
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    }
  }

  static String _htmlUnescape(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static Uri _canonicalizeMarketplace(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!host.contains('ozon')) return uri;
    final match = RegExp(r'(?<!\d)(\d{7,})(?!\d)').firstMatch(uri.path);
    if (match == null) return uri;
    return Uri.parse('https://www.ozon.ru/product/${match.group(1)}/');
  }

  static String? _jsonUnescape(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    try {
      return jsonDecode('"${normalized.replaceAll('"', r'\"')}"') as String;
    } catch (_) {
      return normalized;
    }
  }

  static String? _string(dynamic value) => value?.toString().trim().isEmpty == true ? null : value?.toString().trim();
  static String? _clean(String? value) => value?.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _usableImage(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static String? _firstUsableImage(dynamic value) {
    if (value is String && value.isNotEmpty) return _usableImage(value);
    if (value is List) {
      for (final item in value) {
        final image = _firstUsableImage(item);
        if (image != null) return image;
      }
    }
    if (value is Map) {
      return _usableImage(_string(value['src']) ?? _string(value['url']) ?? _string(value['image']));
    }
    return null;
  }

  static String? _imageFromElement(dynamic element) {
    if (element == null) return null;
    for (final key in ['src', 'data-src', 'data-original', 'data-lazy-src', 'content']) {
      final value = element.attributes[key];
      final candidate = _usableImage(value);
      if (candidate != null) return candidate;
    }
    return null;
  }

  static bool _isGenericImage(String? value, Uri pageUri) {
    if (value == null || value.isEmpty) return true;
    final lower = value.toLowerCase();
    if (lower.contains('logo') || lower.contains('favicon') || lower.contains('sprite') || lower.contains('avatar') || lower.contains('placeholder')) return true;
    if (pageUri.host.toLowerCase().contains('avito')) {
      if (lower.contains('avito.ru') && (lower.contains('/logo') || lower.contains('logo.') || lower.contains('brand'))) return true;
      if (lower.contains('avito.st') && (lower.contains('/logo') || lower.contains('logo.'))) return true;
    }
    return false;
  }

  static String? _absoluteImage(Uri base, String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.replaceAll(r'\u002F', '/').replaceAll(r'\/', '/');
    final imageUri = Uri.tryParse(normalized);
    if (imageUri == null) return null;
    return imageUri.hasScheme ? imageUri.toString() : base.resolveUri(imageUri).toString();
  }

  static double? _parsePrice(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll('\u00A0', '').replaceAll('\u202F', '').replaceAll(' ', '').replaceAll(',', '.');
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(normalized);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  static String? _currencyFromPrice(String value) {
    if (value.contains('₽') || value.toLowerCase().contains('rub')) return 'RUB';
    if (value.contains('\$') || value.toLowerCase().contains('usd')) return 'USD';
    if (value.contains('€') || value.toLowerCase().contains('eur')) return 'EUR';
    return null;
  }
}
