import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/document/models/prepared_document_upload_metadata.dart';
import 'package:domabas/data/scanner/datasources/ml_kit_scanner_camera.dart';
import 'package:domabas/data/scanner/datasources/scan_draft_store.dart';
import 'package:domabas/data/scanner/datasources/scan_pdf_encoder.dart';
import 'package:domabas/data/scanner/datasources/scan_storage_coordinator.dart';
import 'package:domabas/data/scanner/models/scan_image_limits.dart';
import 'package:domabas/data/scanner/repos/local_scan_draft_repository.dart';
import 'package:domabas/data/scanner/repos/scan_upload_data_port.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas/presentation/scanner/cubits/scanner_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scanner_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.domabas/document_scanner');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late ScanStorageCoordinator coordinator;
  late ScanStorageLease lease;
  late MlKitScannerCamera camera;
  late ScanDraftStore store;
  late LocalScanDraftRepository repository;
  late ScannerCubit cubit;
  late Uint8List jpeg;
  late Future<Uint8List?> Function() scan;
  final calls = <MethodCall>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('domabas-mlkit-');
    coordinator = ScanStorageCoordinator(() async => root);
    lease = await coordinator.acquire('mlkit-owner');
    camera = MlKitScannerCamera(lease);
    store = ScanDraftStore(lease);
    repository = LocalScanDraftRepository(
      lease: lease,
      camera: camera,
      upload: _UnexpectedScanUpload(),
      store: store,
      encoder: ScanPdfEncoder(),
    );
    cubit = ScannerCubit(camera: camera, repository: repository, allowed: true);
    jpeg = scanJpeg(600, 800);
    scan = () async => jpeg;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'scan' ? await scan() : null;
    });
  });

  tearDown(() async {
    await cubit.close();
    await camera.close();
    await repository.close();
    await lease.release();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test(
    'system capture saves exact JPEG and embeds it unchanged in PDF',
    () async {
      await cubit.restore();
      await cubit.addPage();
      expect(calls.map((call) => call.method), ['scan']);
      expect(cubit.state.error, isNull);
      expect(cubit.state.stage, ScannerStage.review);
      expect(cubit.state.capture, isNull);
      expect(cubit.state.draft!.pages, hasLength(1));
      final record = (store.record!['pages'] as List).single as Map;
      final file = store.asset(store.record!, record['file'] as String);
      expect(await file.readAsBytes(), jpeg);
      expect((record['width'], record['height']), (600, 800));
      final pdf = await ScanPdfEncoder().encode([
        ScanPdfPage(file.path, 600, 800),
      ]);
      expect(latin1.decode(pdf), contains(latin1.decode(jpeg)));
      expect(lease.scratchBytes, 0);
      final restored = ScanDraftStore(lease);
      await restored.initialize();
      expect((await restored.snapshot()).pages, hasLength(1));
      restored.release();
    },
  );

  test(
    'cancelling native UI returns to draft and permits another scan',
    () async {
      scan = () async => null;
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.stage, ScannerStage.review);
      expect(cubit.state.error, isNull);
      expect(cubit.state.draft!.pages, isEmpty);
      expect(lease.scratchBytes, 0);
      scan = () async => jpeg;
      await cubit.addPage();
      expect(cubit.state.draft!.pages, hasLength(1));
    },
  );

  test(
    'Google activity background and resume preserve the in-flight page',
    () async {
      final pending = Completer<Uint8List?>();
      final entered = Completer<void>();
      scan = () {
        entered.complete();
        return pending.future;
      };
      await cubit.restore();
      final adding = cubit.addPage();
      await entered.future;
      final backgrounding = cubit.setForeground(false);
      final resuming = cubit.setForeground(true);
      expect(calls.where((call) => call.method == 'cancel'), isEmpty);
      pending.complete(jpeg);
      await Future.wait([adding, backgrounding, resuming]);
      expect(cubit.state.error, isNull);
      expect(cubit.state.stage, ScannerStage.review);
      expect(cubit.state.draft!.pages, hasLength(1));
      expect(calls.where((call) => call.method == 'scan'), hasLength(1));
    },
  );

  test(
    'closing cancels its request and drains a late result before handoff',
    () async {
      final pending = Completer<Uint8List?>();
      final entered = Completer<void>();
      scan = () {
        entered.complete();
        return pending.future;
      };
      await cubit.restore();
      final adding = cubit.addPage();
      await entered.future;
      final closing = cubit.close();
      await Future<void>.delayed(Duration.zero);
      final cancel = calls.singleWhere((call) => call.method == 'cancel');
      expect(cancel.arguments, calls.first.arguments);
      pending.complete(jpeg);
      await Future.wait([adding, closing]);
      await camera.close();
      expect(store.record!['pages'], isEmpty);
      expect(lease.scratchBytes, 0);
      final release = await coordinator.acquireCamera();
      release();
      expect(
        await lease.directory
            .list()
            .where((file) => file.path.contains('scratch-'))
            .toList(),
        isEmpty,
      );
    },
  );

  for (final failure in ['unsupported', 'corrupt', 'oversize', 'pixels']) {
    test(
      '$failure result preserves saved pages and releases scratch storage',
      () async {
        await cubit.restore();
        await cubit.addPage();
        scan = () async {
          switch (failure) {
            case 'unsupported':
              throw PlatformException(
                code: 'scan_unsupported',
                message: 'private SDK detail',
              );
            case 'corrupt':
              return Uint8List.fromList([1, 2, 3]);
            case 'oversize':
              return Uint8List(ScanImageLimits.maxPageBytes + 1);
            default:
              final bytes = Uint8List.fromList(jpeg);
              for (var i = 0; i < bytes.length - 8; i++) {
                if (bytes[i] == 0xff && bytes[i + 1] == 0xc0) {
                  bytes[i + 5] = 0x27;
                  bytes[i + 6] = 0x10;
                  bytes[i + 7] = 0x27;
                  bytes[i + 8] = 0x10;
                  return bytes;
                }
              }
              throw StateError('Fixture has no JPEG frame header');
          }
        };
        await cubit.addPage();
        expect(cubit.state.error, isNotNull);
        if (failure == 'unsupported') {
          expect(cubit.state.error, contains('not supported on this device'));
        }
        expect(cubit.state.error, isNot(contains('private SDK detail')));
        expect(cubit.state.stage, ScannerStage.review);
        expect(cubit.state.draft!.pages, hasLength(1));
        expect(lease.scratchBytes, 0);
      },
    );
  }

  test(
    'failed page save keeps processed capture for retry without cropping',
    () async {
      await cubit.close();
      final retryRepository = _RetryScanRepository();
      await camera.close();
      await repository.close();
      await lease.release();
      lease = await coordinator.acquire('mlkit-owner');
      camera = MlKitScannerCamera(lease);
      cubit = ScannerCubit(
        camera: camera,
        repository: retryRepository,
        allowed: true,
      );
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.stage, ScannerStage.correction);
      expect(cubit.state.capture!.processed, isTrue);
      final corners = cubit.state.corners;
      cubit.moveCorner(0, const ScanPoint(.2, .2));
      cubit.moveEdge(0, const ScanPoint(.5, .3));
      cubit.resetCorners();
      expect(cubit.state.corners, same(corners));
      retryRepository.fail = false;
      await cubit.keepPage();
      expect(cubit.state.stage, ScannerStage.review);
      expect(cubit.state.draft!.pages, hasLength(1));
      expect(calls.where((call) => call.method == 'scan'), hasLength(1));
      expect(lease.scratchBytes, 0);
    },
  );
}

final class _RetryScanRepository extends FixtureScanRepository {
  bool fail = true;
  @override
  Future<ScanDraft> keepPage(ScanCapture capture, ScanCorners corners) {
    if (fail) throw const ScanFailure('Save failed. Try again.');
    return super.keepPage(capture, corners);
  }
}

final class _UnexpectedScanUpload implements ScanUploadDataPort {
  @override
  PreparedDocumentUploadMetadata prepare(DocumentProperties properties) =>
      throw StateError('Unexpected upload');
  @override
  Future<Document> send(
    Uint8List pdfBytes,
    PreparedDocumentUploadMetadata metadata,
    String filename,
    Future<void> cancel,
  ) => throw StateError('Unexpected upload');
}
