import 'dart:convert';
import 'dart:developer' as developer;

class ImageDiagnosticEntry {
  ImageDiagnosticEntry({required this.timestamp, required this.event, required this.data});
  final DateTime timestamp;
  final String event;
  final Map<String, Object?> data;

  String? get url => data['url']?.toString();
  String? get source => data['source']?.toString();
  int? get statusCode => data['status'] is int ? data['status'] as int : int.tryParse('${data['status'] ?? ''}');
  String? get contentType => data['contentType']?.toString();
  int? get bytes => data['bytes'] is int ? data['bytes'] as int : int.tryParse('${data['bytes'] ?? ''}');
  String? get path => data['path']?.toString();
  String? get error => data['error']?.toString();

  String? dataValue(String key) => data[key]?.toString();

  String get summary {
    if (event.startsWith('FAIL_')) return error ?? event;
    if (event == 'RESPONSE') return 'HTTP ${statusCode ?? '?'} · ${contentType ?? '?'} · ${bytes ?? 0} B';
    if (event == 'SAVED' || event == 'CACHE_HIT') return path ?? event;
    if (event == 'WEBVIEW_RESULT') {
      final reason = data['reason']?.toString();
      final finalUrl = data['finalUrl']?.toString();
      return [reason, finalUrl].where((value) => value != null && value.isNotEmpty).join(' · ').ifEmpty(event);
    }
    final value = source ?? url ?? data['title']?.toString() ?? data['price']?.toString();
    return value ?? event;
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class ImageDiagnostics {
  static const _name = 'Pinzon.Image';
  static const maxEntries = 250;
  static final List<ImageDiagnosticEntry> _entries = <ImageDiagnosticEntry>[];
  static final List<void Function()> _callbacks = <void Function()>[];

  static List<ImageDiagnosticEntry> get entries => List.unmodifiable(_entries.reversed);
  static bool get hasEntries => _entries.isNotEmpty;

  static void addListener(void Function() listener) {
    if (!_callbacks.contains(listener)) _callbacks.add(listener);
  }

  static void removeListener(void Function() listener) => _callbacks.remove(listener);

  static void clear() {
    _entries.clear();
    _notify();
  }

  static void log(String event, [Map<String, Object?> data = const {}]) {
    final cleanData = <String, Object?>{};
    for (final entry in data.entries) {
      if (entry.value != null) cleanData[entry.key] = _jsonSafe(entry.value);
    }
    final details = cleanData.entries.map((entry) => '${entry.key}=${entry.value}').join(' ');
    developer.log(details.isEmpty ? event : '$event $details', name: _name);
    _entries.add(ImageDiagnosticEntry(timestamp: DateTime.now(), event: event, data: cleanData));
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
    _notify();
  }

  static void _notify() {
    for (final callback in List<void Function()>.from(_callbacks)) {
      callback();
    }
  }

  static void start(String url, {String? referer}) => log('START', {'url': url, 'referer': referer});

  static void candidate(String source, String? url) => log('CANDIDATE', {'source': source, 'url': url});

  static void response({required String url, required int statusCode, String? contentType, int? bytes, String? finalUrl}) =>
      log('RESPONSE', {'url': url, 'status': statusCode, 'contentType': contentType, 'bytes': bytes, 'finalUrl': finalUrl});

  static void result(String message, {String? url, String? path}) => log(message, {'url': url, 'path': path});

  static void failure(String stage, Object error, {String? url, StackTrace? stackTrace}) {
    log('FAIL_$stage', {
      'url': url,
      'error': error.toString(),
      'stackTrace': stackTrace?.toString(),
    });
  }

  static String exportJson({String? appVersion, String? platform}) {
    final payload = <String, Object?>{
      'format': 'pinzon-image-diagnostics/v1',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'app': <String, Object?>{
        'name': 'Pinzon',
        'version': appVersion,
        'platform': platform,
      },
      'entryCount': _entries.length,
      'entries': _entries.map((entry) => <String, Object?>{
            'timestamp': entry.timestamp.toUtc().toIso8601String(),
            'event': entry.event,
            'data': entry.data,
          }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String exportJsonLines({String? appVersion, String? platform}) {
    final lines = <String>[];
    lines.add(jsonEncode({
      'format': 'pinzon-image-diagnostics-jsonl/v1',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'app': {'name': 'Pinzon', 'version': appVersion, 'platform': platform},
      'entryCount': _entries.length,
    }));
    for (final entry in _entries) {
      lines.add(jsonEncode({
        'timestamp': entry.timestamp.toUtc().toIso8601String(),
        'event': entry.event,
        'data': entry.data,
      }));
    }
    return lines.join('\n');
  }

  static Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) return value;
    if (value is Iterable) return value.map(_jsonSafe).toList();
    if (value is Map) return value.map((key, value) => MapEntry(key.toString(), _jsonSafe(value)));
    try {
      jsonEncode(value);
      return value;
    } catch (_) {
      return value.toString();
    }
  }
}
