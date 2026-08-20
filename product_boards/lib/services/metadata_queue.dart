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
    final pending = items.where((item) => item.metadataStatus == MetadataStatus.loading);
    for (final item in pending) {
      unawaited(enqueue(item));
    }
  }

  Future<void> _process(ArchiveItem initial) async {
    ArchiveItem item = initial;
    Object? lastError;
    for (var attempt = 0; attempt < _delays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_delays[attempt]);
      try {
        final result = await service.fetch(Uri.parse(item.url));
        final titleAvailable = result.title != null && result.title!.isNotEmpty;
        final imageAvailable = result.imageUrl != null && result.imageUrl!.isNotEmpty;
        final next = item.copyWith(
          title: item.titleSource == TitleSource.manual
              ? item.title
              : (titleAvailable ? result.title! : 'Без названия'),
          imageUrl: imageAvailable ? result.imageUrl : null,
          imageStatus: imageAvailable ? ImageStatus.success : ImageStatus.failed,
          metadataStatus: titleAvailable && imageAvailable
              ? MetadataStatus.success
              : (titleAvailable || imageAvailable ? MetadataStatus.partial : MetadataStatus.failed),
          updatedAt: DateTime.now(),
        );
        await repository.upsertItem(next);
        return;
      } on PermanentMetadataException catch (error) {
        lastError = error;
        break;
      } on TemporaryMetadataException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      } on Object catch (error) {
        lastError = error;
      }
    }

    final failed = item.copyWith(
      title: item.titleSource == TitleSource.manual ? item.title : 'Без названия',
      imageUrl: null,
      imageStatus: ImageStatus.failed,
      metadataStatus: MetadataStatus.failed,
      updatedAt: DateTime.now(),
    );
    await repository.upsertItem(failed);
    // Keep the exception out of the UI: the URL itself remains valid.
    // ignore: avoid_print
    print('Metadata failed for ${item.url}: $lastError');
  }
}
