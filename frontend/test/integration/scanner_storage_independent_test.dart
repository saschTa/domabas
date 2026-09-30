import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:domabas/data/document/datasources/document_upload_remote_data_source.dart';
import 'package:domabas/data/document/models/prepared_document_upload_metadata.dart';
import 'package:domabas/data/scanner/datasources/native_scanner_camera.dart';
import 'package:domabas/data/scanner/datasources/scan_draft_store.dart';
import 'package:domabas/data/scanner/datasources/scan_pdf_encoder.dart';
import 'package:domabas/data/scanner/datasources/scan_storage_coordinator.dart';
import 'package:domabas/data/scanner/repos/local_scan_draft_repository.dart';
import 'package:domabas/data/scanner/repos/scan_upload_data_port.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../integration_test/scanner_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ScanStorageCoordinator coordinator;
  final leases = <ScanStorageLease>[];
  final cameras = <NativeScannerCamera>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('domabas-scan-test-');
    coordinator = ScanStorageCoordinator(() async => root);
  });
  tearDown(() async {
    for (final camera in cameras) {
      await camera.close();
    }
    cameras.clear();
    for (final lease in leases) {
      await lease.release();
    }
    leases.clear();
    await root.delete(recursive: true);
  });
  Future<ScanDraftStore> open([String owner = 'owner-a']) async {
    final lease = await coordinator.acquire(owner);
    leases.add(lease);
    final store = ScanDraftStore(lease);
    await store.initialize();
    return store;
  }

  Future<void> addPage(
    ScanDraftStore store,
    String id,
    int width,
    int height, {
    int red = 230,
    int green = 30,
  }) async {
    final bytes = scanJpeg(width, height, red: red, green: green);
    final thumbnail = scanJpeg(100, 100, red: red, green: green);
    final page = <String, dynamic>{
      'id': id,
      'revision': (store.record!['revision'] as int) + 1,
      'width': width,
      'height': height,
    };
    store.describe(
      page,
      'file',
      await store.writeAsset('$id.jpg', bytes),
      bytes,
    );
    store.describe(
      page,
      'thumbnail',
      await store.writeAsset('$id-thumb.jpg', thumbnail),
      thumbnail,
    );
    final next = store.copy()..['revision'] = page['revision'];
    (next['pages'] as List).add(page);
    await store.commit(next);
  }

  LocalScanDraftRepository repository(ScanDraftStore store, _Upload upload) {
    final camera = NativeScannerCamera(store.lease);
    cameras.add(camera);
    return LocalScanDraftRepository(
      lease: store.lease,
      camera: camera,
      upload: upload,
      store: store,
      encoder: ScanPdfEncoder(),
    );
  }

  test('single authoritative manifest preserves raw invalid drafts, rejects corruption and missing assets', () async {
    final store = await open();
    final raw = scanProperties({
      'title': '\ud800',
      'tags': <String>['  raw ', '', 'DUP', 'dup'],
    });
    await store.commit(store.copy()..['properties'] = raw.values);
    await addPage(store, 'page-1', 120, 180);
    final restored = ScanDraftStore(store.lease);
    await restored.initialize();
    expect((await restored.snapshot()).properties.values, raw.values);
    await File('${store.lease.directory.path}/manifest.stage')
        .writeAsString(jsonEncode(store.record));
    await File('${store.lease.directory.path}/manifest.json')
        .writeAsString('{broken');
    final corrupt = ScanDraftStore(store.lease);
    await corrupt.initialize();
    expect((await corrupt.snapshot()).status, ScanDraftStatus.blocked);
    await store.commit(store.record!);
    await store
        .asset(
          store.record!,
          ((store.record!['pages'] as List).single as Map)['file'] as String,
        )
        .delete();
    final missing = ScanDraftStore(store.lease);
    await missing.initialize();
    expect((await missing.snapshot()).status, ScanDraftStatus.blocked);
  });
  test('missing primary with assets never restores an editable draft and explicit discard clears owned files', () async {
    final store = await open();
    await addPage(store, 'page-1', 120, 180);
    await File('${store.lease.directory.path}/manifest.json').delete();
    final blocked = ScanDraftStore(store.lease);
    final repo = repository(blocked, _Upload());
    expect((await repo.restore()).status, ScanDraftStatus.blocked);
    await repo.discard();
    expect(await store.lease.directory.list().toList(), isEmpty);
  });
  test('ordinary housekeeping preserves active correction input; cold restore removes orphan scratch', () async {
    final store = await open();
    final scratch = File('${store.lease.directory.path}/scratch-123-456.jpg');
    await scratch.writeAsBytes(scanJpeg(120, 180));
    await store.cleanupUnreferenced();
    expect(await scratch.exists(), isTrue);
    final restored = ScanDraftStore(store.lease);
    await restored.initialize();
    expect(await scratch.exists(), isFalse);
  });
  test('same-owner reopen waits for admitted commit; cancelled queued work cannot cross ownership', () async {
    final store = await open();
    final gate = Completer<void>(), entered = Completer<void>();
    final first = store.lease.run(() async {
      entered.complete();
      await gate.future;
      await store.commit(
        store.copy()
          ..['properties'] = scanProperties({'title': 'Admitted'}).values,
      );
    });
    await entered.future;
    final queued = store.lease.run(() async {
      fail('Cancelled queued operation ran');
    });
    final queuedCheck = expectLater(queued, throwsA(isA<ScanFailure>()));
    store.lease.cancelNewOperations();
    final release = store.lease.release();
    var reopened = false;
    final next = coordinator.acquire(store.lease.owner).then((lease) {
      reopened = true;
      leases.add(lease);
      return lease;
    });
    final other = await coordinator.acquire('other-account-and-namespace');
    leases.add(other);
    expect(other.directory.path, isNot(store.lease.directory.path));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reopened, isFalse);
    gate.complete();
    await first;
    await release;
    await queuedCheck;
    final nextStore = ScanDraftStore(await next);
    await nextStore.initialize();
    expect((await nextStore.snapshot()).properties.title, 'Admitted');
  });
  test('owner, scratch and global reservations account pending bytes and release idempotently', () async {
    final store = await open();
    final first = await store.lease.reserve(30 * 1024 * 1024);
    await expectLater(
      store.lease.reserve(11 * 1024 * 1024),
      throwsA(isA<ScanFailure>()),
    );
    first.release();
    first.release();
    final scratch = await store.lease.reserve(24 * 1024 * 1024, scratch: true);
    await expectLater(
      store.lease.reserve(1, scratch: true),
      throwsA(isA<ScanFailure>()),
    );
    scratch.release();
    final rootFile = await File('${root.path}/capacity.bin')
        .open(mode: FileMode.write);
    await rootFile.truncate(256 * 1024 * 1024 - 256 * 1024);
    await rootFile.close();
    await expectLater(store.lease.reserve(1), throwsA(isA<ScanFailure>()));
    await store.commit(
      store.copy()
        ..['properties'] = scanProperties({'title': 'Housekeeping at capacity'})
            .values,
    );
    expect(
      (await store.snapshot()).properties.title,
      'Housekeeping at capacity',
    );
  });
  test('reservation release cannot let an allocation miss both newly written disk bytes and pending bytes', () async {
    final usage = _GatedUsage();
    coordinator = ScanStorageCoordinator(() async => root, usage: usage);
    final store = await open();
    final pending = await store.lease.reserve(30 * 1024 * 1024);
    usage.gate = Completer<void>();
    final allocating = store.lease.reserve(15 * 1024 * 1024);
    final check = expectLater(allocating, throwsA(isA<ScanFailure>()));
    await usage.scanned.future;
    final file = await File('${store.lease.directory.path}/committed.pdf')
        .open(mode: FileMode.write);
    await file.truncate(30 * 1024 * 1024);
    await file.close();
    pending.release();
    usage.gate!.complete();
    await check;
    await expectLater(
      store.lease.reserve(15 * 1024 * 1024),
      throwsA(isA<ScanFailure>()),
    );
  });
  test('uncertain upload retries exact cached PDF/metadata across restart and blocks corrupted cache', () async {
    final store = await open();
    await addPage(store, 'one', 120, 180);
    await addPage(store, 'two', 180, 120, red: 20, green: 230);
    final upload = _Upload();
    final repo = repository(store, upload);
    await repo.restore();
    expect((await repo.submit()).draft.status, ScanDraftStatus.uncertain);
    final bytes = Uint8List.fromList(upload.pdfs.single);
    final metadata = Uint8List.fromList(upload.metadata.single);
    final reopened = ScanDraftStore(store.lease);
    final retry = repository(reopened, upload);
    await retry.restore();
    await expectLater(retry.movePage('two', 0), throwsA(isA<ScanFailure>()));
    expect((await retry.restore()).pages.map((page) => page.id), [
      'one',
      'two',
    ]);
    expect((await retry.retryUpload()).draft.status, ScanDraftStatus.uncertain);
    expect(upload.pdfs.last, bytes);
    expect(upload.metadata.last, metadata);
    final attempt = reopened.record!['attempt'] as Map<String, dynamic>;
    await reopened
        .asset(reopened.record!, attempt['pdf'] as String)
        .writeAsBytes(List.filled(bytes.length, 0));
    expect((await retry.retryUpload()).draft.status, ScanDraftStatus.blocked);
    expect(upload.pdfs, hasLength(2));
  });
  test('moves commit only order and revision, with final indices and unchanged assets', () async {
    final store = await open();
    for (final id in ['one', 'two', 'three']) {
      await addPage(store, id, 120, 180);
    }
    final next = store.copy();
    for (final page in next['pages'] as List) {
      (page as Map)['sourceCaptureId'] = 'capture-${page['id']}';
    }
    await store.commit(next);
    final repo = repository(store, _Upload());
    final original = await repo.restore();
    final originalPages = List<dynamic>.from(store.record!['pages'] as List);
    final manifest = File('${store.lease.directory.path}/manifest.json');
    final originalManifest = await manifest.readAsBytes();
    final files = await store.lease.directory.list().toList();
    final bytesByPath = <String, List<int>>{};
    for (final file in files.whereType<File>()) {
      if (file.path != manifest.path) {
        bytesByPath[file.path] = await file.readAsBytes();
      }
    }
    expect((await repo.movePage('one', 0)).revision, original.revision);
    await expectLater(repo.movePage('absent', 1), throwsA(isA<ScanFailure>()));
    await expectLater(repo.movePage('one', -1), throwsA(isA<ScanFailure>()));
    await expectLater(repo.movePage('one', 3), throwsA(isA<ScanFailure>()));
    expect(await manifest.readAsBytes(), originalManifest);
    final last = await repo.movePage('one', 2);
    expect(last.pages.map((page) => page.id), ['two', 'three', 'one']);
    expect(last.revision, original.revision + 1);
    final first = await repo.movePage('three', 0);
    expect(first.pages.map((page) => page.id), ['three', 'two', 'one']);
    expect(first.revision, original.revision + 2);
    expect(store.record!['pages'], [
      originalPages[2],
      originalPages[1],
      originalPages[0],
    ]);
    expect(store.record!['retired'], isEmpty);
    for (final entry in bytesByPath.entries) {
      expect(await File(entry.key).readAsBytes(), entry.value);
    }
    final reopened = repository(ScanDraftStore(store.lease), _Upload());
    final restored = await reopened.restore();
    expect(restored.pages.map((page) => page.id), ['three', 'two', 'one']);
    expect(restored.revision, first.revision);
  });
  test(
    'failed reorder commit or snapshot preserves the authoritative order',
    () async {
      final store = await open();
      await addPage(store, 'one', 120, 180);
      await addPage(store, 'two', 120, 180);
      final repo = repository(store, _Upload());
      await repo.restore();
      final manifest = File('${store.lease.directory.path}/manifest.json');
      final committed = await manifest.readAsBytes();
      final stage = await Directory(
        '${store.lease.directory.path}/manifest.stage',
      ).create();
      await expectLater(
        repo.movePage('two', 0),
        throwsA(isA<FileSystemException>()),
      );
      expect(await manifest.readAsBytes(), committed);
      expect((await repo.restore()).pages.map((page) => page.id), [
        'one',
        'two',
      ]);
      await stage.delete();
      final thumbnail = (store.record!['pages'] as List).first as Map;
      await store
          .asset(store.record!, thumbnail['thumbnail'] as String)
          .delete();
      await expectLater(
        repo.movePage('two', 0),
        throwsA(isA<FileSystemException>()),
      );
      expect(await manifest.readAsBytes(), committed);
      expect(
        (store.record!['pages'] as List).map((page) => (page as Map)['id']),
        ['one', 'two'],
      );
    },
  );
  test('queued moves check read-only state inside the storage lease', () async {
    final store = await open();
    await addPage(store, 'one', 120, 180);
    await addPage(store, 'two', 120, 180);
    final repo = repository(store, _Upload());
    await repo.restore();
    final gate = Completer<void>();
    final statusChange = store.lease.run(() async {
      await gate.future;
      await store.commit(store.copy()..['status'] = 'duplicate');
    });
    final moving = expectLater(
      repo.movePage('two', 0),
      throwsA(isA<ScanFailure>()),
    );
    gate.complete();
    await Future.wait([statusChange, moving]);
    expect(
      (store.record!['pages'] as List).map((page) => (page as Map)['id']),
      ['one', 'two'],
    );
    for (final status in ['uncertain', 'accepted']) {
      await store.commit(store.copy()..['status'] = status);
      await expectLater(repo.movePage('two', 0), throwsA(isA<ScanFailure>()));
    }
    await store.commit(store.copy()..['status'] = 'editable');
    store.blocked = true;
    await expectLater(repo.movePage('two', 0), throwsA(isA<ScanFailure>()));
  });
  test('late acceptance finalizes admitted attempt after scope cancellation without another upload', () async {
    final store = await open();
    await addPage(store, 'one', 120, 180);
    final upload = _Upload()..gate = Completer<Document>();
    final repo = repository(store, upload);
    await repo.restore();
    final submitting = repo.submit();
    await upload.sent.future;
    repo.cancelNewOperations();
    final closing = repo.close();
    upload.gate!.complete(_document());
    final result = await submitting;
    await closing;
    expect(result.accepted, isTrue);
    expect(upload.pdfs, hasLength(1));
    expect(await store.lease.directory.list().toList(), isEmpty);
  });
  test('persisted acceptance resumes cleanup after process restart, including empty retired list', () async {
    for (final withRetired in [true, false]) {
      final store = await open('accepted-$withRetired');
      final retired = <String>[];
      if (withRetired) {
        retired.add(
          await store.writeAsset('retired.pdf', Uint8List.fromList([1, 2, 3])),
        );
      }
      await store.commit(
        store.copy()
          ..['status'] = 'accepted'
          ..['acceptedDocumentId'] = _document().id
          ..['retired'] = retired,
      );
      final freshCoordinator = ScanStorageCoordinator(() async => root);
      await store.lease.release();
      final lease = await freshCoordinator.acquire(store.lease.owner);
      leases.add(lease);
      final recovered = ScanDraftStore(lease);
      final upload = _Upload();
      final repo = repository(recovered, upload);
      expect((await repo.restore()).status, ScanDraftStatus.accepted);
      expect(upload.pdfs, isEmpty);
      expect(await lease.directory.list().toList(), isEmpty);
      await lease.release();
      final fresh = await freshCoordinator.acquire(store.lease.owner);
      leases.add(fresh);
      final newStore = ScanDraftStore(fresh);
      await newStore.initialize();
      expect((await newStore.snapshot()).status, ScanDraftStatus.editable);
      expect(newStore.record!['id'], isNot(store.record!['id']));
    }
  });
  test('known acceptance survives tombstone write failure and owner handoff without resubmission', () async {
    final store = await open();
    await addPage(store, 'one', 120, 180);
    final upload = _Upload()..gate = Completer<Document>();
    final repo = repository(store, upload);
    await repo.restore();
    final sending = repo.submit();
    await upload.sent.future;
    final obstruction = await Directory(
      '${store.lease.directory.path}/manifest.stage',
    ).create();
    upload.gate!.complete(_document());
    final accepted = await sending;
    expect(accepted.accepted, isTrue);
    expect(accepted.draft.cleanupPending, isTrue);
    expect(store.record!['status'], 'uncertain');
    await repo.close();
    await store.lease.release();
    final newLease = await coordinator.acquire(store.lease.owner);
    leases.add(newLease);
    final nextStore = ScanDraftStore(newLease), nextUpload = _Upload();
    final next = repository(nextStore, nextUpload);
    final recovered = await next.restore();
    expect(recovered.status, ScanDraftStatus.accepted);
    expect(recovered.cleanupPending, isTrue);
    await expectLater(next.retryUpload(), throwsA(isA<ScanFailure>()));
    await obstruction.delete();
    expect((await next.retryCleanup()).cleanupPending, isFalse);
    expect(nextUpload.pdfs, isEmpty);
    expect(upload.pdfs, hasLength(1));
    expect(await newLease.directory.list().toList(), isEmpty);
  });
  test('committed source capture identity prevents duplicate page after presentation read failure', () async {
    final store = await open();
    await addPage(store, 'one', 120, 180);
    final next = store.copy();
    ((next['pages'] as List).single as Map)['sourceCaptureId'] =
        'known-capture';
    await store.commit(next);
    final repo = repository(store, _Upload());
    await repo.restore();
    final result = await repo.keepPage(
      ScanCapture(
        id: 'known-capture',
        width: 120,
        height: 180,
        corners: ScanCorners.fullImage(),
        preview: scanJpeg(120, 180),
      ),
      ScanCorners.fullImage(),
    );
    expect(result.pages, hasLength(1));
    expect(result.pages.single.id, 'one');
  });
  test('reordered retained pages survive reopen and produce the uploaded PDF in saved order', () async {
    final store = await open();
    await addPage(store, 'red-portrait', 200, 300);
    await addPage(store, 'removed-middle', 200, 200, red: 20, green: 20);
    await addPage(store, 'green-landscape', 400, 200, red: 20, green: 230);
    final repo = repository(store, _Upload());
    await repo.restore();
    await repo.removePage('removed-middle');
    await repo.movePage('green-landscape', 0);
    final upload = _Upload();
    final reopened = repository(ScanDraftStore(store.lease), upload);
    expect((await reopened.restore()).pages.map((page) => page.id), [
      'green-landscape',
      'red-portrait',
    ]);
    await reopened.submit();
    final pdf = upload.pdfs.single;
    final file = File('${root.path}/verified.pdf');
    await file.writeAsBytes(pdf);
    late ProcessResult info;
    try {
      info = await Process.run('pdfinfo', ['-f', '1', '-l', '2', file.path]);
      await Process.run('pdftoppm', ['-v']);
    } on ProcessException {
      markTestSkipped('Poppler is unavailable; encoder still executed');
      return;
    }
    expect(info.exitCode, 0);
    expect(info.stdout, contains('Pages:           2'));
    expect(info.stdout, matches(r'Page\s+1 size:\s+842 x 421'));
    expect(info.stdout, matches(r'Page\s+2 size:\s+561\.\d+ x 842'));
    final raster = await Process.run('pdftoppm', [
      '-scale-to',
      '300',
      '-png',
      file.path,
      '${root.path}/page',
    ]);
    expect(raster.exitCode, 0);
    final red = img.decodePng(
      await File('${root.path}/page-2.png').readAsBytes(),
    )!;
    final green = img.decodePng(
      await File('${root.path}/page-1.png').readAsBytes(),
    )!;
    expect(red.width / red.height, closeTo(2 / 3, .01));
    expect(green.width / green.height, closeTo(2, .01));
    expect(red.getPixel(red.width ~/ 2, red.height ~/ 2).r, greaterThan(200));
    expect(red.getPixel(red.width ~/ 2, red.height ~/ 2).g, lessThan(60));
    expect(
      green.getPixel(green.width ~/ 2, green.height ~/ 2).g,
      greaterThan(200),
    );
    expect(green.getPixel(green.width ~/ 2, green.height ~/ 2).r, lessThan(60));
    final evidencePath = Platform.environment['SCANNER_TEST_EVIDENCE_DIR'];
    if (evidencePath != null) {
      final evidence = await Directory(evidencePath).create(recursive: true);
      await file.copy('${evidence.path}/retained-pages.pdf');
      for (final page in [1, 2]) {
        await File('${root.path}/page-$page.png')
            .copy('${evidence.path}/retained-page-$page.png');
      }
      await File('${evidence.path}/pdfinfo.txt')
          .writeAsString('${info.stdout}');
    }
  });
}

