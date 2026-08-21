import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageCacheService {
  Future<String?> cacheLocalUri(String value) async {
    _log('LOCAL_START', 'uri=$value');
    final uri = Uri.tryParse(value);
    if (uri?.scheme != 'file') {
      _log('LOCAL_INVALID', 'Only file:// URIs are accepted; image URLs are deliberately unsupported');
      return null;
    }
    try {
      final source = File(uri!.toFilePath());
      final exists = await source.exists();
      _log('LOCAL_SOURCE', 'exists=$exists path=${source.path}');
      if (!exists) return null;
      final bytes = await source.readAsBytes();
      final looksLikeImage = _looksLikeImage(bytes);
      _log('LOCAL_VALIDATE', 'looksLikeImage=$looksLikeImage bytes=${bytes.length}');
      if (!looksLikeImage || bytes.length < 4096) {
        _log('LOCAL_REJECTED', 'Screenshot is missing, invalid, or too small');
        return null;
      }
      final dir = await _cacheDir();
      final digest = sha1.convert(bytes).toString();
      final ext = _extension(source.path, bytes);
      final file = File(p.join(dir.path, '$digest.$ext'));
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

  static void _log(String stage, String message) => developer.log('[$stage] $message', name: 'Pinzon.ImageCache');

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length >= 12) {
      final png = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
      final jpg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
      final gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
      final webp = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
      return png || jpg || gif || webp;
    }
    return false;
  }

  static String _extension(String path, Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'jpg';
    if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'png';
    if (bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) return 'webp';
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }
}
