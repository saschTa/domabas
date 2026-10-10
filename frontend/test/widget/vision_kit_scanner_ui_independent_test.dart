import 'package:domabas/domain/scanner/interfaces/scanner_camera.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas/presentation/scanner/cubits/scanner_cubit.dart';
import 'package:domabas/presentation/scanner/views/scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scanner_fixtures.dart';

void main() {
  testWidgets(
    'iOS disclosure and pending retry remain usable on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final camera = _BatchScannerCamera();
      final cubit = ScannerCubit(
        camera: camera,
        repository: FixtureScanRepository(),
        allowed: true,
      );
      addTearDown(camera.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ScannerScreen(
            cubit: cubit,
            previewBuilder: (_) => const Text('Custom camera preview'),
            canReadDocuments: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(camera.systemCaptureNotice), findsOneWidget);
      expect(find.textContaining('Google receives'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('addScanPage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addScanPage')));
      await tester.pumpAndSettle();
      expect(cubit.state.pendingPages, 2);
      expect(cubit.state.capture, isNull);
      expect(find.text('Custom camera preview'), findsNothing);
      expect(find.byKey(const Key('retryPendingScans')), findsOneWidget);
      expect(find.byKey(const Key('discardPendingScans')), findsOneWidget);
      final add = find.byKey(const Key('addScanPage'));
      if (add.evaluate().isNotEmpty) {
        expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
      }
      camera.failRead = false;
      await tester.ensureVisible(find.byKey(const Key('retryPendingScans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('retryPendingScans')));
      await tester.pumpAndSettle();
      expect(cubit.state.pendingPages, 0);
      expect(cubit.state.draft!.pages, hasLength(2));
      expect(camera.begins, 1);
      expect(find.byKey(const Key('retryPendingScans')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'leaving with unread native pages warns even without an active capture',
    (tester) async {
      final camera = _BatchScannerCamera();
      final cubit = ScannerCubit(
        camera: camera,
        repository: FixtureScanRepository(),
        allowed: true,
      );
      addTearDown(camera.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ScannerScreen(
            cubit: cubit,
            previewBuilder: (_) => const SizedBox.shrink(),
            canReadDocuments: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addScanPage')));
      await tester.pumpAndSettle();
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.capture, isNull);
      expect(cubit.state.pendingPages, 2);
      await tester.tap(find.byKey(const Key('closeScanner')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Leave this scan?'), findsOneWidget);
      expect(find.textContaining('upload is in progress'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cubit.state.pendingPages, 2);
      expect(find.byKey(const Key('retryPendingScans')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _BatchScannerCamera extends FixtureScannerCamera
    implements ScannerBatchCamera, ScannerSystemCapture {
  _BatchScannerCamera() {
    usesSystemCapture = true;
  }

  @override
  String get systemCaptureNotice => 'Scanning uses Apple’s document scanner.';
  @override
  int pendingPageCount = 0;
  bool failRead = true;
  int begins = 0;
  ScanCapture? _active;

  @override
  Future<void> beginBatch({required int maxPages}) async {
    begins++;
    pendingPageCount = 2;
  }

  @override
  Future<ScanCapture> captureNextPage() async {
    if (failRead) {
      throw const ScanFailure(
        'Page could not be read. Retry the remaining scans.',
      );
    }
    return _active ??= ScanCapture(
      id: 'batch-$pendingPageCount',
      width: 200,
      height: 300,
      corners: ScanCorners.fullImage(),
      preview: scanJpeg(20, 30),
      processed: true,
    );
  }

  @override
  Future<void> acknowledgePage(String id) async {
    if (_active?.id != id) return;
    _active = null;
    pendingPageCount--;
  }

  @override
  Future<void> discardPendingPages() async {
    _active = null;
    pendingPageCount = 0;
  }
}