Document _document() => Document(
  id: 'c70a9c09-efcc-4210-830c-b73c408ac2ae',
  title: 'Accepted scan',
  description: '',
  createdAt: DateTime.utc(2026, 9, 18),
);

final class _Upload implements ScanUploadDataPort {
  final pdfs = <Uint8List>[], metadata = <Uint8List>[];
  final sent = Completer<void>();
  Completer<Document>? gate;
  @override
  PreparedDocumentUploadMetadata prepare(DocumentProperties value) {
    final client = api.ApiClient();
    try {
      return DocumentUploadRemoteDataSource(client).prepare(value);
    } finally {
      client.client.close();
    }
  }

  @override
  Future<Document> send(
    Uint8List pdf,
    PreparedDocumentUploadMetadata value,
    String filename,
    Future<void> cancel,
  ) async {
    pdfs.add(Uint8List.fromList(pdf));
    metadata.add(Uint8List.fromList(value.bytes));
    if (!sent.isCompleted) sent.complete();
    if (gate != null) return gate!.future;
    throw const DocumentUploadException(
      DocumentUploadDisposition.uncertain,
      'Unknown result',
    );
  }
}

final class _GatedUsage extends ScanStorageUsage {
  final scanned = Completer<void>();
  Completer<void>? gate;
  @override
  Future<int> bytes(Directory directory, {required bool includeScratch}) async {
    final result = await super.bytes(directory, includeScratch: includeScratch);
    if (!includeScratch && gate != null && !gate!.isCompleted) {
      scanned.complete();
      await gate!.future;
    }
    return result;
  }
}
