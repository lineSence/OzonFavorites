import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'image_cache_service.dart';
import 'product_preview_resolver.dart';

class MetadataResult {
  const MetadataResult({this.title, this.imageUrl});
  final String? title;
  final String? imageUrl;
}

class MetadataService {
  MetadataService({http.Client? client, ProductPreviewResolver? resolver, ImageCacheService? imageCache})
      : _client = client ?? http.Client(),
        _resolver = resolver ?? ProductPreviewResolver(),
        _imageCache = imageCache ?? ImageCacheService();

  final http.Client _client;
  final ProductPreviewResolver _resolver;
  final ImageCacheService _imageCache;

  Future<MetadataResult> fetch(Uri uri) async {
    String? title;
    String? image;

    try {
      final preview = await _resolver.resolve(uri);
      title = _clean(preview.title);
      image = preview.localImageUri ?? preview.imageUrl;
    } catch (_) {
      // Generic HTTP fallback below remains authoritative for unsupported pages.
    }

    if (title != null && image != null) return MetadataResult(title: title, imageUrl: image);

    final generic = await _fetchGeneric(uri);
    title ??= generic.title;
    image ??= generic.imageUrl;

    if (image != null && !image.startsWith('file:') && !image.startsWith('content:')) {
      image = await _imageCache.cacheUrl(image, referer: uri) ?? image;
    }
    return MetadataResult(title: title, imageUrl: image);
  }

  Future<MetadataResult> _fetchGeneric(Uri uri) async {
    final response = await _client.get(uri, headers: const {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/131 Safari/537.36',
      'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode >= 500) throw TemporaryMetadataException('HTTP ${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 400) throw PermanentMetadataException('HTTP ${response.statusCode}');

    final document = html_parser.parse(response.body);
    String? meta(String key) => document.querySelector('meta[property="$key"]')?.attributes['content'] ?? document.querySelector('meta[name="$key"]')?.attributes['content'];
    String? title = _clean(meta('og:title') ?? meta('twitter:title') ?? document.querySelector('title')?.text);
    String? image = _clean(meta('og:image') ?? meta('twitter:image') ?? document.querySelector('[itemprop="image"]')?.attributes['content']);

    for (final node in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(node.text.trim());
        final values = decoded is List ? decoded : [decoded];
        for (final value in values) {
          if (value is! Map) continue;
          final type = '${value['@type'] ?? ''}'.toLowerCase();
          if (type.contains('product') || value.containsKey('name') || value.containsKey('image')) {
            title ??= _clean(value['name']?.toString());
            image ??= _firstImage(value['image']);
          }
        }
      } catch (_) {}
    }

    if (image != null) {
      final parsed = Uri.tryParse(image);
      if (parsed != null && !parsed.hasScheme) image = uri.resolveUri(parsed).toString();
    }
    return MetadataResult(title: title, imageUrl: image);
  }

  String? _clean(String? value) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _firstImage(dynamic value) {
    if (value is String) return _clean(value);
    if (value is List && value.isNotEmpty) return _clean(value.first?.toString());
    if (value is Map) return _clean(value['url']?.toString());
    return null;
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
