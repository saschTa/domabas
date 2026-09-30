import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/presentation/document/models/document_previews.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/document_thumbnail_fixture.dart';

final _png = File('../scripts/testing/fixtures/invoice.png').readAsBytesSync();
final _jpeg = documentThumbnailBytes(_png);
Document _document(String id) => Document(
  id: id,
  title: id,
  description: '',
  createdAt: DateTime.utc(2026),
  thumbnail: documentThumbnailFixture(_jpeg),
  file: DocumentFile(
    originalFilename: 'image.png',
    mediaType: 'image/png',
    size: _png.length,
    sha256: id,
    ingestedAt: DateTime.utc(2026),
    uploaderId: 'user',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('50 megapixel images decode to a bounded preview', () async {
    final bytes = File('test/fixtures/image-50mp.png').readAsBytesSync();
    final image = await decodeDocumentImage(bytes, longestEdge: 256);
    try {
      expect((image.width, image.height), (256, 128));
    } finally {
      image.dispose();
    }
  });
  test(
    'oversized compressed headers are refused before invoking a codec',
    () async {
      final huge = Uint8List.fromList(_png.sublist(0, 24));
      final header = ByteData.sublistView(huge);
      header.setUint32(16, 10001);
      header.setUint32(20, 5000);
      await expectLater(
        decodeDocumentImage(huge, longestEdge: 256),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'admission',
            contains('50 million pixels'),
          ),
        ),
      );
      header.setUint32(16, 0xffffffff);
      header.setUint32(20, 1);
      await expectLater(
        decodeDocumentImage(huge, longestEdge: 256),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'admission',
            contains('50 million pixels'),
          ),
        ),
      );
    },
  );
  test('truncated and invalid headers fail before image allocation', () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([0xff, 0xd8, 0xff]),
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff]),
      _png.sublist(0, 23),
    ]) {
      await expectLater(
        decodeDocumentImage(bytes, longestEdge: 32),
        throwsFormatException,
      );
    }
  });

  test(
    'JPEG orientation preserves aspect ratio and longest-edge decode bound',
    () async {
      final jpeg = File('test/fixtures/invoice-small.jpg').readAsBytesSync();
      final ordinary = await decodeDocumentImage(jpeg, longestEdge: 48);
      expect((ordinary.width, ordinary.height), (48, 17));
      ordinary.dispose();
      final rotated = Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe1,
        0,
        34,
        0x45,
        0x78,
        0x69,
        0x66,
        0,
        0,
        0x4d,
        0x4d,
        0,
        42,
        0,
        0,
        0,
        8,
        0,
        1,
        1,
        0x12,
        0,
        3,
        0,
        0,
        0,
        1,
        0,
        6,
        0,
        0,
        0,
        0,
        0,
        0,
        0xff,
        0xe1,
        0,
        6,
        0x58,
        0x4d,
        0x50,
        0x21,
        ...jpeg.skip(2),
      ]);
      final image = await decodeDocumentImage(rotated, longestEdge: 48);
      expect((image.width, image.height), (17, 48));
      image.dispose();
    },
  );
  test('preview admission permits two combined jobs and skips cancelled queued work', () async {
    final repository = _PreviewRepository();
    final previews = DocumentPreviewCoordinator(repository);
    addTearDown(previews.close);
    final requests = List.generate(
      5,
      (index) => previews.request(_document('$index').thumbnailRef),
    );
    expect(repository.started, ['0', '1']);
    requests[2].cancel();
    repository.responses['0']!.completeError(
      const DocumentFailure(DocumentFailureKind.unavailable),
    );
    await requests[0].result.future;
    await Future<void>.delayed(Duration.zero);
    expect(repository.started, ['0', '1', '3']);
    previews.pause();
    await Future<void>.delayed(Duration.zero);
    expect(repository.cancelledIds, containsAll(['1', '3']));
    expect(repository.started, isNot(contains('4')));
    for (final request in requests) {
      expect(await request.result.future, isNull);
    }
    for (final pending in repository.responses.values) {
      if (!pending.isCompleted) pending.complete(Uint8List(0));
    }
  });

  test(
    'pause cancels active jobs and resume admits a fresh visible request',
    () async {
      final repository = _PreviewRepository();
      final previews = DocumentPreviewCoordinator(repository);
      addTearDown(previews.close);
      final old = previews.request(_document('old').thumbnailRef);
      previews.pause();
      expect(await old.result.future, isNull);
      repository.responses['old']!.complete(Uint8List(0));
      await Future<void>.delayed(Duration.zero);
      previews.resume();
      final fresh = previews.request(_document('fresh').thumbnailRef);
      expect(repository.started, ['old', 'fresh']);
      previews.close();
      expect(await fresh.result.future, isNull);
      repository.responses['fresh']!.complete(Uint8List(0));
    },
  );

  test('server JPEG decode is bounded and cached previews survive consumer disposal', () async {
    final repository = FakeDocumentRepository()..thumbnails['image'] = _jpeg;
    final previews = DocumentPreviewCoordinator(repository);
    addTearDown(previews.close);
    final first = await previews
        .request(_document('image').thumbnailRef)
        .result
        .future;
    expect(first, isNotNull);
    expect(first!.width, lessThanOrEqualTo(256));
    first.dispose();
    repository.failure = const DocumentFailure(DocumentFailureKind.unavailable);
    final cached = await previews
        .request(_document('image').thumbnailRef)
        .result
        .future;
    expect(cached, isNotNull);
    cached!.dispose();
    previews.evict('image');
    expect(
      await previews.request(_document('image').thumbnailRef).result.future,
      isNull,
    );
  });

  test(
    'corrupt image produces retryable preview failure and frees its slot',
    () async {
      final repository = FakeDocumentRepository()
        ..thumbnails['bad'] = Uint8List.fromList([0, 1, 2]);
      final previews = DocumentPreviewCoordinator(repository);
      addTearDown(previews.close);
      expect(
        await previews.request(_document('bad').thumbnailRef).result.future,
        isNull,
      );
      repository.thumbnails['bad'] = _jpeg;
      final retried = await previews
          .request(_document('bad').thumbnailRef)
          .result
          .future;
      expect(retried, isNotNull);
      retried!.dispose();
    },
  );
}

final class _PreviewRepository extends FakeDocumentRepository {
  final started = <String>[];
  final cancelledIds = <String>[];
  final responses = <String, Completer<Uint8List>>{};
  @override
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  }) {
    started.add(document.id);
    cancel?.then((_) => cancelledIds.add(document.id));
    return (responses[document.id] = Completer<Uint8List>()).future;
  }
}
