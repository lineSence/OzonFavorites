import 'dart:developer' as developer;

class ImageDiagnostics {
  static const _name = 'Pinzon.Image';

  static void log(String event, [Map<String, Object?> data = const {}]) {
    final details = data.entries.where((entry) => entry.value != null).map((entry) => '${entry.key}=${entry.value}').join(' ');
    developer.log(details.isEmpty ? event : '$event $details', name: _name);
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
