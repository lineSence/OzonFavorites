import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class MetadataResult {
  const MetadataResult({this.title});
  final String? title;
}

/// Metadata is text-only. Product images are exclusively produced by the
/// rendered Android WebView screenshot pipeline.
class MetadataService {
  MetadataService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<MetadataResult> fetch(Uri uri) async {
    try {
      final generic = await _fetchGeneric(uri);
      return generic;
    } catch (_) {
      return const MetadataResult();
    }
  }

  Future<MetadataResult> _fetchGeneric(Uri uri) async {
    final response = await _client.get(uri, headers: const {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/131 Safari/537.36',
      'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode >= 500) throw TemporaryMetadataException('HTTP ${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 400) throw PermanentMetadataException('HTTP ${response.statusCode}');

    final document = html_parser.parse(response.body);
    String? meta(String key) => document.querySelector('meta[property="$key"]')?.attributes['content'] ?? document.querySelector('meta[name="$key"]')?.attributes['content'];
    String? title = _clean(meta('og:title') ?? meta('twitter:title') ?? document.querySelector('title')?.text);

    for (final node in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(node.text.trim());
        final values = decoded is List ? decoded : [decoded];
        for (final value in values) {
          if (value is! Map) continue;
          final type = '${value['@type'] ?? ''}'.toLowerCase();
          if (type.contains('product') || value.containsKey('name')) {
            title ??= _clean(value['name']?.toString());
          }
        }
      } catch (_) {}
    }

    return MetadataResult(title: title);
  }

  String? _clean(String? value) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
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
