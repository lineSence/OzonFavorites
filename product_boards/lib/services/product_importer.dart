import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'image_diagnostics.dart';

class ImportedProductData {
  const ImportedProductData({
    this.title,
    this.screenshotUri,
    this.price,
    this.currency,
    this.description,
    this.resolvedUrl,
  });

  final String? title;
  final String? screenshotUri;
  final double? price;
  final String? currency;
  final String? description;
  final String? resolvedUrl;

  ImportedProductData merge(ImportedProductData other) => ImportedProductData(
        title: _selectTitle(title, other.title),
        screenshotUri: screenshotUri ?? other.screenshotUri,
        price: price ?? other.price,
        currency: currency ?? other.currency,
        description: description ?? other.description,
        resolvedUrl: other.resolvedUrl ?? resolvedUrl,
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
      data = await _fetchMetadata(uri);
      ImageDiagnostics.log('HTTP_RESULT', {
        'url': uri.toString(),
        'title': data.title,
        'price': data.price,
        'image': null,
        'resolvedUrl': data.resolvedUrl,
      });
    } catch (error, stackTrace) {
      httpError = error;
      ImageDiagnostics.failure('IMPORT_HTTP', error, url: uri.toString(), stackTrace: stackTrace);
    }

    if (_enableBrowserFallback && _needsBrowser(uri)) {
      try {
        ImageDiagnostics.log('WEBVIEW_START', {'url': uri.toString(), 'mode': 'screenshot'});
        final result = await _browserChannel.invokeMethod<dynamic>('resolveProduct', {
          'url': uri.toString(),
        });

        if (result is Map) {
          final rawDiagnostics = result['diagnostics'];
          if (rawDiagnostics is Iterable) {
            for (final rawEvent in rawDiagnostics) {
              if (rawEvent is Map) {
                final eventData = <String, Object?>{};
                rawEvent.forEach((key, value) => eventData[key.toString()] = value);
                final stage = eventData.remove('stage')?.toString() ?? 'UNKNOWN';
                ImageDiagnostics.log('WEBVIEW_EVENT', {'stage': stage, ...eventData});
              }
            }
          }

          final browserData = ImportedProductData(
            title: _nullableString(result['title']),
            screenshotUri: _nullableString(result['screenshotUri']),
            price: _nullableDouble(result['price']),
            currency: _nullableString(result['currency']),
            description: _nullableString(result['description']),
            resolvedUrl: _nullableString(result['finalUrl']),
          );

          ImageDiagnostics.log('WEBVIEW_RESULT', {
            'url': uri.toString(),
            'originalUrl': _nullableString(result['originalUrl']),
            'finalUrl': browserData.resolvedUrl,
            'pageTitle': _nullableString(result['pageTitle']),
            'title': browserData.title,
            'price': browserData.price,
            'currency': browserData.currency,
            'screenshotUri': browserData.screenshotUri,
            'reason': _nullableString(result['reason']),
            'attempts': result['attempts'],
          });

          data = data.merge(browserData);
          if (browserData.title != null || browserData.price != null || browserData.screenshotUri != null) {
            httpError = null;
          }
        } else {
          ImageDiagnostics.failure(
            'WEBVIEW_EMPTY_RESULT',
            Exception('WebView returned ${result.runtimeType}'),
            url: uri.toString(),
          );
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
      'image': null,
      'screenshotUri': data.screenshotUri,
      'resolvedUrl': data.resolvedUrl,
    });

    if (httpError != null && data.title == null && data.price == null && data.screenshotUri == null) {
      throw httpError;
    }
    return data;
  }

  Future<ImportedProductData> _fetchMetadata(Uri uri) async {
    final response = await _client.get(_canonicalizeMarketplace(uri), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
      'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    }).timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final document = html_parser.parse(response.body);
    String? meta(String name) =>
        document.querySelector('meta[property="$name"]')?.attributes['content'] ??
        document.querySelector('meta[name="$name"]')?.attributes['content'];

    String? title = _clean(meta('og:title')) ??
        _clean(meta('twitter:title')) ??
        _clean(document.querySelector('[data-widget="webProductHeading"] h1')?.text) ??
        _clean(document.querySelector('h1')?.text) ??
        _clean(document.querySelector('title')?.text);
    double? price = _parsePrice(meta('product:price:amount'));
    String? currency = meta('product:price:currency');
    final description = _clean(meta('og:description') ?? meta('twitter:description'));

    if (price == null) {
      for (final element in document.querySelectorAll('[itemprop="price"], [class*="price"], [data-testid*="price"]')) {
        final value = _parsePrice(_clean(element.text));
        if (value != null && value > 0) {
          price = value;
          currency ??= 'RUB';
          break;
        }
      }
    }

    for (final node in document.querySelectorAll('div[id^="state-webPrice-"]')) {
      final state = _decodeState(node.attributes['data-state']);
      if (state == null) continue;
      final rawPrice = '${state['price'] ?? state['currentPrice'] ?? state['salePrice'] ?? state['finalPrice'] ?? state['discountPrice'] ?? ''}';
      price ??= _parsePrice(rawPrice);
      currency ??= _currencyFromPrice(rawPrice);
      if (price != null) break;
    }

    for (final node in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final decoded = jsonDecode(node.text.trim());
        final values = decoded is List ? decoded : [decoded];
        for (final raw in values) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          title = ImportedProductData._selectTitle(title, _string(map['name']));
          final offers = map['offers'];
          if (offers is Map) {
            price ??= _parsePrice('${offers['price'] ?? offers['lowPrice'] ?? offers['highPrice'] ?? ''}');
            currency ??= _string(offers['priceCurrency']);
          }
          if (price != null) break;
        }
      } catch (_) {
        // Ignore malformed JSON-LD and continue.
      }
    }

    if (title == null || price == null) {
      final inline = response.body.replaceAll(RegExp(r'\\+"'), '"');
      if (title == null) {
        final match = RegExp(r'"name"\s*:\s*"([^"\\]{3,500})"').firstMatch(inline);
        title = ImportedProductData._selectTitle(title, _jsonUnescape(match?.group(1)));
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
    }

    return ImportedProductData(
      title: _clean(title),
      price: price,
      currency: currency,
      description: description,
      resolvedUrl: response.request?.url.toString(),
    );
  }

  static Map<String, dynamic>? _decodeState(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static String? _currencyFromPrice(String value) {
    final normalized = value.toUpperCase();
    if (normalized.contains('₽') || normalized.contains('RUB') || normalized.contains('РУБ')) return 'RUB';
    return null;
  }

  static bool _needsBrowser(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('ozon') ||
        host.contains('wildberries') ||
        host.contains('avito') ||
        host.contains('market.yandex') ||
        host.contains('yandex.ru');
  }

  static Uri _canonicalizeMarketplace(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!host.contains('ozon')) return uri;
    final match = RegExp(r'(?<!\d)(\d{7,})(?!\d)').firstMatch(uri.path);
    if (match == null) return uri;
    return Uri.parse('https://www.ozon.ru/product/${match.group(1)}/');
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

  static String? _string(dynamic value) =>
      value?.toString().trim().isEmpty == true ? null : value?.toString().trim();

  static String? _clean(String? value) => value?.replaceAll(RegExp(r'\s+'), ' ').trim();

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

  static String? _jsonUnescape(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    try {
      return jsonDecode('"${normalized.replaceAll('"', r'\"')}"') as String;
    } catch (_) {
      return normalized;
    }
  }
}
