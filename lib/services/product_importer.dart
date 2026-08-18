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

    String? meta(String property) => document.querySelector('meta[property="$property"]')?.attributes['content'] ??
        document.querySelector('meta[name="$property"]')?.attributes['content'];

    String? title = meta('og:title') ??
        document.querySelector('meta[name="twitter:title"]')?.attributes['content'] ??
        document.querySelector('[itemprop="name"]')?.attributes['content'] ??
        document.querySelector('title')?.text.trim();
    String? image = meta('og:image') ??
        meta('twitter:image') ??
        document.querySelector('[itemprop="image"]')?.attributes['content'];
    String? description = meta('og:description') ?? meta('twitter:description');
    double? price;
    String? currency = meta('product:price:currency');
    final priceContent = meta('product:price:amount');
    if (priceContent != null) price = _parsePrice(priceContent);

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
        // Some pages contain multiple invalid JSON-LD snippets; continue with OG metadata.
      }
    }

    // Ozon may inline product data without standard OG tags.
    if (title == null || image == null) {
      final raw = response.body;
      if (title == null) {
        final m = RegExp(r'\"name\"\s*:\s*\"([^\"]{3,500})\"').firstMatch(raw);
        title = _jsonUnescape(m?.group(1));
      }
      if (image == null) {
        // Хвост без \ и ", чтобы не захватывать экранирующий backslash
        // перед закрывающей \" в JSON-инлайне Ozon.
        final m = RegExp(r'\"(?:image|images)\"\s*:\s*(?:\[\s*)?\"([^\"]+\.(?:jpg|jpeg|png|webp)[^\"\\]*)', caseSensitive: false).firstMatch(raw);
        image = m?.group(1);
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

  static Uri _canonicalizeOzon(Uri uri) {
    if (!uri.host.toLowerCase().contains('ozon')) return uri;
    final match = RegExp(r'(?<!\d)(\d{7,})(?!\d)').firstMatch(uri.path);
    if (match == null) return uri;
    return Uri.parse('https://www.ozon.ru/product/${match.group(1)}/');
  }

  static String? _jsonUnescape(String? value) {
    if (value == null) return null;
    try { return jsonDecode('"${value.replaceAll('"', '\"')}"') as String; } catch (_) { return value; }
  }

  static String? _string(dynamic value) => value?.toString().trim().isEmpty == true ? null : value?.toString().trim();

  static String? _clean(String? value) => value?.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _firstImage(dynamic value) {
    if (value is String) return value;
    if (value is List && value.isNotEmpty) return value.first?.toString();
    if (value is Map) return value['url']?.toString();
    return null;
  }

  static String? _absoluteImage(Uri base, String? value) {
    if (value == null || value.isEmpty) return null;
    final imageUri = Uri.tryParse(value);
    if (imageUri == null) return null;
    return imageUri.hasScheme ? imageUri.toString() : base.resolveUri(imageUri).toString();
  }

  static double? _parsePrice(String value) {
    final normalized = value.replaceAll(' ', '').replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(normalized);
  }
}
