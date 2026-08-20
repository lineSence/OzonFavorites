import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'image_diagnostics.dart';

class MarketplaceSearchCandidate {
  const MarketplaceSearchCandidate({
    required this.url,
    required this.title,
    required this.score,
    required this.engine,
  });

  final Uri url;
  final String title;
  final double score;
  final String engine;
}

class MarketplaceSearchResolver {
  MarketplaceSearchResolver({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36';

  Future<MarketplaceSearchCandidate?> findOzonProduct(String title) async {
    final cleanTitle = _clean(title);
    if (cleanTitle.length < 3) return null;

    ImageDiagnostics.log('SEARCH_START', {
      'source': 'ozon',
      'query': cleanTitle,
      'strategies': ['duckduckgo', 'google'],
    });

    final queries = <({String engine, Uri uri})>[
      (
        engine: 'duckduckgo',
        uri: Uri.https('html.duckduckgo.com', '/html/', {
          'q': 'site:ozon.ru/product "$cleanTitle"',
        }),
      ),
      (
        engine: 'google',
        uri: Uri.https('www.google.com', '/search', {
          'q': 'site:ozon.ru/product "$cleanTitle"',
          'num': '10',
          'hl': 'ru',
        }),
      ),
    ];

    for (final query in queries) {
      final candidates = await _search(query.engine, query.uri, cleanTitle);
      if (candidates.isEmpty) {
        ImageDiagnostics.log('SEARCH_EMPTY', {
          'engine': query.engine,
          'queryUrl': query.uri.toString(),
        });
        continue;
      }

      final best = candidates.reduce((a, b) => a.score >= b.score ? a : b);
      ImageDiagnostics.log('SEARCH_CANDIDATES', {
        'engine': query.engine,
        'count': candidates.length,
        'bestUrl': best.url.toString(),
        'bestTitle': best.title,
        'bestScore': best.score,
      });

      if (best.score >= 0.55) {
        ImageDiagnostics.log('SEARCH_SELECTED', {
          'engine': query.engine,
          'url': best.url.toString(),
          'title': best.title,
          'score': best.score,
        });
        return best;
      }
    }

    ImageDiagnostics.log('SEARCH_NOT_CONFIDENT', {'query': cleanTitle});
    return null;
  }

  Future<List<MarketplaceSearchCandidate>> _search(
    String engine,
    Uri queryUrl,
    String wantedTitle,
  ) async {
    try {
      final response = await _client.get(queryUrl, headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      }).timeout(const Duration(seconds: 10));

      ImageDiagnostics.log('SEARCH_RESPONSE', {
        'engine': engine,
        'status': response.statusCode,
        'contentType': response.headers['content-type'],
        'bytes': response.bodyBytes.length,
      });

      if (response.statusCode < 200 || response.statusCode >= 400) return const [];

      final document = html_parser.parse(response.body);
      final results = <MarketplaceSearchCandidate>[];
      final seen = <String>{};

      for (final link in document.querySelectorAll('a[href]')) {
        final href = link.attributes['href'];
        final url = _extractOzonProductUrl(href);
        if (url == null || !seen.add(url.toString())) continue;

        final anchorTitle = _clean(link.text);
        final surrounding = _clean(link.parent?.text);
        final candidateTitle = anchorTitle.isNotEmpty ? anchorTitle : surrounding;
        final score = _titleSimilarity(wantedTitle, candidateTitle);
        results.add(MarketplaceSearchCandidate(
          url: url,
          title: candidateTitle.isEmpty ? url.toString() : candidateTitle,
          score: score,
          engine: engine,
        ));
      }

      results.sort((a, b) => b.score.compareTo(a.score));
      return results.take(10).toList();
    } catch (error, stackTrace) {
      ImageDiagnostics.failure('SEARCH_$engine', error, stackTrace: stackTrace);
      return const [];
    }
  }

  static Uri? _extractOzonProductUrl(String? href) {
    if (href == null || href.isEmpty) return null;

    var value = href.trim();
    if (value.startsWith('//')) value = 'https:$value';

    final direct = Uri.tryParse(value);
    if (direct != null && _isOzonProduct(direct)) return _canonicalProduct(direct);

    final decoded = Uri.decodeFull(value);
    final embedded = RegExp(r'https?://(?:www\.)?ozon\.ru/product/[^\s&<>]+', caseSensitive: false)
        .firstMatch(decoded)
        ?.group(0);
    if (embedded == null) return null;

    final uri = Uri.tryParse(embedded);
    return uri != null && _isOzonProduct(uri) ? _canonicalProduct(uri) : null;
  }

  static bool _isOzonProduct(Uri uri) {
    return (uri.host == 'ozon.ru' || uri.host.endsWith('.ozon.ru')) &&
        uri.path.toLowerCase().contains('/product/');
  }

  static Uri _canonicalProduct(Uri uri) {
    return Uri(
      scheme: 'https',
      host: 'www.ozon.ru',
      pathSegments: uri.pathSegments,
    );
  }

  static double _titleSimilarity(String wanted, String candidate) {
    final a = _tokens(wanted);
    final b = _tokens(candidate);
    if (a.isEmpty || b.isEmpty) return 0;

    final common = a.intersection(b).length;
    final precision = common / b.length;
    final recall = common / a.length;
    final f1 = precision + recall == 0 ? 0 : (2 * precision * recall) / (precision + recall);

    final cyrillicWanted = RegExp(r'[А-Яа-яЁё]').hasMatch(wanted);
    final cyrillicCandidate = RegExp(r'[А-Яа-яЁё]').hasMatch(candidate);
    final languageBonus = cyrillicWanted && cyrillicCandidate ? 0.08 : 0;
    return (f1 + languageBonus).clamp(0, 1).toDouble();
  }

  static Set<String> _tokens(String value) {
    return value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2)
        .toSet();
  }

  static String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
