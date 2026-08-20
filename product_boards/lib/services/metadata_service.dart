import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class MetadataResult {
  const MetadataResult({this.title, this.imageUrl});
  final String? title;
  final String? imageUrl;
}

class MetadataService {
  MetadataService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<MetadataResult> fetch(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent': 'Mozilla/5.0 (Android 14; Mobile) AppleWebKit/537.36 Chrome/131 Safari/537.36',
        'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode >= 500) {
      throw TemporaryMetadataException('HTTP ${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw PermanentMetadataException('HTTP ${response.statusCode}');
    }

    final document = html_parser.parse(response.body);
    String? meta(String key) =>
        document.querySelector('meta[property="$key"]')?.attributes['content'] ??
        document.querySelector('meta[name="$key"]')?.attributes['content'];

    String? title = _clean(
      meta('og:title') ??
          meta('twitter:title') ??
          document.querySelector('[itemprop="name"]')?.attributes['content'] ??
          document.querySelector('title')?.text,
    );
    String? image = _clean(meta('og:image') ?? meta('twitter:image') ?? document.querySelector('[itemprop="image"]')?.attributes['content']);

    for (final node in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(node.text.trim());
        final values = decoded is List ? decoded : [decoded];
        for (final value in values) {
          if (value is! Map) continue;
          final type = '${value['@type'] ?? ''}'.toLowerCase();
          if (type.contains('product') || value.containsKey('name') || value.containsKey('image')) {
            title ??= _string(value['name']);
            image ??= _firstImage(value['image']);
          }
        }
      } catch (_) {
        // A malformed JSON-LD block does not make the whole page unusable.
      }
    }

    if (title == null || image == null) {
      final raw = response.body;
      title ??= _jsonString(raw, 'name');
      image ??= _jsonImage(raw);
    }

    return MetadataResult(
      title: _clean(title),
      imageUrl: _absolute(uri, _clean(image)),
    );
  }

  String? _clean(String? value) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _string(dynamic value) => _clean(value?.toString());

  String? _firstImage(dynamic value) {
    if (value is String) return value;
    if (value is List && value.isNotEmpty) return value.first?.toString();
    if (value is Map) return value['url']?.toString();
    return null;
  }

  String? _absolute(Uri base, String? value) {
    if (value == null) return null;
    final image = Uri.tryParse(value);
    if (image == null) return null;
    return image.hasScheme ? image.toString() : base.resolveUri(image).toString();
  }

  String? _jsonString(String raw, String key) {
    final match = RegExp('"$key"\\s*:\\s*"([^"\\]{3,500})"').firstMatch(raw);
    return match?.group(1);
  }

  String? _jsonImage(String raw) {
    final match = RegExp(r'"(?:image|images)"\s*:\s*(?:\[\s*)?"([^"\\]+\.(?:jpg|jpeg|png|webp)[^"\\]*)', caseSensitive: false).firstMatch(raw);
    return match?.group(1);
  }
}

class TemporaryMetadataException implements Exception {
  TemporaryMetadataException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PermanentMetadataException implements Exception {
  PermanentMetadataException(this.message);
  final String message;
  @override
  String toString() => message;
}
