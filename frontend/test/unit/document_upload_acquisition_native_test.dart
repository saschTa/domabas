import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:domabas/data/document/datasources/document_upload_acquisition.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('domabas-upload-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('native handles defer opening, admit whole batches, and reject 19 plus 2 before retention', () async {
    final access = _Files();
    final source = NativeDocumentUploadAcquisition(files: access);
    addTearDown(source.dispose);
    final first = source.captureNativePaths(
      List.filled(19, '${temporary.path}/one.pdf'),
      reserve: (_) => true,
    );
    var called = false;
    final second = source.captureNativePaths(
      List.filled(2, '${temporary.path}/two.pdf'),
      reserve: (_) {
        called = true;
        return true;
      },
    );
    expect(first.candidates, hasLength(19));
    expect(second.candidates, isEmpty);
    expect(second.rejection, isNotNull);
    expect(called, isFalse);
    expect(access.opens, 0);
    source.release(first.candidates.map((candidate) => candidate.id));
    final admitted = source.captureNativePaths([
      '${temporary.path}/next.pdf',
    ], reserve: (_) => true);
    expect(admitted.candidates, hasLength(1));
  });

  test('real filesystem rejects disappeared files, directories and selected leaf symlinks', () async {
    final source = NativeDocumentUploadAcquisition();
    addTearDown(source.dispose);
    final file = File('${temporary.path}/original.pdf');
    await file.writeAsBytes([1, 2, 3]);
    final rejected = [
      temporary.path,
      '${temporary.path}/missing.pdf',
      'relative.pdf',
      'https://example.test/file.pdf',
    ];
    if (!Platform.isWindows) {
      final link = Link('${temporary.path}/link.pdf');
      await link.create(file.path);
      rejected.add(link.path);
    }
    for (final location in rejected) {
      final candidate = source
          .captureNativePaths([location], reserve: (_) => true)
          .candidates
          .single;
      await expectLater(
        source.read(candidate.id, Completer<void>().future),
        throwsA(isA<DocumentUploadReadException>()),
      );
      source.release([candidate.id]);
    }
    final candidate = source
        .captureNativePaths([file.path], reserve: (_) => true)
        .candidates
        .single;
    await file.delete();
    await expectLater(
      source.read(candidate.id, Completer<void>().future),
      throwsA(isA<DocumentUploadReadException>()),
    );
  });

  test('special native entries are rejected without opening them', () async {
    final access = _Files(type: FileSystemEntityType.pipe);
    final source = NativeDocumentUploadAcquisition(files: access);
    addTearDown(source.dispose);
    final candidate = source
        .captureNativePaths(['${temporary.path}/pipe'], reserve: (_) => true)
        .candidates
        .single;
    await expectLater(
      source.read(candidate.id, Completer<void>().future),
      throwsA(isA<DocumentUploadReadException>()),
    );
    expect(access.opens, 0);
  });

  for (final length in [documentUploadByteLimit, documentUploadByteLimit + 1]) {
    test(
      'one handle enforces exact $length byte boundary and reads at most 64 KiB per step',
      () async {
        final file = _File(length);
        final source = NativeDocumentUploadAcquisition(
          files: _Files(file: file),
        );
        addTearDown(source.dispose);
        final candidate = source
            .captureNativePaths([
              '${temporary.path}/sized.pdf',
            ], reserve: (_) => true)
            .candidates
            .single;
        final future = source.read(candidate.id, Completer<void>().future);
        if (length <= documentUploadByteLimit) {
          final bytes = await future;
          expect(bytes.length, length);
          expect(bytes.first, 7);
          expect(bytes.last, 7);
          expect(file.buffers, hasLength(2));
          expect(file.maximumChunk, lessThanOrEqualTo(documentUploadReadChunk));
        } else {
          await expectLater(
            future,
            throwsA(isA<DocumentUploadReadException>()),
          );
          expect(file.buffers, isEmpty);
        }
        expect(file.closed, 1);
      },
    );
  }

  for (final mode in ['shrink', 'grow', 'length']) {
    test(
      '$mode during an opened native read is rejected and closes the original handle',
      () async {
        final file = _File(100, change: mode);
        final source = NativeDocumentUploadAcquisition(
          files: _Files(file: file),
        );
        addTearDown(source.dispose);
        final candidate = source
            .captureNativePaths([
              '${temporary.path}/changing.pdf',
            ], reserve: (_) => true)
            .candidates
            .single;
        await expectLater(
          source.read(candidate.id, Completer<void>().future),
          throwsA(isA<DocumentUploadReadException>()),
        );
        expect(file.closed, 1);
      },
    );
  }

  test('native timeout reports promptly but does not free the read lease before late IO and close settle', () async {
    final file = _File(100, hold: true);
    final source = NativeDocumentUploadAcquisition(
      files: _Files(file: file),
      readTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(source.dispose);
    final candidates = source.captureNativePaths([
      '${temporary.path}/held.pdf',
      '${temporary.path}/next.pdf',
    ], reserve: (_) => true).candidates;
    final reported = Completer<String>();
    var settled = false;
    final read = source.read(
      candidates.first.id,
      Completer<void>().future,
      onReadFailure: reported.complete,
    );
    final assertion = expectLater(
      read,
      throwsA(isA<DocumentUploadReadException>()),
    ).then((_) => settled = true);
    await file.started.future;
    expect(await reported.future, contains('stopped responding'));
    expect(settled, isFalse);
    expect(file.closed, 0);
    await expectLater(
      source.read(candidates.last.id, Completer<void>().future),
      throwsA(isA<DocumentUploadReadException>()),
    );
    file.release.complete();
    await assertion;
    expect(file.closed, 1);
  });
}

final class _Files implements NativeDocumentUploadFiles {
  _Files({this.type = FileSystemEntityType.file, _File? file})
    : file = file ?? _File(3);
  final FileSystemEntityType type;
  final _File file;
  int opens = 0;
  @override
  Future<FileSystemEntityType> typeWithoutFollowingLinks(
    String location,
  ) async => type;
  @override
  Future<NativeDocumentUploadFile> open(String location) async {
    opens++;
    return file;
  }
}

final class _File implements NativeDocumentUploadFile {
  _File(this.size, {this.change, this.hold = false});
  final int size;
  final String? change;
  final bool hold;
  final started = Completer<void>(), release = Completer<void>();
  final buffers = <Uint8List>{};
  int offset = 0, closed = 0, maximumChunk = 0, lengths = 0;
  @override
  Future<int> length() async =>
      change == 'length' && lengths++ > 0 ? size + 1 : size;
  @override
  Future<int> readInto(Uint8List buffer, int start, int end) async {
    if (!started.isCompleted) started.complete();
    if (hold) await release.future;
    buffers.add(buffer);
    final count = end - start;
    if (count > maximumChunk) maximumChunk = count;
    if (change == 'shrink') return 0;
    if (offset == size) return change == 'grow' ? 1 : 0;
    buffer.fillRange(start, end, 7);
    offset += count;
    return count;
  }

  @override
  Future<void> close() async {
    closed++;
  }
}
