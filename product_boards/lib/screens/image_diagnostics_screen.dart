import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/image_diagnostics.dart';

class ImageDiagnosticsScreen extends StatefulWidget {
  const ImageDiagnosticsScreen({super.key});

  @override
  State<ImageDiagnosticsScreen> createState() => _ImageDiagnosticsScreenState();
}

class _ImageDiagnosticsScreenState extends State<ImageDiagnosticsScreen> {
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    ImageDiagnostics.addListener(_refresh);
  }

  @override
  void dispose() {
    ImageDiagnostics.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _exportLog() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${directory.path}/pinzon_diagnostics_$timestamp.json');
      await file.writeAsString(ImageDiagnostics.exportJson(platform: Platform.operatingSystem));
      await SharePlus.instance.share(
        ShareParams(
          text: 'Pinzon — диагностический лог импорта товаров',
          files: [XFile(file.path, mimeType: 'application/json')],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Не удалось выгрузить лог: $error')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ImageDiagnostics.entries;
    final lastResult = entries.cast<ImageDiagnosticEntry?>().firstWhere(
      (entry) => entry != null && entry.event == 'IMPORT_RESULT',
      orElse: () => null,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика импорта'),
        actions: [
          IconButton(
            tooltip: 'Выгрузить лог',
            onPressed: exporting || entries.isEmpty ? null : _exportLog,
            icon: exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Очистить',
            onPressed: entries.isEmpty ? null : ImageDiagnostics.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Здесь появится причина, почему не загрузились название, цена или изображение. Откройте экран ДО следующей попытки импорта.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _exportHint(context),
                const SizedBox(height: 12),
                if (lastResult != null) _resultCard(context, lastResult),
                const SizedBox(height: 12),
                Text('Журнал', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ExpansionTile(
                          leading: Icon(_icon(entry.event), color: _color(context, entry.event)),
                          title: Text(entry.event, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(entry.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            _row('Время', entry.timestamp.toLocal().toString()),
                            if (entry.url != null) _row('URL', entry.url!),
                            if (entry.source != null) _row('Источник', entry.source!),
                            if (entry.statusCode != null) _row('HTTP', '${entry.statusCode}'),
                            if (entry.contentType != null) _row('Content-Type', entry.contentType!),
                            if (entry.bytes != null) _row('Размер', '${entry.bytes} B'),
                            if (entry.path != null) _row('Файл', entry.path!),
                            ...entry.data.entries.where((item) => !{'url', 'source', 'status', 'contentType', 'bytes', 'path', 'error'}.contains(item.key)).map((item) => _row(item.key, item.value.toString())),
                            if (entry.error != null) _row('Ошибка', entry.error!),
                          ],
                        ),
                      ),
                    )),
              ],
            ),
    );
  }

  Widget _exportHint(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Лог можно передать целиком'),
          subtitle: const Text('Кнопка ↑ сверху создаёт JSON-файл, удобный для разбора в чате.'),
          trailing: IconButton(
            tooltip: 'Выгрузить лог',
            onPressed: exporting || ImageDiagnostics.entries.isEmpty ? null : _exportLog,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ),
      );

  Widget _resultCard(BuildContext context, ImageDiagnosticEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Последний результат', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            _statusRow(context, 'Название', entry.dataValue('title')),
            _statusRow(context, 'Цена', entry.dataValue('price')),
            _statusRow(context, 'Изображение', entry.dataValue('image')),
            _statusRow(context, 'Локальный файл', entry.dataValue('localImage')),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(BuildContext context, String label, String? value) {
    final ok = value != null && value.trim().isNotEmpty && value != 'null';
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.cancel_outlined, size: 18, color: ok ? Colors.green : Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text('$label: ${ok ? value : 'не найдено'}')),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(alignment: Alignment.centerLeft, child: SelectableText('$label: $value', style: const TextStyle(fontSize: 12.5))),
      );

  IconData _icon(String event) {
    if (event.startsWith('FAIL_')) return Icons.error_outline_rounded;
    if (event == 'SAVED') return Icons.check_circle_outline_rounded;
    if (event == 'RESPONSE') return Icons.http_rounded;
    if (event == 'CANDIDATE') return Icons.image_search_rounded;
    if (event.startsWith('WEBVIEW_')) return Icons.web_outlined;
    return Icons.image_outlined;
  }

  Color _color(BuildContext context, String event) {
    if (event.startsWith('FAIL_')) return Theme.of(context).colorScheme.error;
    if (event == 'SAVED') return Colors.green;
    return Theme.of(context).colorScheme.primary;
  }
}
