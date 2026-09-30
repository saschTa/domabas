import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/presentation/document/cubits/document_preview_cubit.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/models/document_previews.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/ui/app_navigation_button.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fake_document_repository.dart';
import 'support/document_thumbnail_fixture.dart';

Future<List<int>> _pixel(
  WidgetTester tester,
  GlobalKey boundary,
  Offset point,
) async {
  final image = await tester.runAsync(
    () =>
        (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final offset = (point.dy.floor() * image!.width + point.dx.floor()) * 4;
  final result = List.generate(3, (index) => bytes!.getUint8(offset + index));
  image.dispose();
  return result;
}

void main() {
  testWidgets(
    'pause racing a fulfilled render disposes the unadopted clone and empty resume recovers',
    (tester) async {
      final source = img.Image(width: 20, height: 30);
      img.fill(source, color: img.ColorRgb8(230, 30, 30));
      final repository = _PreviewRepository(img.encodeJpg(source));
      final coordinator = DocumentPreviewCoordinator(repository);
      final cubit = DocumentPreviewCubit(
        coordinator,
        repository.records.single.thumbnailRef,
      );
      addTearDown(cubit.close);
      addTearDown(coordinator.close);
      ui.Image? original;
      final oldCreate = ui.Image.onCreate;
      ui.Image.onCreate = (image) {
        if (original != null) return;
        original = image;
        var attempts = 0;
        void pauseAfterClone() {
          if (image.debugGetOpenHandleStackTraces()!.length > 1) {
            coordinator.pause();
          } else if (attempts++ < 50) {
            scheduleMicrotask(pauseAfterClone);
          }
        }

        scheduleMicrotask(pauseAfterClone);
      };
      try {
        await tester.runAsync(cubit.load);
        expect(original, isNotNull);
        expect(cubit.state.image, isNull);
        expect(cubit.state.loading, isFalse);
        expect(original!.debugGetOpenHandleStackTraces(), hasLength(1));
        coordinator.resume();
        await cubit.resume();
        expect(cubit.state.image, isNotNull);
        expect(repository.downloads, 1);
      } finally {
        ui.Image.onCreate = oldCreate;
      }
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} navigation hover and reversal never paint the gray intermediate flash',
      (tester) async {
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        final boundary = GlobalKey();
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: ColoredBox(
                    color: theme.colorScheme.surface,
                    child: SizedBox(
                      width: 240,
                      height: 80,
                      child: AppNavigationButton(
                        label: 'Destination',
                        onPressed: () {},
                        reduceMotion: false,
                        focusNode: focus,
                        child: const Text('Destination'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        final button = find.byType(AppNavigationButton);
        final initial = await _pixel(tester, boundary, const Offset(20, 20));
        final target = theme.scaffoldBackgroundColor;
        final targetChannels = [
          (target.r * 255).round(),
          (target.g * 255).round(),
          (target.b * 255).round(),
        ];
        Future<void> frame(int millis) async {
          await tester.pump(Duration(milliseconds: millis));
          final actual = await _pixel(tester, boundary, const Offset(20, 20));
          for (var index = 0; index < 3; index++) {
            final endpoints = [initial[index], targetChannels[index]]..sort();
            expect(
              actual[index],
              inInclusiveRange(endpoints.first - 2, endpoints.last + 2),
              reason: 'channel $index intermediate pixel $actual',
            );
          }
        }

        await mouse.moveTo(tester.getCenter(button));
        await tester.pump();
        for (var index = 0; index < 3; index++) {
          await frame(16);
        }
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        for (var index = 0; index < 3; index++) {
          await frame(16);
        }
        await mouse.moveTo(tester.getCenter(button));
        await tester.pump();
        for (var index = 0; index < 12; index++) {
          await frame(16);
        }
        final settled = await _pixel(tester, boundary, const Offset(20, 20));
        for (var index = 0; index < 3; index++) {
          expect(settled[index], closeTo(targetChannels[index], 2));
        }
        focus.requestFocus();
        await tester.pumpAndSettle();
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: button,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect((decoration.border! as Border).top.width, 2);
        expect(
          (decoration.border! as Border).top.color,
          theme.colorScheme.primary,
        );
        await mouse.removePointer();
      },
    );
  }

  testWidgets(
    'ready collection thumbnail keeps its image, pixels and completed reveal across nested viewer return',
    (tester) async {
      final source = img.Image(width: 40, height: 60);
      img.fill(source, color: img.ColorRgb8(230, 30, 30));
      final bytes = img.encodeJpg(source);
      final repository = _PreviewRepository(bytes);
      final cubit = DocumentsCubit(
        repository,
        capabilities: allDocumentCapabilities,
      );
      addTearDown(cubit.close);
      cubit.setActive(true);
      await cubit.load();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: DocumentsScreen(cubit: cubit),
            ),
          ),
        ),
      );
      final raw = find.byType(RawImage);
      final card = find.byKey(const Key('document-image'));
      final pendingSize = tester.getSize(card);
      for (var index = 0; index < 50 && raw.evaluate().isEmpty; index++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(raw, findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.getSize(card), pendingSize);
      final image = tester.widget<RawImage>(raw).image;
      final origin = tester.getTopLeft(find.byKey(boundary));
      final point = tester.getCenter(raw) - origin;
      final pixel = await _pixel(tester, boundary, point);
      expect(pixel, [230, 30, 30]);
      final first = cubit.openDocument('image');
      final nested = cubit.openDocument('image');
      final epoch = cubit.state.previewEpoch;
      await cubit.closeDocument(nested);
      expect(cubit.state.previewEpoch, epoch);
      await cubit.closeDocument(first);
      expect(cubit.state.previewEpoch, epoch + 1);
      for (var index = 0; index < 14; index++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget<RawImage>(raw).image, same(image));
        expect(await _pixel(tester, boundary, point), pixel);
        final reveal = find
            .ancestor(of: raw, matching: find.byType(Opacity))
            .first;
        expect(tester.widget<Opacity>(reveal).opacity, 1);
      }
      expect(repository.downloads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancelled empty preview resumes while fulfilled unadopted image clones are disposed',
    (tester) async {
      final source = img.Image(width: 20, height: 30);
      img.fill(source, color: img.ColorRgb8(230, 30, 30));
      final repository = _PreviewRepository(img.encodeJpg(source));
      final coordinator = DocumentPreviewCoordinator(repository);
      addTearDown(coordinator.close);
      coordinator.pause();
      final cubit = DocumentPreviewCubit(
        coordinator,
        repository.records.single.thumbnailRef,
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.image, isNull);
      coordinator.resume();
      await tester.runAsync(cubit.resume);
      final ready = cubit.state.image;
      expect(ready, isNotNull);
      coordinator.pause();
      coordinator.resume();
      await cubit.resume();
      expect(cubit.state.image, same(ready));
      expect(repository.downloads, 1);
      final handles = ready!.debugGetOpenHandleStackTraces()!.length;
      final cloneConsumer = DocumentPreviewCubit(
        coordinator,
        repository.records.single.thumbnailRef,
      );
      final pending = cloneConsumer.load();
      expect(ready.debugGetOpenHandleStackTraces(), hasLength(handles + 1));
      await cloneConsumer.close();
      await pending;
      expect(ready.debugGetOpenHandleStackTraces(), hasLength(handles));
    },
  );
}

final class _PreviewRepository extends FakeDocumentRepository {
  _PreviewRepository(this.bytes) {
    records = [
      Document(
        id: 'image',
        title: 'Red image',
        description: '',
        createdAt: DateTime.utc(2026),
        thumbnail: documentThumbnailFixture(bytes),
        file: DocumentFile(
          originalFilename: 'image.png',
          mediaType: 'image/png',
          size: bytes.length,
          sha256: 'red',
          ingestedAt: DateTime.utc(2026),
          uploaderId: 'user',
        ),
      ),
    ];
  }
  final Uint8List bytes;
  int downloads = 0;
  @override
  Future<Uint8List> thumbnail(
    DocumentThumbnailRef document, {
    Future<void>? cancel,
  }) async {
    downloads++;
    return bytes;
  }
}
