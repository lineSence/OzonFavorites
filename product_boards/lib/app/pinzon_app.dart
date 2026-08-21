import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repositories/archive_repository.dart';
import '../services/metadata_queue.dart';
import '../screens/archive_screen.dart';

class PinzonApp extends StatefulWidget {
  const PinzonApp({super.key, required this.repository, required this.queue});

  final ArchiveRepository repository;
  final MetadataQueue queue;

  @override
  State<PinzonApp> createState() => _PinzonAppState();
}

class _PinzonAppState extends State<PinzonApp> {
  static const _channel = MethodChannel('product_boards/share');
  Map<Object?, Object?>? _sharedData;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethodCall);
    unawaited(_loadInitialShare());
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'sharedData' && call.arguments is Map && mounted) {
      setState(() => _sharedData = Map<Object?, Object?>.from(call.arguments as Map));
    }
  }

  Future<void> _loadInitialShare() async {
    try {
      final value = await _channel.invokeMethod('getInitialSharedData');
      if (mounted && value is Map) {
        setState(() => _sharedData = Map<Object?, Object?>.from(value));
      }
    } catch (_) {
      // Share input is optional; the archive remains usable when the bridge fails.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pinzon',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
          scaffoldBackgroundColor: const Color(0xfff6f6f4),
        ),
        home: ArchiveScreen(
          repository: widget.repository,
          queue: widget.queue,
          sharedData: _sharedData,
          onSharedDataConsumed: () => setState(() => _sharedData = null),
        ),
      );
}
