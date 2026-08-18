import 'dart:developer' as developer;
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
    _log('START', 'url=$url referer=${referer ?? '-'}');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _log('INVALID_URL', 'Could not parse image URL');
      return null;
    }
    try {
      final dir = await _cacheDir();
      _log('REQUEST', 'GET $uri');
      final response = await _client.get(uri, headers: {
        'User-Agent': _userAgent,
        if (referer != null) 'Referer': referer.toString(),
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      }).timeout(const Duration(seconds: 15));
      final contentType = response.headers['content-type'];
      _log('RESPONSE', 'status=${response.statusCode} contentType=${contentType ?? '-'} bytes=${response.bodyBytes.length} finalUrl=${response.request?.url ?? uri}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _log('FAIL_HTTP', 'Unexpected HTTP status ${response.statusCode}');
        return null;
      }
      final looksLikeImage = _looksLikeImage(response.bodyBytes, contentType);
      _log('VALIDATE_TYPE', 'looksLikeImage=$looksLikeImage');
      if (!looksLikeImage) {
        _log('FAIL_NOT_IMAGE', 'Response is not recognized as an image; firstBytes=${_hexPrefix(response.bodyBytes)}');
        return null;
      }
      if (response.bodyBytes.length < 4096) {
        _log('FAIL_TOO_SMALL', 'Image payload is smaller than 4096 bytes');
        return null;
      }

      final ext = _extension(contentType, response.bodyBytes);
      final digest = sha1.convert(uri.toString().codeUnits).toString();
      final file = File(p.join(dir.path, '$digest.$ext'));
      if (!await file.exists()) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        _log('SAVED', 'path=${file.path} ext=$ext bytes=${response.bodyBytes.length}');
      } else {
        _log('CACHE_HIT', 'path=${file.path}');
      }
      return file.uri.toString();
    } on SocketException catch (error) {
      _log('FAIL_SOCKET', error.toString());
      return null;
    } on HttpException catch (error) {
      _log('FAIL_HTTP_EXCEPTION', error.toString());
      return null;
    } on FormatException catch (error) {
      _log('FAIL_FORMAT', error.toString());
      return null;
    } on Exception catch (error) {
      _log('FAIL_EXCEPTION', error.toString());
      return null;
    }
  }

  Future<String?> cacheLocalUri(String value) async {
    _log('LOCAL_START', 'uri=$value');
    final uri = Uri.tryParse(value);
    if (uri?.scheme != 'file') {
      _log('LOCAL_INVALID', 'Only file:// URIs are supported');
      return null;
    }
    try {
      final source = File(uri!.toFilePath());
      final exists = await source.exists();
      _log('LOCAL_SOURCE', 'exists=$exists path=${source.path}');
      if (!exists) return null;
      final bytes = await source.readAsBytes();
      final looksLikeImage = _looksLikeImage(bytes, null);
      _log('LOCAL_VALIDATE', 'looksLikeImage=$looksLikeImage bytes=${bytes.length}');
      if (!looksLikeImage || bytes.length < 4096) return null;
      final dir = await _cacheDir();
      final ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
      final digest = sha1.convert(bytes).toString();
      final file = File(p.join(dir.path, '$digest.${ext.isEmpty ? 'jpg' : ext}'));
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
        _log('LOCAL_SAVED', 'path=${file.path} bytes=${bytes.length}');
      } else {
        _log('LOCAL_CACHE_HIT', 'path=${file.path}');
      }
      return file.uri.toString();
    } on Exception catch (error) {
      _log('LOCAL_FAIL', error.toString());
      return null;
    }
  }

  Future<Directory> _cacheDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'pinzon_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static void _log(String stage, String message) {
    developer.log('[$stage] $message', name: 'Pinzon.ImageCache');
  }

  static String _hexPrefix(Uint8List bytes) {
    final length = bytes.length < 24 ? bytes.length : 24;
    return bytes.sublist(0, length).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
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
