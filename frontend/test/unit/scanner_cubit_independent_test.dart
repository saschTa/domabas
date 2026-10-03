import 'dart:async';

import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas/presentation/scanner/cubits/scanner_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scanner_fixtures.dart';

void main() {
  late FixtureScannerCamera camera;
  late FixtureScanRepository repository;
  late ScannerCubit cubit;
  setUp(() {
    camera = FixtureScannerCamera();
    repository = FixtureScanRepository();
    cubit = ScannerCubit(camera: camera, repository: repository, allowed: true);
  });
  tearDown(() async {
    await cubit.close();
    await camera.close();
  });
  Future<void> page() async {
    await cubit.restore();
    await cubit.addPage();
    await cubit.capture();
    await cubit.keepPage();
  }

  for (var edge = 0; edge < 4; edge++) {
    test(
      'edge $edge moves both endpoints and preserves its slope at image bounds',
      () async {
        await cubit.restore();
        await cubit.addPage();
        await cubit.capture();
        const original = [
          ScanPoint(.15, .1),
          ScanPoint(.85, .2),
          ScanPoint(.8, .9),
          ScanPoint(.2, .8),
        ];
        for (var i = 0; i < 4; i++) {
          cubit.moveCorner(i, original[i]);
        }
        final next = (edge + 1) % 4;
        final first = original[edge], second = original[next];
        cubit.moveEdge(
          edge,
          ScanPoint(
            (first.x + second.x) / 2 + .03,
            (first.y + second.y) / 2 + .04,
          ),
        );
        final moved = cubit.state.corners!.points;
        for (var i = 0; i < 4; i++) {
          if (i == edge || i == next) {
            expect(moved[i].x, closeTo(original[i].x + .03, 1e-9));
            expect(moved[i].y, closeTo(original[i].y + .04, 1e-9));
          } else {
            expect(moved[i].x, original[i].x);
            expect(moved[i].y, original[i].y);
          }
        }
        for (final target in [
          const ScanPoint(-10, 10),
          const ScanPoint(10, -10),
        ]) {
          cubit.moveEdge(edge, target);
          final bounded = cubit.state.corners!.points;
          expect(
            bounded.every((p) => p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1),
            isTrue,
          );
          expect(
            bounded[next].x - bounded[edge].x,
            closeTo(second.x - first.x, 1e-9),
          );
          expect(
            bounded[next].y - bounded[edge].y,
            closeTo(second.y - first.y, 1e-9),
          );
          expect([
            bounded[edge].x,
            bounded[next].x,
          ], contains(closeTo(target.x < 0 ? 0 : 1, 1e-9)));
          expect([
            bounded[edge].y,
            bounded[next].y,
          ], contains(closeTo(target.y < 0 ? 0 : 1, 1e-9)));
        }
      },
    );
  }

  test(
    'edge edits reject invalid input, other stages and in-flight page saves',
    () async {
      await cubit.restore();
      final review = cubit.state;
      cubit.moveEdge(0, const ScanPoint(.5, .2));
      expect(cubit.state, same(review));
      await cubit.addPage();
      await cubit.capture();
      final correction = cubit.state;
      cubit.moveEdge(-1, const ScanPoint(.5, .2));
      cubit.moveEdge(4, const ScanPoint(.5, .2));
      cubit.moveEdge(0, const ScanPoint(double.nan, .2));
      cubit.moveEdge(0, const ScanPoint(.5, double.infinity));
      expect(cubit.state, same(correction));
      repository.saveGate = Completer<void>();
      cubit.setProperties(scanProperties({'title': 'Saving page'}));
      final keeping = cubit.keepPage();
      final corners = cubit.state.corners;
      cubit.moveEdge(0, const ScanPoint(.5, .2));
      expect(cubit.state.corners, same(corners));
      repository.saveGate!.complete();
      await keeping;
    },
  );

  test('upload permission gates every public operation before camera or repository admission', () async {
    await cubit.close();
    cubit = ScannerCubit(
      camera: camera,
      repository: repository,
      allowed: false,
    );
    await cubit.restore();
    await cubit.addPage();
    await cubit.capture();
    await cubit.submit();
    await cubit.retryUpload();
    await cubit.retryCleanup();
    await cubit.movePage('one', 0);
    cubit.setProperties(scanProperties({'title': 'Forbidden'}));
    expect(repository.restores, 0);
    expect(repository.saves, 0);
    expect(repository.submissions, 0);
    expect(repository.moves, 0);
    expect(camera.starts, 0);
    expect(cubit.state.error, contains('permission'));
  });
  test(
    'page moves wait for pending saves and block overlapping operations',
    () async {
      await page();
      await page();
      await page();
      repository.saveGate = Completer<void>();
      cubit.setProperties(scanProperties({'title': 'Reordered document'}));
      final moving = cubit.movePage('capture-1', 2);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.busy, isTrue);
      expect(repository.moves, 0);
      expect(cubit.state.draft!.pages.map((page) => page.id), [
        'capture-1',
        'capture-2',
        'capture-3',
      ]);
      await cubit.movePage('capture-2', 0);
      await cubit.removePage('capture-3');
      await cubit.submit();
      expect(repository.submissions, 0);
      repository.saveGate!.complete();
      await moving;
      expect(repository.moves, 1);
      expect(cubit.state.draft!.pages.map((page) => page.id), [
        'capture-2',
        'capture-3',
        'capture-1',
      ]);
      expect(cubit.state.draft!.properties.title, 'Reordered document');
      expect(cubit.state.properties!.title, 'Reordered document');
      expect(cubit.state.dirty, isFalse);
      expect(cubit.state.busy, isFalse);
      await cubit.movePage('capture-1', 2);
      await cubit.movePage('missing', 0);
      await cubit.movePage('capture-1', -1);
      await cubit.movePage('capture-1', 3);
      expect(repository.moves, 1);
    },
  );
  test(
    'failed page move retains the committed order and can be retried',
    () async {
      await page();
      await page();
      final committed = cubit.state.draft;
      repository.failMove = true;
      await cubit.movePage('capture-2', 0);
      expect(cubit.state.draft, same(committed));
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.error, 'Page order could not be saved.');
      repository.failMove = false;
      await cubit.movePage('capture-2', 0);
      expect(cubit.state.draft!.pages.first.id, 'capture-2');
      expect(cubit.state.error, isNull);
    },
  );
  for (final status in [
    ScanDraftStatus.uncertain,
    ScanDraftStatus.duplicate,
    ScanDraftStatus.blocked,
    ScanDraftStatus.accepted,
  ]) {
    test('$status draft cannot reorder pages', () async {
      repository.draft = ScanDraft(
        id: 'readonly',
        revision: 1,
        properties: scanProperties(),
        status: status,
        pages: [
          ScanPage(
            id: 'one',
            width: 200,
            height: 300,
            thumbnail: scanJpeg(20, 30),
          ),
          ScanPage(
            id: 'two',
            width: 200,
            height: 300,
            thumbnail: scanJpeg(20, 30),
          ),
        ],
      );
      await cubit.restore();
      await cubit.movePage('two', 0);
      expect(repository.moves, 0);
      expect(cubit.state.draft!.pages.first.id, 'one');
    });
  }
  test('inactive/resumed during camera initialize reconciles final foreground state', () async {
    await cubit.restore();
    camera.startGate = Completer<void>();
    final starting = cubit.addPage();
    await Future<void>.delayed(Duration.zero);
    final inactive = cubit.setForeground(false),
        resumed = cubit.setForeground(true);
    camera.startGate!.complete();
    await Future.wait([starting, inactive, resumed]);
    expect(cubit.state.camera.status, ScanCameraStatus.ready);
    expect(cubit.state.busy, isFalse);
    expect(camera.starts, 2);
  });
  test('capture pending through background preserves correction input and serialization', () async {
    await cubit.restore();
    await cubit.addPage();
    camera.captureGate = Completer<ScanCapture>();
    final taking = cubit.capture();
    await cubit.capture();
    await cubit.setForeground(false);
    await cubit.setForeground(true);
    camera.captureGate!.complete(
      ScanCapture(
        id: 'pending',
        width: 200,
        height: 300,
        corners: ScanCorners.fullImage(),
        preview: scanJpeg(200, 300),
      ),
    );
    await taking;
    expect(camera.captures, 1);
    expect(cubit.state.stage, ScannerStage.correction);
    expect(cubit.state.capture!.id, 'pending');
    expect(camera.releases, 0);
    await cubit.keepPage();
    expect(cubit.state.draft!.pages, hasLength(1));
    expect(cubit.state.capture, isNull);
  });
  test('cancel during property flush prevents dispatch and leaves another upload possible', () async {
    await page();
    repository.saveGate = Completer<void>();
    cubit.setProperties(scanProperties({'title': 'Latest edit'}));
    final sending = cubit.submit();
    await Future<void>.delayed(Duration.zero);
    cubit.cancelUpload();
    repository.saveGate!.complete();
    await sending;
    expect(repository.submissions, 0);
    expect(cubit.state.properties!.title, 'Latest edit');
    expect(cubit.state.dirty, isFalse);
    repository.uploadGate = Completer<ScanSubmission>();
    final retry = cubit.submit();
    await Future<void>.delayed(Duration.zero);
    expect(repository.submissions, 1);
    repository.uploadGate!.complete(
      ScanSubmission(
        ScanDraft(
          id: 'fixture',
          revision: 2,
          properties: repository.draft.properties,
          status: ScanDraftStatus.uncertain,
        ),
      ),
    );
    await retry;
    expect(cubit.state.draft!.status, ScanDraftStatus.uncertain);
  });
  test('decoded acceptance wins cancellation, notifies once, and never notifies closed view', () async {
    var accepted = 0;
    await cubit.close();
    cubit = ScannerCubit(
      camera: camera,
      repository: repository,
      allowed: true,
      onAccepted: () => accepted++,
    );
    await page();
    repository.uploadGate = Completer<ScanSubmission>();
    final sending = cubit.submit();
    await Future<void>.delayed(Duration.zero);
    cubit.cancelUpload();
    repository.uploadGate!.complete(
      ScanSubmission(
        ScanDraft(
          id: 'fixture',
          revision: 2,
          properties: repository.draft.properties,
          status: ScanDraftStatus.accepted,
          acceptedDocumentId: 'accepted',
        ),
      ),
    );
    await sending;
    expect(accepted, 1);
    expect(cubit.state.draft!.status, ScanDraftStatus.accepted);
    await cubit.retryUpload();
    expect(repository.submissions, 1);
    await cubit.close();
    expect(cubit.state.draft, isNull);
    expect(repository.cancelled, isTrue);
  });
  test(
    'raw edits coalesce and newer properties survive an older in-flight save',
    () async {
      await cubit.restore();
      repository.saveGate = Completer<void>();
      cubit.setProperties(scanProperties({'title': 'First'}));
      final saving = cubit.flushProperties();
      await Future<void>.delayed(Duration.zero);
      cubit.setProperties(
        scanProperties({
          'title': 'Newest',
          'tags': <String>['raw ', '', 'DUP'],
        }),
      );
      repository.saveGate!.complete();
      expect(await saving, isTrue);
      expect(repository.saves, 2);
      expect(repository.draft.properties.title, 'Newest');
      expect(repository.draft.properties.tags, ['raw ', '', 'DUP']);
      expect(cubit.state.dirty, isFalse);
    },
  );
}
