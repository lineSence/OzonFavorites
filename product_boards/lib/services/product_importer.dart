import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class ImportedProductData {
  const ImportedProductData({this.title, this.imageUrl, this.price, this.currency, this.description});
  final String? title;
  final String? imageUrl;
  final double? price;
  final String? currency;
  final String? description;
}

class ProductImporter {
  ProductImporter({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<ImportedProductData> fetch(Uri uri) async {
    final response = await _client.get(_canonicalizeOzon(uri), headers: {
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

    String? image = meta('og:image') ??
        meta('twitter:image') ??
        document.querySelector('[itemprop="image"]')?.attributes['content'];

    String? description = meta('og:description') ?? meta('twitter:description');
    double? price = _parsePrice(meta('product:price:amount'));
    String? currency = meta('product:price:currency');

    final priceStates = document.querySelectorAll('div[id^="state-webPrice-"]');
    for (final node in priceStates) {
      final state = _decodeState(node.attributes['data-state']);
      if (state == null) continue;
      final rawPrice = '${state['price'] ?? state['currentPrice'] ?? state['salePrice'] ?? ''}';
      price ??= _parsePrice(rawPrice);
      currency ??= _currencyFromPrice(rawPrice);
      if (price != null) break;
    }

    final galleryStates = document.querySelectorAll('div[id^="state-webGallery-"]');
    for (final node in galleryStates) {
      final state = _decodeState(node.attributes['data-state']);
      if (state == null) continue;
      image ??= _firstImage(state['images']);
      image ??= _firstImage(state['items']);
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
            image ??= _firstImage(map['image']);
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

    final raw = response.body;
    if (title == null || image == null || price == null) {
      if (title == null) {
        final match = RegExp(r'"name"\s*:\s*"([^"\\]{3,500})"').firstMatch(raw);
        title = _jsonUnescape(match?.group(1));
      }
      if (image == null) {
        final match = RegExp(
          r'"(?:image|images)"\s*:\s*(?:\[\s*)?"(https?[^"\\]+\.(?:jpg|jpeg|png|webp)(?:\?[^"\\]*)?)',
          caseSensitive: false,
        ).firstMatch(raw);
        image = match?.group(1);
      }
      if (price == null) {
        final match = RegExp(
          r'"(?:price|currentPrice|salePrice)"\s*:\s*"?([0-9][0-9\s.,\u00A0\u202F]*)',
          caseSensitive: false,
        ).firstMatch(raw);
        if (match != null) {
          price = _parsePrice(match.group(1));
          currency ??= 'RUB';
        }
      }
    }

    return ImportedProductData(
      title: _clean(title),
      imageUrl: _absoluteImage(uri, image),
      price: price,
      currency: currency,
      description: _clean(description),
    );
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

  static Uri _canonicalizeOzon(Uri uri) {
    if (!uri.host.toLowerCase().contains('ozon')) return uri;
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

  static String? _firstImage(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is List) {
      for (final item in value) {
        final image = _firstImage(item);
        if (image != null) return image;
      }
    }
    if (value is Map) {
      return _string(value['src']) ?? _string(value['url']) ?? _string(value['image']);
    }
    return null;
  }

  static String? _absoluteImage(Uri base, String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.replaceAll('\\u002F', '/').replaceAll(r'\/', '/');
    final imageUri = Uri.tryParse(normalized);
    if (imageUri == null) return null;
    return imageUri.hasScheme ? imageUri.toString() : base.resolveUri(imageUri).toString();
  }

  static double? _parsePrice(String? value) {
    if (value == null) return null;
    final normalized = value
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
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
