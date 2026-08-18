import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageCacheService {
  ImageCacheService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _userAgent = 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36';

  Future<String?> cacheUrl(String url, {Uri? referer}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final dir = await _cacheDir();
      final response = await _client.get(uri, headers: {
        'User-Agent': _userAgent,
        if (referer != null) 'Referer': referer.toString(),
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (!_looksLikeImage(response.bodyBytes, response.headers['content-type'])) return null;
      if (response.bodyBytes.length < 4096) return null;

      final ext = _extension(response.headers['content-type'], response.bodyBytes);
      final digest = sha1.convert(uri.toString().codeUnits).toString();
      final file = File(p.join(dir.path, '$digest.$ext'));
      if (!await file.exists()) await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.uri.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> cacheLocalUri(String value) async {
    final uri = Uri.tryParse(value);
    if (uri?.scheme != 'file') return null;
    try {
      final source = File(uri!.toFilePath());
      if (!await source.exists()) return null;
      final bytes = await source.readAsBytes();
      if (!_looksLikeImage(bytes, null) || bytes.length < 4096) return null;
      final dir = await _cacheDir();
      final ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
      final digest = sha1.convert(bytes).toString();
      final file = File(p.join(dir.path, '$digest.${ext.isEmpty ? 'jpg' : ext}'));
      if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
      return file.uri.toString();
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _cacheDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'pinzon_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static bool _looksLikeImage(Uint8List bytes, String? contentType) {
    final type = (contentType ?? '').toLowerCase();
    if (type.startsWith('image/')) return true;
    if (bytes.length >= 12) {
      final png = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
      final jpg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
      final gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
      final webp = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
          bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
      return png || jpg || gif || webp;
    }
    return false;
  }

  static String _extension(String? contentType, Uint8List bytes) {
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('png')) return 'png';
    if (type.contains('webp')) return 'webp';
    if (type.contains('gif')) return 'gif';
    if (type.contains('avif')) return 'avif';
    if (_looksLikeImage(bytes, null) && bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    return 'jpg';
  }
}
