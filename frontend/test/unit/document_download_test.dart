import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/domain/document/interfaces/document_file_saver.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
  late _DownloadRepository repository;
  late _DocumentFileSaver saver;
  late DocumentCubit cubit;

  setUp(() {
    repository = _DownloadRepository()..records = [_record()];
    saver = _DocumentFileSaver();
    cubit = DocumentCubit(
      repository,
      id: 'original',
      capabilities: const DocumentCapabilities(read: true, download: true),
      fileSaver: saver,
      onUpdated: (_) {},
      onDeleted: (_) async {},
    );
  });
  tearDown(() => cubit.close());

  test(
    'saves the original filename and bytes without downloading twice',
    () async {
      await cubit.load();
      expect(repository.downloads, 1);
      await cubit.downloadOriginal();
      expect(repository.downloads, 1);
      expect(saver.file!.originalFilename, 'original.png');
      expect(saver.file!.mediaType, 'image/png');
      expect(saver.bytes, [1, 2, 3]);
      expect(cubit.state.downloading, isFalse);
    },
  );

  test(
    'email originals load on demand and repeated clicks save only once',
    () async {
      repository.records = [_record(email: true)];
      await cubit.load();
      expect(repository.downloads, 0);
      final pending = repository.pending = Completer<Uint8List>();
      final download = cubit.downloadOriginal();
      await cubit.downloadOriginal();
      expect(repository.downloads, 1);
      expect(cubit.state.downloading, isTrue);
      pending.complete(Uint8List.fromList([4, 5, 6]));
      await download;
      expect(saver.saves, 1);
      expect(saver.file!.originalFilename, 'original.eml');
      expect(saver.bytes, [4, 5, 6]);
    },
  );

  for (final close in [false, true]) {
    test(
      'pending download cannot save after ${close ? 'close' : 'deletion'}',
      () async {
        repository.records = [_record(email: true)];
        await cubit.load();
        final pending = repository.pending = Completer<Uint8List>();
        final download = cubit.downloadOriginal();
        if (close) {
          await cubit.close();
        } else {
          repository.records.clear();
          await cubit.refreshRemote();
        }
        pending.complete(Uint8List.fromList([1, 2, 3]));
        await download;
        expect(saver.saves, 0);
      },
    );
  }

  test(
    'save failure is retryable without fetching the original again',
    () async {
      await cubit.load();
      saver.fail = true;
      await cubit.downloadOriginal();
      expect(cubit.state.downloadError, contains('Could not save'));
      expect(cubit.canDownloadOriginal, isTrue);
      saver.fail = false;
      await cubit.downloadOriginal();
      expect(cubit.state.downloadError, isNull);
      expect(saver.saves, 2);
      expect(repository.downloads, 1);
    },
  );

  test(
    'download failure does not open a save dialog and can be retried',
    () async {
      repository.records = [_record(email: true)];
      await cubit.load();
      repository.fail = true;
      await cubit.downloadOriginal();
      expect(cubit.state.downloadError, isNotNull);
      expect(cubit.state.downloading, isFalse);
      expect(saver.saves, 0);
      repository.fail = false;
      await cubit.downloadOriginal();
      expect(cubit.state.downloadError, isNull);
      expect(saver.saves, 1);
    },
  );

  test(
    'download authority is required even when the method is called directly',
    () async {
      final restricted = DocumentCubit(
        repository,
        id: 'original',
        capabilities: const DocumentCapabilities(read: true),
        fileSaver: saver,
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      addTearDown(restricted.close);
      await restricted.load();
      await restricted.downloadOriginal();
      expect(restricted.canDownloadOriginal, isFalse);
      expect(repository.downloads, 0);
      expect(saver.saves, 0);
    },
  );
}

Document _record({bool email = false}) => Document(
  id: 'original',
  title: 'Original',
  description: '',
  createdAt: DateTime.utc(2026),
  file: DocumentFile(
    originalFilename: email ? 'original.eml' : 'original.png',
    mediaType: email ? 'message/rfc822' : 'image/png',
    size: 3,
    sha256: 'a' * 64,
    ingestedAt: DateTime.utc(2026),
    uploaderId: 'user',
  ),
);

final class _DownloadRepository extends FakeDocumentRepository {
  int downloads = 0;
  bool fail = false;
  Completer<Uint8List>? pending;

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) async {
    downloads++;
    if (fail) throw const DocumentFailure(DocumentFailureKind.unavailable);
    return pending?.future ?? Uint8List.fromList([1, 2, 3]);
  }
}

final class _DocumentFileSaver implements DocumentFileSaver {
  int saves = 0;
  bool fail = false;
  DocumentFile? file;
  Uint8List? bytes;

  @override
  Future<void> save(DocumentFile file, Uint8List bytes) async {
    saves++;
    if (fail) throw StateError('Save failed');
    this.file = file;
    this.bytes = bytes;
  }
}
