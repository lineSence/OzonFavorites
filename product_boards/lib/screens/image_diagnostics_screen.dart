import 'package:flutter/material.dart';
import '../services/image_diagnostics.dart';

class ImageDiagnosticsScreen extends StatefulWidget {
  const ImageDiagnosticsScreen({super.key});

  @override
  State<ImageDiagnosticsScreen> createState() => _ImageDiagnosticsScreenState();
}

class _ImageDiagnosticsScreenState extends State<ImageDiagnosticsScreen> {
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

  @override
  Widget build(BuildContext context) {
    final entries = ImageDiagnostics.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика изображений'),
        actions: [
          IconButton(
            tooltip: 'Очистить',
            onPressed: entries.isEmpty ? null : () => ImageDiagnostics.clear(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Пока нет попыток загрузки изображений. Добавьте товар и откройте этот экран снова.', textAlign: TextAlign.center)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final entry = entries[index];
                return Card(
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
                      if (entry.error != null) _row('Ошибка', entry.error!),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SelectableText('$label: $value', style: const TextStyle(fontSize: 12.5)),
        ),
      );

  IconData _icon(String event) {
    if (event.startsWith('FAIL_')) return Icons.error_outline_rounded;
    if (event == 'SAVED') return Icons.check_circle_outline_rounded;
    if (event == 'RESPONSE') return Icons.http_rounded;
    if (event == 'CANDIDATE') return Icons.image_search_rounded;
    return Icons.image_outlined;
  }

  Color _color(BuildContext context, String event) {
    if (event.startsWith('FAIL_')) return Theme.of(context).colorScheme.error;
    if (event == 'SAVED') return Colors.green;
    return Theme.of(context).colorScheme.primary;
  }
}
