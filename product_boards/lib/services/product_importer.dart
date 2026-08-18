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
  static final _client = http.Client();

  Future<ImportedProductData> fetch(Uri uri) async {
    final response = await _client.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36',
      'Accept-Language': 'ru-RU,ru;q=0.9,en;q=0.7',
      'Accept': 'text/html,application/xhtml+xml',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final document = html_parser.parse(response.body);

    String? meta(String property) => document.querySelector('meta[property="$property"]')?.attributes['content'] ??
        document.querySelector('meta[name="$property"]')?.attributes['content'];

    String? title = meta('og:title') ?? document.querySelector('title')?.text.trim();
    String? image = meta('og:image');
    String? description = meta('og:description');
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
          if (type.contains('product')) {
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

    return ImportedProductData(
      title: _clean(title),
      imageUrl: _absoluteImage(uri, image),
      price: price,
      currency: currency,
      description: _clean(description),
    );
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
