import 'dart:async';

import 'package:flutter/material.dart';

import 'app/pinzon_app.dart';
import 'repositories/archive_repository.dart';
import 'repositories/local_archive_repository.dart';
import 'services/metadata_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ArchiveRepository repository = LocalArchiveRepository();
  await repository.init();

  final queue = MetadataQueue(repository: repository);
  unawaited(queue.resumePending().catchError((_) {}));

  runApp(PinzonApp(repository: repository, queue: queue));
}
