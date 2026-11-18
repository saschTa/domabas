import 'dart:ui' show CheckedState, Tristate;

import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpMobile(
  WidgetTester tester,
  String id, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    CatalogPreview(
      entry: catalogCases().firstWhere((entry) => entry.id == id),
      textScale: scale,
      reduceMotion: true,
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

List<SemanticsData> semanticData(WidgetTester tester) {
  final result = <SemanticsData>[];
  void visit(SemanticsNode node) {
    if (!node.isMergedIntoParent) result.add(node.getSemanticsData());
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  tester.binding.rootPipelineOwner.visitChildren((owner) {
    final root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  });
  return result;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('DMSans')
      ..addFont(
        rootBundle.load('packages/domabas/assets/fonts/DMSans-Regular.ttf'),
      );
    await loader.load();
  });
  testWidgets('Appearance exposes one selected action in each choice group', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpMobile(tester, 'mobile-appearance-ready');
    for (final label in ['System', 'Light', 'Dark', 'Calm', 'Activity']) {
      final nodes = semanticData(tester)
          .where((node) => node.label == label && node.flagsCollection.isButton)
          .toList();
      expect(nodes, hasLength(1), reason: label);
      expect(nodes.single.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(nodes.single.flagsCollection.isToggled, Tristate.none);
      expect(
        nodes.single.flagsCollection.isChecked == CheckedState.isTrue,
        label == 'System' || label == 'Activity',
        reason: label,
      );
      expect(
        nodes.single.flagsCollection.isSelected == Tristate.isTrue,
        label == 'System' || label == 'Activity',
        reason: label,
      );
    }
    await tester.tap(find.text('Dark'));
    await tester.pump();
    final selected = semanticData(tester)
        .where((node) => node.flagsCollection.isSelected == Tristate.isTrue)
        .map((node) => node.label);
    expect(selected, contains('Dark'));
    expect(selected, isNot(contains('System')));
    handle.dispose();
  });
  testWidgets('Search choices expose one named selected button per action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpMobile(tester, 'mobile-search-ready');
    for (final label in ['Words', 'PDF']) {
      final nodes = semanticData(tester)
          .where((node) => node.label == label && node.flagsCollection.isButton)
          .toList();
      expect(nodes, hasLength(1), reason: label);
      expect(
        nodes.single.flagsCollection.isInMutuallyExclusiveGroup,
        label == 'Words',
      );
      expect(nodes.single.flagsCollection.isToggled, Tristate.none);
    }
    await tester.tap(find.text('PDF').last);
    await tester.pump();
    final pdf = semanticData(tester).singleWhere(
      (node) => node.label == 'PDF' && node.flagsCollection.isButton,
    );
    expect(pdf.flagsCollection.isSelected == Tristate.isTrue, isTrue);
    expect(pdf.flagsCollection.isChecked == CheckedState.isTrue, isTrue);
    handle.dispose();
  });
  testWidgets(
    'Filtered collection count and continuation describe the same scope',
    (tester) async {
      await pumpMobile(tester, 'mobile-documents-ready');
      await tester.tap(find.text('Find a document'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'Forma');
      await tester.tap(find.text('PDF').last);
      await tester.tap(find.text('Apply search'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1 match · Personal'), findsOneWidget);
      expect(find.text('1 matching document shown'), findsOneWidget);
      expect(find.text('6 of 248 documents'), findsNothing);
      final continuation = tester.widget<GlacierMobileContinuation>(
        find.byType(GlacierMobileContinuation),
      );
      expect(continuation.onLoadMore, isNull);
    },
  );
  testWidgets('Accepted scan receipt retains its page count in the original', (
    tester,
  ) async {
    await pumpMobile(tester, 'mobile-scan-review-ready');
    await tester.tap(find.byTooltip('Remove page 1'));
    await tester.pump();
    await tester.ensureVisible(find.text('Upload 2-page PDF'));
    await tester.tap(find.text('Upload 2-page PDF'));
    await tester.pump(const Duration(milliseconds: 300));
    tester
        .widget<GlacierMobileUploadOutcome>(
          find.byType(GlacierMobileUploadOutcome),
        )
        .onCheck!();
    await tester.pump();
    expect(find.text('2 pages · Personal library'), findsOneWidget);
    tester
        .widget<GlacierMobileUploadOutcome>(
          find.byType(GlacierMobileUploadOutcome),
        )
        .onOpen!();
    await tester.pump();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    final reader = tester.widget<GlacierMobileReader>(
      find.byType(GlacierMobileReader),
    );
    reader.onNextPage!();
    await tester.pump();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(
      tester
          .widget<GlacierMobileReader>(find.byType(GlacierMobileReader))
          .onNextPage,
      isNull,
    );
  });
  testWidgets(
    'Library selection persists into Documents and capture destination',
    (tester) async {
      await pumpMobile(tester, 'mobile-library-ready');
      await tester.tap(find.text('Family archive'));
      await tester.pump();
      expect(
        tester
            .widget<GlacierMobileLibraryRow>(
              find.widgetWithText(GlacierMobileLibraryRow, 'Family archive'),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Documents'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Family archive'), findsOneWidget);
      await tester.tap(find.text('Scan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester
            .widget<GlacierMobileScanHandoff>(
              find.byType(GlacierMobileScanHandoff),
            )
            .library,
        'Family archive',
      );
      expect(find.text('Destination: Family archive library'), findsOneWidget);
    },
  );
  testWidgets('Chat Send exposes one disabled action without nested buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpMobile(tester, 'mobile-chat-ready');
    final nodes = semanticData(tester).where(
      (node) => node.label == 'Send message' && node.flagsCollection.isButton,
    );
    expect(nodes, hasLength(1));
    expect(nodes.single.flagsCollection.isEnabled == Tristate.isTrue, isFalse);
    handle.dispose();
  });
  testWidgets('Isolated FieldGroup inherits the mobile Material typography', (
    tester,
  ) async {
    await pumpMobile(tester, 'mobile-component-field-group');
    final context = tester.element(find.text('Email'));
    final style = DefaultTextStyle.of(context).style;
    expect(style.color, Theme.of(context).colorScheme.onSurface);
    expect(style.decoration, TextDecoration.none);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Large tablet rail fits full labels and preserves content clearance',
    (tester) async {
      await pumpMobile(
        tester,
        'mobile-workload-ready',
        size: const Size(768, 1024),
        scale: 2,
      );
      final rail = tester.getRect(find.byType(GlacierMobileNavigation));
      expect(rail.width, 208);
      expect(rail.left, 14);
      final title = tester.getRect(find.text('Workload limits').first);
      expect(title.left, 256);
      final documents = tester.getRect(find.text('Documents'));
      expect(documents.right, lessThanOrEqualTo(rail.right));
      expect(documents.height, lessThan(30));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Large phone title gets full width below Back', (tester) async {
    await pumpMobile(
      tester,
      'mobile-confirm-delete',
      size: const Size(320, 740),
      scale: 2,
    );
    final title = tester.getRect(find.text('Named confirmation'));
    final back = tester.getRect(find.byTooltip('Back'));
    expect(title.width, greaterThanOrEqualTo(296));
    expect(title.top, greaterThanOrEqualTo(back.bottom + 8));
    expect(tester.takeException(), isNull);
  });
  for (final configuration in [
    (const Size(768, 1024), 1.0, true),
    (const Size(390, 844), 1.0, false),
    (const Size(768, 1024), 2.0, false),
  ]) {
    testWidgets(
      'Member fields adapt ${configuration.$1.width}/${configuration.$2}',
      (tester) async {
        await pumpMobile(
          tester,
          'mobile-members-ready',
          size: configuration.$1,
          scale: configuration.$2,
        );
        final email = tester.getRect(find.text('Recipient email'));
        final role = tester.getRect(find.text('Library role'));
        if (configuration.$3) {
          expect(role.top, email.top);
          expect(role.left, greaterThan(email.right));
        } else {
          expect(role.top, greaterThan(email.bottom));
          expect(role.left, email.left);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
