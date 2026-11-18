import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/native_reference_cases.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = catalogCases();
  testWidgets('activity fallback retains dock jobs and selected library', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatalogPreview(
        entry: cases.firstWhere(
          (c) => c.id == 'native-windows-documents-light',
        ),
        reduceMotion: true,
      ),
    );
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    await settle();
    tester.widget<GlacierWorkspace>(find.byType(GlacierWorkspace)).onLibrary!();
    await settle();
    await tester.tap(
      find.widgetWithText(GlacierButton, 'Switch to Family library'),
    );
    await settle();
    final dock = tester.widget<GlacierActivityDock>(
      find.byType(GlacierActivityDock),
    );
    expect(dock.jobs.map((job) => job.library), everyElement('Family library'));
    await tester.tap(find.byKey(const ValueKey('activity-dock-token')));
    await settle();
    final panel = tester.widget<GlacierActivityPanel>(
      find.byType(GlacierActivityPanel),
    );
    expect(panel.library, 'Family library');
    expect(panel.running, 1);
    expect(panel.waiting, 1);
    final rows = panel.jobs.cast<GlacierJobRow>();
    expect(rows.map((job) => job.title), dock.jobs.map((job) => job.title));
    expect(rows.map((job) => job.status), dock.jobs.map((job) => job.status));
    final first = find.descendant(
      of: find.byType(GlacierActivityPanel),
      matching: find.text(dock.jobs.first.title),
    );
    await tester.ensureVisible(first);
    await tester.tap(first);
    await settle();
    expect(
      tester.widget<GlacierDialog>(find.byType(GlacierDialog)).title,
      dock.jobs.first.title,
    );
    expect(find.text('Family library'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(find.byType(GlacierDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'enlarged native chat retains editable input and reachable Send',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: cases.firstWhere((c) => c.id == 'native-windows-chat'),
          textScale: 2,
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final composer = find.byType(GlacierChatComposer);
      final input = find.descendant(
        of: composer,
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'Where are the lease terms?');
      await tester.pump();
      final send = find.widgetWithText(GlacierButton, 'Send');
      await tester.ensureVisible(send);
      await tester.pump();
      final pageScroll = tester.state<ScrollableState>(
        find.ancestor(of: composer, matching: find.byType(Scrollable)).last,
      );
      pageScroll.position.jumpTo(pageScroll.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(send).bottom, lessThanOrEqualTo(768));
      await tester.tap(send);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      final messages = tester
          .widget<GlacierChatScreen>(find.byType(GlacierChatScreen))
          .messages
          .whereType<GlacierChatMessage>();
      expect(
        messages.any((message) => message.text == 'Where are the lease terms?'),
        isTrue,
      );
      final stop = find.widgetWithText(GlacierButton, 'Stop reply');
      await tester.ensureVisible(stop);
      await tester.pump();
      pageScroll.position.jumpTo(pageScroll.position.maxScrollExtent);
      await tester.pump();
      await tester.tap(stop);
      await tester.pump();
      expect(find.widgetWithText(GlacierButton, 'Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native enlarged workload footer stays above compact dock footprint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: cases.firstWhere((c) => c.id == 'native-windows-admin'),
          textScale: 2,
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final actionScroll = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.widgetWithText(GlacierButton, 'Save changes'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      actionScroll.position.jumpTo(actionScroll.position.maxScrollExtent);
      await tester.pump();
      final dock = tester.getRect(
        find.byKey(const ValueKey('activity-dock-token')),
      );
      final save = tester.getRect(
        find.widgetWithText(GlacierButton, 'Save changes'),
      );
      final reset = tester.getRect(
        find.widgetWithText(GlacierButton, 'Use saved values'),
      );
      expect(save.bottom, lessThan(dock.top));
      expect(reset.bottom, lessThan(dock.top));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native enlarged metadata and document actions share aligned rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: cases.firstWhere((c) => c.id == 'native-windows-text-200'),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getRect(find.text('16 Nov')).top,
        tester.getRect(find.text('15 Nov')).top,
        reason:
            '${tester.getRect(find.text('Home').first)} ${tester.getRect(find.text('Utilities').first)} ${tester.getRect(find.byType(GlacierDocumentCard).first)} ${tester.getRect(find.byType(GlacierDocumentCard).at(1))}',
      );
      final upload = tester
          .getCenter(find.widgetWithText(GlacierButton, 'Upload'))
          .dy;
      expect(
        tester.getCenter(find.byTooltip('Grid view')).dy,
        closeTo(upload, 1),
      );
      expect(
        tester.getCenter(find.byTooltip('More document actions')).dy,
        closeTo(upload, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native 800 grid uses three columns with equal original previews',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: cases.firstWhere((c) => c.id == 'native-windows-compact-800'),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      final previews = find.descendant(
        of: find.byType(GlacierDocumentCard),
        matching: find.byType(ClipRRect),
      );
      final heights = previews
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)).height)
          .where((h) => h == 180);
      expect(heights.length, greaterThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('workload fixtures preserve bounded per-resource saved values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatalogPreview(
        entry: cases.firstWhere((c) => c.id == 'settings-workload'),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(find.byType(GlacierWorkloadResource), findsNWidgets(3));
    expect(find.text('Saved'), findsNWidgets(3));
    expect(find.text('Active'), findsNWidgets(3));
    expect(find.text('Allowed: 1–16'), findsOneWidget);
    final first = find.byType(TextFormField).first;
    await tester.enterText(first, '17');
    await tester.pump();
    GlacierButton save() => tester.widget<GlacierButton>(
      find.widgetWithText(GlacierButton, 'Save changes'),
    );
    expect(save().onPressed, isNull);
    await tester.enterText(first, '7');
    await tester.pump();
    save().onPressed!();
    await tester.pump();
    expect(
      tester
          .widget<GlacierWorkloadResource>(
            find.byType(GlacierWorkloadResource).first,
          )
          .savedLimit,
      7,
    );
    await tester.enterText(first, '3');
    await tester.pump();
    tester
        .widget<GlacierButton>(
          find.widgetWithText(GlacierButton, 'Use saved values'),
        )
        .onPressed!();
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: first, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      '7',
    );
    expect(find.textContaining('reserved'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'ordinary desktop retains its original toolbar bounds without native reservations',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: cases.firstWhere((c) => c.id == 'desktop-workspace'),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final toolbar = tester.getRect(find.byType(GlacierToolbar).first);
      expect(toolbar.left, 268);
      expect(toolbar.top, 16);
      expect(toolbar.right, 1416);
      expect(find.byType(GlacierNativeFrame), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final spec in nativeReferenceCases) {
    testWidgets('${spec['id']} renders its frozen native context', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(
        Size(
          (spec['width']! as num).toDouble(),
          (spec['height']! as num).toDouble(),
        ),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: cases.firstWhere((c) => c.id == spec['id']),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: spec['id']! as String);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
