import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'image_diagnostics.dart';

class ImportedProductData {
  const ImportedProductData({this.title, this.imageUrl, this.price, this.currency, this.description});
  final String? title;
  final String? imageUrl;
  final double? price;
  final String? currency;
  final String? description;

  ImportedProductData merge(ImportedProductData other) => ImportedProductData(
        title: _selectTitle(title, other.title),
        imageUrl: imageUrl ?? other.imageUrl,
        price: price ?? other.price,
        currency: currency ?? other.currency,
        description: description ?? other.description,
      );

  static String? _selectTitle(String? first, String? second) {
    if (first == null || first.trim().isEmpty) return second;
    if (second == null || second.trim().isEmpty) return first;
    final firstScore = _titleScore(first);
    final secondScore = _titleScore(second);
    return secondScore > firstScore ? second : first;
  }

  static int _titleScore(String value) {
    var score = value.trim().length.clamp(0, 500);
    if (RegExp(r'[А-Яа-яЁё]').hasMatch(value)) score += 1000;
    if (RegExp(r'[A-Za-z]').hasMatch(value)) score += 10;
    if (value.contains(' - ')) score += 5;
    if (value.toLowerCase().contains('avito')) score -= 100;
    return score;
  }
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
    ImageDiagnostics.start(uri.toString(), referer: uri.toString());
    ImportedProductData data = const ImportedProductData();
    Object? httpError;
    try {
      data = await _fetchHttp(uri);
      ImageDiagnostics.log('HTTP_RESULT', {
        'url': uri.toString(),
        'title': data.title,
        'price': data.price,
        'image': data.imageUrl,
      });
    } catch (error, stackTrace) {
      httpError = error;
      ImageDiagnostics.failure('IMPORT_HTTP', error, url: uri.toString(), stackTrace: stackTrace);
    }

    if (_enableBrowserFallback && _needsBrowserFallback(uri) &&
        (httpError != null || data.price == null || data.imageUrl == null || data.title == null)) {
      try {
        ImageDiagnostics.log('WEBVIEW_START', {'url': uri.toString()});
        final result = await _browserChannel.invokeMethod<dynamic>('resolveProduct', {'url': uri.toString()});
        if (result is Map) {
          final browserData = ImportedProductData(
            title: _nullableString(result['title']),
            imageUrl: _nullableString(result['imageUrl']),
            price: _nullableDouble(result['price']),
            currency: _nullableString(result['currency']),
            description: _nullableString(result['description']),
          );
          ImageDiagnostics.log('WEBVIEW_RESULT', {
            'url': uri.toString(),
            'title': browserData.title,
            'price': browserData.price,
            'image': browserData.imageUrl,
          });
          data = data.merge(browserData);
          if (browserData.title != null || browserData.imageUrl != null || browserData.price != null || browserData.description != null) {
            httpError = null;
          }
        }
      } on MissingPluginException catch (error, stackTrace) {
        ImageDiagnostics.failure('WEBVIEW_PLUGIN', error, url: uri.toString(), stackTrace: stackTrace);
      } on PlatformException catch (error, stackTrace) {
        ImageDiagnostics.failure('WEBVIEW', error, url: uri.toString(), stackTrace: stackTrace);
      } catch (error, stackTrace) {
        ImageDiagnostics.failure('WEBVIEW_UNKNOWN', error, url: uri.toString(), stackTrace: stackTrace);
      }
    }

    ImageDiagnostics.log('IMPORT_RESULT', {
      'url': uri.toString(),
      'title': data.title,
      'price': data.price,
      'image': data.imageUrl,
    });
    if (httpError != null && data.title == null && data.price == null && data.imageUrl == null) throw httpError;
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

    String? title = _clean(meta('og:title')) ??
        _clean(document.querySelector('meta[name="twitter:title"]')?.attributes['content']) ??
        _clean(document.querySelector('[itemprop="name"]')?.attributes['content']) ??
        _clean(document.querySelector('[data-widget="webProductHeading"] h1')?.text) ??
        _clean(document.querySelector('[data-widget="webProductHeading"]')?.text) ??
        _clean(document.querySelector('h1')?.text) ??
        _clean(document.querySelector('title')?.text);

