import 'package:domabas_api/api.dart' as api;
import 'package:flutter/widgets.dart';

import '../domain/identity/models/identity.dart';
import '../domain/scanner/interfaces/scan_draft_repository.dart';
import '../domain/scanner/interfaces/scanner_camera.dart';
import 'scanner_runtime_stub.dart'
    if (dart.library.io) 'scanner_runtime_native.dart'
    as platform;

abstract interface class ScannerScope {
  ScannerCamera get camera;
  ScanDraftRepository get repository;
  Widget Function(BuildContext) get previewBuilder;
  void cancelNewOperations();
  Future<void> close();
}

abstract interface class ScannerScopeFactory {
  Future<ScannerScope> open();
  void cancelNewOperations();
  Future<void> close();
}

abstract interface class ScannerCoordinator {
  ScannerScopeFactory? forSession(
    String endpoint,
    Identity identity,
    api.ApiClient client,
  );
}

ScannerCoordinator createScannerCoordinator() =>
    platform.createScannerCoordinator();
