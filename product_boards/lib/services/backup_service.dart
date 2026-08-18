import 'dart:convert';
import 'package:share_plus/share_plus.dart';

class BackupService {
  Future<void> shareJson(Map<String, dynamic> data) async {
    final text = const JsonEncoder.withIndent('  ').convert(data);
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Product Boards backup'));
  }

  Map<String, dynamic> decode(String text) {
    final value = jsonDecode(text);
    if (value is! Map) throw const FormatException('Некорректный файл резервной копии');
    return Map<String, dynamic>.from(value);
  }
}