    String? image = _usableImage(meta('og:image')) ?? _usableImage(meta('twitter:image'));
    String? description = _clean(meta('og:description') ?? meta('twitter:description'));
    double? price = _parsePrice(meta('product:price:amount'));
    String? currency = meta('product:price:currency');

    for (final node in document.querySelectorAll('div[id^="state-webPrice-"]')) {
      final state = _decodeState(node.attributes['data-state']);
      if (state == null) continue;
      final rawPrice = '${state['price'] ?? state['currentPrice'] ?? state['salePrice'] ?? state['finalPrice'] ?? state['discountPrice'] ?? ''}';
      price ??= _parsePrice(rawPrice);
      currency ??= _currencyFromPrice(rawPrice);
      if (price != null) break;
    }

    for (final node in document.querySelectorAll('div[id^="state-webGallery-"]')) {
      final state = _decodeState(node.attributes['data-state']);
      if (state == null) continue;
      final candidate = _firstUsableImage(state['images']) ?? _firstUsableImage(state['items']) ?? _firstUsableImage(state['image']);
      if (candidate != null && !_isGenericImage(candidate, uri)) {
        image ??= candidate;
      }
      if (image != null && !_isGenericImage(image, uri)) break;
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
            title = ImportedProductData._selectTitle(title, _string(map['name']));
            final candidateImage = _firstUsableImage(map['image']);
            if (candidateImage != null && !_isGenericImage(candidateImage, uri)) image = candidateImage;
            description ??= _string(map['description']);
            final offers = map['offers'];
            if (offers is Map) {
              price ??= _parsePrice('${offers['price'] ?? offers['lowPrice'] ?? offers['highPrice'] ?? offers['currentPrice'] ?? ''}');
              currency ??= _string(offers['priceCurrency']);
            } else if (offers is List) {
              for (final offer in offers) {
                if (offer is Map) {
                  price ??= _parsePrice('${offer['price'] ?? offer['lowPrice'] ?? offer['highPrice'] ?? offer['currentPrice'] ?? ''}');
                  currency ??= _string(offer['priceCurrency']);
                  if (price != null) break;
                }
              }
            }
          }
        }
      } catch (_) {
        // Some pages contain invalid JSON-LD; continue with other sources.
      }
    }

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
      } else {
        final match = RegExp(r'"name"\s*:\s*"([^"\\]{3,500})"').firstMatch(inline);
        title = ImportedProductData._selectTitle(title, _jsonUnescape(match?.group(1)));
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
          r'"(?:price|currentPrice|salePrice|finalPrice|discountPrice|oldPrice)"\s*:\s*"?([0-9][0-9\s.,\u00A0\u202F]*)',
          caseSensitive: false,
        ).firstMatch(inline);
        if (match != null) {
          price = _parsePrice(match.group(1));
          currency ??= 'RUB';
        }
      }
      if (title != null && image != null && price != null) break;
    }

    if (price == null) {
      price = _parseVisiblePrice(document, uri);
      if (price != null) currency ??= 'RUB';
    }

    ImageDiagnostics.candidate('http', _absoluteImage(uri, image));
    return ImportedProductData(
      title: _clean(title),
      imageUrl: _absoluteImage(uri, image),
      price: price,
      currency: currency,
      description: _clean(description),
    );
  }

  static double? _parseVisiblePrice(dynamic document, Uri uri) {
    final candidates = <String>[];
    for (final selector in ['[itemprop="price"]', '[class*="price"]', '[data-testid*="price"]']) {
      for (final element in document.querySelectorAll(selector)) {
        final text = _clean(element.text);
        if (text != null && text.length <= 100) candidates.add(text);
      }
      if (candidates.isNotEmpty) break;
    }
    for (final text in candidates) {
      final value = _parsePrice(text);
      if (value != null && value >= 1) return value;
    }
    return null;
  }

  static bool _needsBrowserFallback(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('ozon') ||
        host.contains('wildberries') ||
        host.contains('avito') ||
        host.contains('market.yandex') ||
        host.contains('yandex.ru');
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

  static String? _usableImage(String? value) => value == null || value.trim().isEmpty ? null : value.trim();

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
