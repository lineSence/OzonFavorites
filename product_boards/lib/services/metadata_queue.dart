import 'dart:async';

import '../models/archive_item.dart';
import '../repositories/archive_repository.dart';
import 'metadata_service.dart';
import 'product_classifier.dart';

/// Background queue for text metadata and deterministic smart sorting.
/// Images are produced exclusively by the Android WebView screenshot pipeline.
class MetadataQueue {
  MetadataQueue({required this.repository, MetadataService? service, ProductClassifier? classifier})
      : service = service ?? MetadataService(),
        classifier = classifier ?? ProductClassifier();

  final ArchiveRepository repository;
  final MetadataService service;
  final ProductClassifier classifier;
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
        final classificationInput = titleOk ? result.title!.trim() : initial.title.trim();
        final classification = classifier.classify(
          classificationInput.isEmpty ? initial.title : classificationInput,
        );

        final next = initial.copyWith(
          title: initial.titleSource == TitleSource.manual ? initial.title : (titleOk ? result.title! : initial.title),
          // Preserve screenshot-derived image fields.
          imageUrl: initial.imageUrl,
          imageStatus: initial.imageStatus,
          // Do not overwrite an explicit/manual board assignment.
          categoryId: initial.categoryId ?? classification.categoryId,
          metadataStatus: titleOk ? MetadataStatus.success : MetadataStatus.partial,
          updatedAt: DateTime.now(),
        );

        // Classification is intentionally observable in diagnostics before we
        // introduce additional persistent fields to ArchiveItem.
        // This keeps the current storage schema backwards compatible.
        // ignore: avoid_print
        print('[PinzonClassifier] category=${classification.categoryId} confidence=${classification.confidence.toStringAsFixed(2)} brand=${classification.brand} type=${classification.productType} model=${classification.model} color=${classification.color} size=${classification.size} material=${classification.material} quantity=${classification.quantity}');

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
        imageUrl: initial.imageUrl,
        imageStatus: initial.imageStatus,
        metadataStatus: MetadataStatus.failed,
        updatedAt: DateTime.now(),
      );
      await repository.upsertItem(failed);
    }
  }
}
