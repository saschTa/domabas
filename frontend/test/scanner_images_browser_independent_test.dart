import 'dart:typed_data';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/scanner/interfaces/scan_draft_repository.dart';
import 'package:domabas/domain/scanner/interfaces/scanner_camera.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas/presentation/scanner/cubits/scanner_cubit.dart';
import 'package:domabas/presentation/scanner/views/scanner_screen.dart';
import 'package:domabas/presentation/scanner/widgets/scan_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets(
    'immutable scan bytes render on the browser and image providers survive corner/theme rebuilds',
    (tester) async {
      final source = img.Image(width: 120, height: 180);
      img.fill(source, color: img.ColorRgb8(220, 30, 40));
      final bytes = img.encodeJpg(source);
      final camera = _Camera(bytes);
      final repository = _Repository(bytes);
      final cubit = ScannerCubit(
        camera: camera,
        repository: repository,
        allowed: true,
      );
      Widget app(Brightness brightness) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: ScannerScreen(
          cubit: cubit,
          previewBuilder: (_) => const SizedBox(),
          canReadDocuments: true,
        ),
      );
      Future<void> decoded(Finder image) async {
        final raw = find.descendant(of: image, matching: find.byType(RawImage));
        for (var attempt = 0; attempt < 50; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (raw.evaluate().isNotEmpty &&
              tester.widget<RawImage>(raw).image != null) {
            break;
          }
        }
        expect(raw, findsOneWidget);
        expect(tester.widget<RawImage>(raw).image?.width, 120);
        expect(tester.widget<RawImage>(raw).image?.height, 180);
        final pixels = await tester.runAsync(
          () => tester.widget<RawImage>(raw).image!.toByteData(),
        );
        expect(pixels!.getUint8(0), greaterThan(200));
        expect(pixels.getUint8(1), lessThan(60));
      }

      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      final thumbnail = find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == 'Page 1 preview',
      );
      await decoded(thumbnail);
      final thumbnailProvider = tester.widget<Image>(thumbnail).image;
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pumpAndSettle();
      expect(tester.widget<Image>(thumbnail).image, same(thumbnailProvider));
      await cubit.addPage();
      await cubit.capture();
      await tester.pumpAndSettle();
      final correction = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.semanticLabel ==
                'Captured page before perspective correction',
      );
      await decoded(correction);
      expect(find.text('Preview unavailable. Retake this page.'), findsNothing);
      final correctionProvider = tester.widget<Image>(correction).image;
      cubit.moveCorner(0, const ScanPoint(.1, .1));
      await tester.pump();
      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      expect(tester.widget<Image>(correction).image, same(correctionProvider));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'equal restored image bytes reuse the provider while changed pixels replace it',
    (tester) async {
      final source = img.Image(width: 10, height: 10);
      img.fill(source, color: img.ColorRgb8(220, 30, 40));
      final bytes = img.encodeJpg(source).asUnmodifiableView();
      Widget image(Uint8List value) => Directionality(
        textDirection: TextDirection.ltr,
        child: ScanImage(bytes: value, fit: BoxFit.contain),
      );
      await tester.pumpWidget(image(bytes));
      final original = tester.widget<Image>(find.byType(Image)).image;
      await tester.pumpWidget(
        image(Uint8List.fromList(bytes).asUnmodifiableView()),
      );
      expect(tester.widget<Image>(find.byType(Image)).image, same(original));
      img.fill(source, color: img.ColorRgb8(30, 220, 40));
      await tester.pumpWidget(
        image(img.encodeJpg(source).asUnmodifiableView()),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isNot(same(original)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _Camera implements ScannerCamera {
  @override
  bool get usesSystemCapture => false;
  _Camera(this.bytes);
  final Uint8List bytes;
  @override
  ScanCameraState get state => const ScanCameraState(
    status: ScanCameraStatus.ready,
    width: 120,
    height: 180,
  );
  @override
  Stream<ScanCameraState> get states => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> suspend() async {}
  @override
  Future<ScanCapture> capture() async => ScanCapture(
    id: 'browser-image',
    width: 120,
    height: 180,
    corners: ScanCorners.fullImage(),
    preview: bytes,
  );
  @override
  Future<void> releaseCapture(String id) async {}
  @override
  void cancelNewOperations() {}
  @override
  Future<void> close() async {}
}

final class _Repository implements ScanDraftRepository {
  _Repository(this.bytes);
  final Uint8List bytes;
  @override
  Future<ScanDraft> restore() async => ScanDraft(
    id: 'images',
    revision: 1,
    properties: DocumentProperties.fromDocument(
      Document(
        id: 'test',
        title: 'Preview',
        description: '',
        createdAt: DateTime.utc(2026),
      ),
    ),
    pages: [ScanPage(id: 'one', width: 120, height: 180, thumbnail: bytes)],
  );
  @override
  void cancelNewOperations() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
