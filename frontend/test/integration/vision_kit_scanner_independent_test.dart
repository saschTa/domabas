import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/document/models/prepared_document_upload_metadata.dart';
import 'package:domabas/data/scanner/datasources/scan_draft_store.dart';
import 'package:domabas/data/scanner/datasources/scan_pdf_encoder.dart';
import 'package:domabas/data/scanner/datasources/scan_storage_coordinator.dart';
import 'package:domabas/data/scanner/datasources/vision_kit_scanner_camera.dart';
import 'package:domabas/data/scanner/models/scan_image_limits.dart';
import 'package:domabas/data/scanner/repos/local_scan_draft_repository.dart';
import 'package:domabas/data/scanner/repos/scan_upload_data_port.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/presentation/scanner/cubits/scanner_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scanner_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.domabas/visionkit_document_scanner');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late ScanStorageCoordinator coordinator;
  late ScanStorageLease lease;
  late VisionKitScannerCamera camera;
  late ScanDraftStore store;
  late LocalScanDraftRepository repository;
  late ScannerCubit cubit;
  late _FailingScanStorageUsage usage;
  late List<Uint8List> pages;
  late Future<int?> Function(MethodCall) scan;
  late Future<Uint8List> Function(int) readPage;
  late Future<void> Function() finish;
  late Future<void> Function() cancel;
  final calls = <MethodCall>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('domabas-visionkit-');
    usage = _FailingScanStorageUsage();
    coordinator = ScanStorageCoordinator(() async => root, usage: usage);
    lease = await coordinator.acquire('visionkit-owner');
    camera = VisionKitScannerCamera(lease);
    store = ScanDraftStore(lease);
    repository = LocalScanDraftRepository(
      lease: lease,
      camera: camera,
      upload: _UnexpectedScanUpload(),
      store: store,
      encoder: ScanPdfEncoder(),
    );
    cubit = ScannerCubit(camera: camera, repository: repository, allowed: true);
    pages = [scanJpeg(120, 160), scanJpeg(160, 120, red: 30, blue: 230)];
    scan = (_) async => pages.length;
    readPage = (index) async => pages[index];
    finish = () async {};
    cancel = () async {};
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'scan') return scan(call);
      if (call.method == 'readPage') {
        return readPage((call.arguments as Map)['index'] as int);
      }
      if (call.method == 'finish') await finish();
      if (call.method == 'cancel') await cancel();
      return null;
    });
  });

  tearDown(() async {
    usage.fail = false;
    await cubit.close();
    await camera.close();
    await repository.close();
    await lease.release();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test(
    'batch pages persist in order with exact JPEG bytes and PDF pixels',
    () async {
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.error, isNull);
      expect(cubit.state.stage, ScannerStage.review);
      expect(cubit.state.capture, isNull);
      expect(cubit.state.draft!.pages, hasLength(2));
      expect(camera.pendingPageCount, 0);
      expect(calls.map((call) => call.method), [
        'scan',
        'readPage',
        'readPage',
        'finish',
      ]);
      expect((calls.first.arguments as Map)['maxPages'], 20);
      expect(lease.scratchBytes, 0);
      final pdfPages = <ScanPdfPage>[];
      final records = store.record!['pages'] as List;
      for (var index = 0; index < records.length; index++) {
        final record = records[index] as Map;
        final file = store.asset(store.record!, record['file'] as String);
        expect(await file.readAsBytes(), pages[index]);
        pdfPages.add(
          ScanPdfPage(
            file.path,
            record['width'] as int,
            record['height'] as int,
          ),
        );
      }
      final pdf = latin1.decode(await ScanPdfEncoder().encode(pdfPages));
      expect(pdf.indexOf(latin1.decode(pages[0])), greaterThanOrEqualTo(0));
      expect(
        pdf.indexOf(latin1.decode(pages[1])),
        greaterThan(pdf.indexOf(latin1.decode(pages[0]))),
      );
      final restored = ScanDraftStore(lease);
      await restored.initialize();
      expect(
        (await restored.snapshot()).pages.map(
          (page) => (page.width, page.height),
        ),
        [(120, 160), (160, 120)],
      );
      restored.release();
    },
  );

  test('native reads wait until the preceding page has committed', () async {
    readPage = (index) async {
      expect(store.record!['pages'], hasLength(index));
      return pages[index];
    };
    await cubit.restore();
    await cubit.addPage();
    expect(cubit.state.error, isNull);
    expect(cubit.state.draft!.pages, hasLength(2));
  });

  test(
    'cancelled native UI preserves the draft and permits another scan',
    () async {
      scan = (_) async => null;
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.error, isNull);
      expect(cubit.state.stage, ScannerStage.review);
      expect(cubit.state.draft!.pages, isEmpty);
      expect(camera.pendingPageCount, 0);
      expect(lease.scratchBytes, 0);
      scan = (_) async => pages.length;
      await cubit.addPage();
      expect(cubit.state.draft!.pages, hasLength(2));
    },
  );

  test('remaining draft capacity is sent to the native scanner', () async {
    await cubit.restore();
    await cubit.addPage();
    await cubit.addPage();
    expect(cubit.state.error, isNull);
    final scans = calls.where((call) => call.method == 'scan');
    expect(scans.map((call) => (call.arguments as Map)['maxPages']), [20, 18]);
    expect(cubit.state.draft!.pages, hasLength(4));
  });

  for (final count in [0, -1, 21]) {
    test('invalid native page count $count imports no partial batch', () async {
      await cubit.restore();
      scan = (_) async => count;
      await cubit.addPage();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.draft!.pages, isEmpty);
      expect(calls.where((call) => call.method == 'readPage'), isEmpty);
      expect(camera.pendingPageCount, 0);
      expect(lease.scratchBytes, 0);
    });
  }

  test('batch over remaining capacity preserves already saved pages', () async {
    await cubit.restore();
    await cubit.addPage();
    scan = (_) async => 19;
    await cubit.addPage();
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.draft!.pages, hasLength(2));
    expect(calls.where((call) => call.method == 'readPage'), hasLength(2));
    expect(camera.pendingPageCount, 0);
    expect(lease.scratchBytes, 0);
  });

  test(
    'failed local save retains one capture and retries without duplication',
    () async {
      readPage = (index) async {
        if (index == 1) usage.fail = true;
        return pages[index];
      };
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.draft!.pages, hasLength(1));
      expect(cubit.state.capture!.processed, isTrue);
      expect(camera.pendingPageCount, 1);
      final captureId = cubit.state.capture!.id;
      usage.fail = false;
      await cubit.keepPage();
      expect(cubit.state.error, isNull);
      expect(cubit.state.draft!.pages, hasLength(2));
      expect(cubit.state.capture, isNull);
      expect(
        ((store.record!['pages'] as List).last as Map)['sourceCaptureId'],
        captureId,
      );
      expect(calls.where((call) => call.method == 'readPage'), hasLength(2));
      expect(camera.pendingPageCount, 0);
      expect(lease.scratchBytes, 0);
    },
  );

  test(
    'failed page read resumes the same batch and blocks upload and new capture',
    () async {
      var failRead = true;
      readPage = (index) async {
        if (index == 1 && failRead) {
          throw PlatformException(code: 'scan_read_failed');
        }
        return pages[index];
      };
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.draft!.pages, hasLength(1));
      expect(cubit.state.capture, isNull);
      expect(cubit.state.pendingPages, 1);
      expect(cubit.state.error, isNotNull);
      await cubit.submit();
      await cubit.addPage();
      expect(calls.where((call) => call.method == 'scan'), hasLength(1));
      failRead = false;
      await cubit.retryPendingPages();
      expect(cubit.state.error, isNull);
      expect(cubit.state.draft!.pages, hasLength(2));
      expect(cubit.state.pendingPages, 0);
      expect(
        calls
            .where((call) => call.method == 'readPage')
            .map((call) => (call.arguments as Map)['index']),
        [0, 1, 1],
      );
      expect(lease.scratchBytes, 0);
    },
  );

  test('discarding pending pages preserves committed pages and releases camera handoff', () async {
    readPage = (index) async {
      if (index == 1) throw PlatformException(code: 'scan_read_failed');
      return pages[index];
    };
    await cubit.restore();
    await cubit.addPage();
    var handedOff = false;
    final handoff = coordinator.acquireCamera().then((release) {
      handedOff = true;
      release();
    });
    await Future<void>.delayed(Duration.zero);
    expect(handedOff, isFalse);
    await cubit.discardPendingPages();
    await handoff.timeout(const Duration(seconds: 2));
    expect(cubit.state.draft!.pages, hasLength(1));
    expect(cubit.state.pendingPages, 0);
    expect(cubit.state.capture, isNull);
    expect(camera.pendingPageCount, 0);
    expect(lease.scratchBytes, 0);
    final restored = ScanDraftStore(lease);
    await restored.initialize();
    expect((await restored.snapshot()).pages, hasLength(1));
    restored.release();
  });

  test('commit retry and duplicate release keep the same page until acknowledgement', () async {
    await repository.restore();
    await camera.start();
    await camera.beginBatch(maxPages: 20);
    final capture = await camera.captureNextPage();
    await repository.keepPage(capture, capture.corners);
    await camera.releaseCapture(capture.id);
    expect(camera.pendingPageCount, 2);
    final retry = await camera.captureNextPage();
    expect(retry.id, capture.id);
    final draft = await repository.keepPage(retry, retry.corners);
    expect(draft.pages, hasLength(1));
    await camera.acknowledgePage(capture.id);
    await camera.acknowledgePage(capture.id);
    expect(camera.pendingPageCount, 1);
    final next = await camera.captureNextPage();
    expect(next.id, isNot(capture.id));
    await camera.discardPendingPages();
    expect((await repository.restore()).pages, hasLength(1));
    expect(lease.scratchBytes, 0);
  });

  test(
    'failed native discard keeps pending pages available for another attempt',
    () async {
      readPage = (_) async => throw PlatformException(code: 'scan_read_failed');
      await cubit.restore();
      await cubit.addPage();
      cancel = () async => throw PlatformException(code: 'scan_busy');
      await cubit.discardPendingPages();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.pendingPages, 2);
      expect(camera.pendingPageCount, 2);
      cancel = () async {};
      await cubit.discardPendingPages();
      expect(cubit.state.error, isNull);
      expect(cubit.state.pendingPages, 0);
      expect(cubit.state.draft!.pages, isEmpty);
      expect(lease.scratchBytes, 0);
    },
  );

  test('normal background and resume do not cancel native scanning', () async {
    final entered = Completer<void>();
    final pending = Completer<int?>();
    scan = (_) {
      entered.complete();
      return pending.future;
    };
    await cubit.restore();
    final adding = cubit.addPage();
    await entered.future;
    final background = cubit.setForeground(false);
    final foreground = cubit.setForeground(true);
    expect(calls.where((call) => call.method == 'cancel'), isEmpty);
    pending.complete(pages.length);
    await Future.wait([adding, background, foreground]);
    expect(cubit.state.error, isNull);
    expect(cubit.state.draft!.pages, hasLength(2));
  });

  test('native finish failure retries cleanup without recapturing or duplicating the page', () async {
    pages = [pages.first];
    var failFinish = true;
    finish = () async {
      if (failFinish) throw PlatformException(code: 'scan_busy');
    };
    await cubit.restore();
    await cubit.addPage();
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.draft!.pages, hasLength(1));
    expect(cubit.state.pendingPages, 1);
    expect(cubit.state.capture, isNotNull);
    failFinish = false;
    await cubit.keepPage();
    expect(cubit.state.error, isNull);
    expect(cubit.state.draft!.pages, hasLength(1));
    expect(cubit.state.pendingPages, 0);
    expect(cubit.state.capture, isNull);
    expect(calls.where((call) => call.method == 'readPage'), hasLength(1));
    expect(calls.where((call) => call.method == 'finish'), hasLength(2));
    expect(lease.scratchBytes, 0);
  });

  test(
    'closing rejects a late native result and releases the camera lease',
    () async {
      final entered = Completer<void>();
      final pending = Completer<int?>();
      scan = (_) {
        entered.complete();
        return pending.future;
      };
      await cubit.restore();
      final adding = cubit.addPage();
      await entered.future;
      await cubit.close();
      await Future<void>.delayed(Duration.zero);
      final cancel = calls.singleWhere((call) => call.method == 'cancel');
      expect(
        (cancel.arguments as Map)['id'],
        (calls.first.arguments as Map)['id'],
      );
      pending.complete(pages.length);
      await adding;
      await camera.close();
      expect(store.record!['pages'], isEmpty);
      expect(lease.scratchBytes, 0);
      final release = await coordinator.acquireCamera().timeout(
        const Duration(seconds: 2),
      );
      release();
    },
  );

  for (final failure in ['corrupt', 'oversize', 'pixels']) {
    test('$failure page cannot enter the draft', () async {
      readPage = (_) async {
        if (failure == 'corrupt') return Uint8List.fromList([1, 2, 3]);
        if (failure == 'oversize') {
          return Uint8List(ScanImageLimits.maxPageBytes + 1);
        }
        final bytes = Uint8List.fromList(pages.first);
        for (var index = 0; index < bytes.length - 8; index++) {
          if (bytes[index] == 0xff && bytes[index + 1] == 0xc0) {
            bytes[index + 5] = 0x27;
            bytes[index + 6] = 0x10;
            bytes[index + 7] = 0x27;
            bytes[index + 8] = 0x10;
            return bytes;
          }
        }
        throw StateError('Fixture has no JPEG frame header');
      };
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.draft!.pages, isEmpty);
      expect(camera.pendingPageCount, 2);
      await camera.discardPendingPages();
      expect(camera.pendingPageCount, 0);
      expect(lease.scratchBytes, 0);
    });
  }

  test(
    'iOS permission guidance does not reveal SDK details or Google advice',
    () async {
      scan = (_) async => throw PlatformException(
        code: 'scan_permission_denied',
        message: 'private SDK detail',
      );
      await cubit.restore();
      await cubit.addPage();
      expect(cubit.state.error, contains('Settings'));
      expect(cubit.state.error, isNot(contains('Google')));
      expect(cubit.state.error, isNot(contains('private SDK detail')));
      expect(cubit.state.draft!.pages, isEmpty);
      expect(lease.scratchBytes, 0);
    },
  );
}

final class _FailingScanStorageUsage extends ScanStorageUsage {
  bool fail = false;
  @override
  Future<int> bytes(Directory directory, {required bool includeScratch}) {
    if (fail) throw const FileSystemException('Fixture storage failure');
    return super.bytes(directory, includeScratch: includeScratch);
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
