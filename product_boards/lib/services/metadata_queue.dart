import 'dart:async';

import '../models/archive_item.dart';
import '../repositories/archive_repository.dart';
import 'metadata_service.dart';

class MetadataQueue {
  MetadataQueue({required this.repository, MetadataService? service}) : service = service ?? MetadataService();

  final ArchiveRepository repository;
  final MetadataService service;
  final Map<String, Future<void>> _running = {};

  static const _delays = <Duration>[
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  Future<void> enqueue(ArchiveItem item) async {
    if (_running.containsKey(item.id)) return;
    final future = _process(item);
    _running[item.id] = future;
    try {
      await future;
    } finally {
      _running.remove(item.id);
    }
  }

  Future<void> resumePending() async {
    final items = await repository.getItems();
    for (final item in items.where((item) => item.metadataStatus == MetadataStatus.loading)) {
      unawaited(enqueue(item));
    }
  }

  Future<void> _process(ArchiveItem initial) async {
    var lastError = false;

    for (var attempt = 0; attempt < _delays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_delays[attempt]);
      try {
        final result = await service.fetch(Uri.parse(initial.url));
        final titleOk = result.title?.trim().isNotEmpty == true;
        final imageOk = result.imageUrl?.trim().isNotEmpty == true;
        final next = initial.copyWith(
          title: initial.titleSource == TitleSource.manual ? initial.title : (titleOk ? result.title! : initial.title),
          imageUrl: imageOk ? result.imageUrl : initial.imageUrl,
          imageStatus: imageOk || initial.imageUrl != null ? ImageStatus.success : ImageStatus.failed,
          metadataStatus: titleOk && (imageOk || initial.imageUrl != null) ? MetadataStatus.success : (titleOk || imageOk ? MetadataStatus.partial : MetadataStatus.failed),
          updatedAt: DateTime.now(),
        );
        await repository.upsertItem(next);
        return;
      } on PermanentMetadataException {
        lastError = true;
        break;
      } on TemporaryMetadataException {
        lastError = true;
      } on TimeoutException {
        lastError = true;
      } catch (_) {
        lastError = true;
      }
    }

    if (lastError) {
      final failed = initial.copyWith(
        title: initial.titleSource == TitleSource.manual ? initial.title : initial.title.isEmpty ? 'Без названия' : initial.title,
        imageStatus: initial.imageUrl == null ? ImageStatus.failed : ImageStatus.success,
        metadataStatus: MetadataStatus.failed,
        updatedAt: DateTime.now(),
      );
      await repository.upsertItem(failed);
    }
  }
}
