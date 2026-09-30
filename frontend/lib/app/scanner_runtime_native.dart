import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../data/document/datasources/document_upload_remote_data_source.dart';
import '../data/scanner/datasources/native_scanner_camera.dart';
import '../data/scanner/datasources/scan_draft_store.dart';
import '../data/scanner/datasources/scan_pdf_encoder.dart';
import '../data/scanner/datasources/scan_storage_coordinator.dart';
import '../data/scanner/repos/local_scan_draft_repository.dart';
import '../domain/identity/models/identity.dart';
import '../domain/scanner/models/scan.dart';
import 'scanner_document_upload_adapter.dart';
import 'scanner_scope.dart';

ScannerCoordinator createScannerCoordinator() => _NativeScannerCoordinator();

final class _NativeScannerCoordinator implements ScannerCoordinator {
  _NativeScannerCoordinator() {
    storage = ScanStorageCoordinator(_root);
  }
  late final ScanStorageCoordinator storage;
  Future<Directory>? _directory;
  Future<Directory> _root() =>
      _directory ??= _prepareRoot().onError((Object error, StackTrace trace) {
        _directory = null;
        Error.throwWithStackTrace(error, trace);
      });
  Future<Directory> _prepareRoot() async {
    final directory = Directory(
      path.join((await getApplicationSupportDirectory()).path, 'scanner-v1'),
    );
    await directory.create(recursive: true);
    if (Platform.isIOS) {
      final excluded = await const MethodChannel('dev.domabas/scanner_storage')
          .invokeMethod<bool>('excludeFromBackup', {'path': directory.path});
      if (excluded != true) {
        throw const ScanFailure(
          'Secure local scan storage could not be prepared.',
        );
      }
    }
    return directory;
  }

  @override
  ScannerScopeFactory? forSession(
    String endpoint,
    Identity identity,
    api.ApiClient client,
  ) {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    final uri = Uri.parse(endpoint);
    final canonical = uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
          fragment: '',
        )
        .toString();
    final owner = sha256
        .convert(
          utf8.encode(
            jsonEncode([canonical, identity.userId, identity.accountId]),
          ),
        )
        .toString();
    return _NativeScannerFactory(
      storage,
      owner,
      identity.allows(IdentityPermission.uploadDocuments),
      DocumentUploadRemoteDataSource(client),
    );
  }
}

final class _NativeScannerFactory implements ScannerScopeFactory {
  _NativeScannerFactory(this.storage, this.owner, this.allowed, this.upload);
  final ScanStorageCoordinator storage;
  final String owner;
  final bool allowed;
  final DocumentUploadRemoteDataSource upload;
  final _scopes = <_NativeScannerScope>{};
  bool _cancelled = false;
  @override
  Future<ScannerScope> open() async {
    if (_cancelled || !allowed) {
      throw const ScanFailure(
        'You do not have permission to scan into this library.',
      );
    }
    final lease = await storage.acquire(owner);
    if (_cancelled) {
      await lease.release();
      throw const ScanFailure('This scanner session has ended.');
    }
    final camera = NativeScannerCamera(lease);
    final repository = LocalScanDraftRepository(
      lease: lease,
      camera: camera,
      upload: ScannerDocumentUploadAdapter(upload),
      store: ScanDraftStore(lease),
      encoder: ScanPdfEncoder(),
    );
    final scope = _NativeScannerScope(camera, repository, lease);
    _scopes.add(scope);
    scope.onClosed = () => _scopes.remove(scope);
    return scope;
  }

  @override
  void cancelNewOperations() {
    if (_cancelled) return;
    _cancelled = true;
    upload.cancelRequests();
    for (final scope in _scopes.toList()) {
      scope.cancelNewOperations();
      unawaited(
        scope.close().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  @override
  Future<void> close() async {
    cancelNewOperations();
    await Future.wait(_scopes.toList().map((scope) => scope.close()));
  }
}

final class _NativeScannerScope implements ScannerScope {
  _NativeScannerScope(this.camera, this.repository, this.lease);
  @override
  final NativeScannerCamera camera;
  @override
  final LocalScanDraftRepository repository;
  final ScanStorageLease lease;
  void Function()? onClosed;
  Future<void>? _closing;
  @override
  Widget Function(BuildContext) get previewBuilder => (_) {
    final controller = camera.currentController;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  };
  @override
  void cancelNewOperations() {
    repository.cancelNewOperations();
    camera.cancelNewOperations();
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    cancelNewOperations();
    try {
      await repository.close();
    } finally {
      try {
        await camera.close();
      } finally {
        await lease.release();
        onClosed?.call();
      }
    }
  }
}
