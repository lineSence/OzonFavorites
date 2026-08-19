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
    final value = source ?? url ?? data['title']?.toString() ?? data['price']?.toString();
    return value ?? event;
  }
}

class ImageDiagnostics {
  static const _name = 'Pinzon.Image';
  static const maxEntries = 100;
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
    final details = data.entries.where((entry) => entry.value != null).map((entry) => '${entry.key}=${entry.value}').join(' ');
    developer.log(details.isEmpty ? event : '$event $details', name: _name);
    _entries.add(ImageDiagnosticEntry(timestamp: DateTime.now(), event: event, data: Map<String, Object?>.from(data)));
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
    log('FAIL_$stage', {'url': url, 'error': error});
    if (stackTrace != null) developer.log(stackTrace.toString(), name: _name, level: 900);
  }
}
