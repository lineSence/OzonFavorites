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

    final normalizedTitle = _normalizeTitle(cleanTitle);
    final queries = _buildQueries(cleanTitle, normalizedTitle);

    ImageDiagnostics.log('SEARCH_START', {
      'source': 'ozon',
      'query': cleanTitle,
      'normalizedQuery': normalizedTitle,
      'strategies': queries.map((query) => query.engine).toList(),
    });

    final allCandidates = <MarketplaceSearchCandidate>[];
    final seen = <String>{};

    for (final query in queries) {
      final candidates = await _search(query.engine, query.uri, cleanTitle);
      if (candidates.isEmpty) {
        ImageDiagnostics.log('SEARCH_EMPTY', {
          'engine': query.engine,
          'queryUrl': query.uri.toString(),
        });
        continue;
      }

      for (final candidate in candidates) {
        if (seen.add(candidate.url.toString())) allCandidates.add(candidate);
      }

      final bestForQuery = candidates.reduce((a, b) => a.score >= b.score ? a : b);
      ImageDiagnostics.log('SEARCH_CANDIDATES', {
        'engine': query.engine,
        'count': candidates.length,
        'bestUrl': bestForQuery.url.toString(),
        'bestTitle': bestForQuery.title,
        'bestScore': bestForQuery.score,
      });
    }

    if (allCandidates.isEmpty) {
      ImageDiagnostics.log('SEARCH_NOT_CONFIDENT', {
        'query': cleanTitle,
        'reason': 'no_ozon_urls_found',
      });
      return null;
    }

    allCandidates.sort((a, b) => b.score.compareTo(a.score));
    final best = allCandidates.first;

    ImageDiagnostics.log('SEARCH_AGGREGATED', {
      'count': allCandidates.length,
      'bestUrl': best.url.toString(),
      'bestTitle': best.title,
      'bestScore': best.score,
    });

    if (best.score >= 0.45) {
      ImageDiagnostics.log('SEARCH_SELECTED', {
        'engine': best.engine,
        'url': best.url.toString(),
        'title': best.title,
        'score': best.score,
      });
      return best;
    }

    ImageDiagnostics.log('SEARCH_NOT_CONFIDENT', {
      'query': cleanTitle,
      'bestUrl': best.url.toString(),
      'bestScore': best.score,
      'reason': 'score_below_threshold',
    });
    return null;
  }

  List<({String engine, Uri uri})> _buildQueries(
    String cleanTitle,
    String normalizedTitle,
  ) {
    final tokens = _tokens(normalizedTitle).toList(growable: false);
    final brandToken = _guessBrand(tokens);

    final queries = <({String engine, Uri uri})>[
      (
        engine: 'google_exact',
        uri: Uri.https('www.google.com', '/search', {
          'q': 'site:ozon.ru/product "$cleanTitle"',
          'num': '10',
          'hl': 'ru',
        }),
      ),
      (
        engine: 'google_relaxed',
        uri: Uri.https('www.google.com', '/search', {
          'q': 'site:ozon.ru/product $normalizedTitle',
          'num': '10',
          'hl': 'ru',
        }),
      ),
    ];

    if (brandToken != null) {
      queries.add((
        engine: 'google_brand',
        uri: Uri.https('www.google.com', '/search', {
          'q': 'site:ozon.ru/product $brandToken ${_compactSearchTokens(tokens, exclude: {brandToken})}',
          'num': '10',
          'hl': 'ru',
        }),
      ));
    }

    queries.add((
      engine: 'google_ozon',
      uri: Uri.https('www.google.com', '/search', {
        'q': 'Ozon $normalizedTitle',
        'num': '10',
        'hl': 'ru',
      }),
    ));

    return queries;
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

      for (final node in document.querySelectorAll('a[href]')) {
        final href = node.attributes['href'];
        final url = _extractOzonProductUrl(href);
        if (url == null || !seen.add(url.toString())) continue;

        final anchorTitle = _clean(node.text);
        final surrounding = _clean(node.parent?.text);
        final candidateTitle = anchorTitle.isNotEmpty ? anchorTitle : surrounding;
        final fallbackTitle = candidateTitle.isEmpty ? url.toString() : candidateTitle;
        final score = _titleSimilarity(wantedTitle, fallbackTitle);
        results.add(MarketplaceSearchCandidate(
          url: url,
          title: fallbackTitle,
          score: score,
          engine: engine,
        ));
      }

      final fromHtml = _extractOzonProductUrlsFromText(response.body);
      for (final url in fromHtml) {
        if (!seen.add(url.toString())) continue;
        final score = _titleSimilarity(wantedTitle, url.path);
        results.add(MarketplaceSearchCandidate(
          url: url,
          title: url.path,
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

    final candidates = _extractOzonProductUrlsFromText(value);
    return candidates.isEmpty ? null : candidates.first;
  }

  static List<Uri> _extractOzonProductUrlsFromText(String text) {
    final matches = <Uri>[];
    final seen = <String>{};

    final patterns = <RegExp>[
      RegExp(
        r'https?(?::|%3A)//(?:www\.)?ozon(?:\.ru|%2Eru)/product/[A-Za-z0-9\-_%./~?=&%]+',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:www\.)?ozon(?:\.ru|%2Eru)/product/[A-Za-z0-9\-_%./~?=&%]+',
        caseSensitive: false,
      ),
      RegExp(
        r'\\?/product\\?/[A-Za-z0-9\-_%./~?=&%]+',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        var raw = match.group(0) ?? '';
        raw = _decodeFragmentSafely(raw);
        raw = raw.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
        raw = _stripTrailingDelimiters(raw);
        if (!raw.startsWith('http')) raw = 'https://$raw';

        final uri = Uri.tryParse(raw);
        if (uri == null || !_isOzonProduct(uri)) continue;
        final canonical = _canonicalProduct(uri);
        if (seen.add(canonical.toString())) matches.add(canonical);
      }
    }

    if (matches.isEmpty) {
      final hrefPattern = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
      for (final match in hrefPattern.allMatches(text)) {
        final href = match.group(1);
        if (href == null) continue;
        final candidate = _extractOzonProductUrlFromFragment(href);
        if (candidate != null && seen.add(candidate.toString())) matches.add(candidate);
      }
    }

    return matches;
  }

  static Uri? _extractOzonProductUrlFromFragment(String value) {
    final decoded = _decodeFragmentSafely(value);
    final direct = Uri.tryParse(decoded);
    if (direct != null && _isOzonProduct(direct)) return _canonicalProduct(direct);

    final match = RegExp(
      r'https?://(?:www\.)?ozon\.ru/product/[A-Za-z0-9\-_%./~?=&]+',
      caseSensitive: false,
    ).firstMatch(decoded);
    if (match == null) return null;

    final uri = Uri.tryParse(_stripTrailingDelimiters(match.group(0)!));
    return uri != null && _isOzonProduct(uri) ? _canonicalProduct(uri) : null;
  }

  static String _decodeFragmentSafely(String value) {
    var result = value.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
    for (var i = 0; i < 2; i++) {
      try {
        final decoded = Uri.decodeFull(result);
        if (decoded == result) break;
        result = decoded;
      } on FormatException {
        break;
      }
    }
    return result;
  }

  static String _stripTrailingDelimiters(String value) =>
      value.replaceAll(RegExp(r'''[\\"<>\]\[,;)]+$'''), '');

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
    final a = _tokens(_normalizeTitle(wanted));
    final b = _tokens(_normalizeTitle(candidate));
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

  static String _normalizeTitle(String value) {
    var normalized = value.toLowerCase().replaceAll('ё', 'е');
    normalized = normalized
        .replaceAll(RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:г|гр|грамм|gram|grams)\b'), r'\1g')
        .replaceAll(RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:кг|килограмм|kilogram|kg)\b'), r'\1kg')
        .replaceAll(RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:мл|миллилитр|миллилитров|ml)\b'), r'\1ml')
        .replaceAll(RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:л|литр|литров|l)\b'), r'\1l')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }

  static Set<String> _tokens(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2)
        .toSet();
  }

  static String? _guessBrand(List<String> tokens) {
    for (final token in tokens) {
      if (RegExp(r'^[a-z0-9]{4,}$').hasMatch(token)) return token;
    }
    return null;
  }

  static String _compactSearchTokens(
    List<String> tokens, {
    Set<String> exclude = const {},
  }) {
    final filtered = tokens.where((token) => !exclude.contains(token));
    return filtered.take(6).join(' ');
  }

  static String _clean(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
