import 'package:domabas/presentation/document/widgets/document_pdf_selection_menu.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  Widget app(
    _DocumentPdfSelectionDelegate selection, {
    TargetPlatform platform = TargetPlatform.iOS,
    bool enabled = true,
  }) => MaterialApp(
    theme: AppTheme.light().copyWith(platform: platform),
    home: Scaffold(
      body: Builder(
        builder: (context) =>
            documentPdfSelectionMenuBuilder(
              context,
              PdfViewerContextMenuBuilderParams(
                isTextSelectionEnabled: enabled,
                anchorA: const Offset(100, 140),
                anchorB: const Offset(230, 190),
                textSelectionDelegate: selection,
                dismissContextMenu: () {},
                contextMenuFor: PdfViewerPart.selectedText,
              ),
            ) ??
            const SizedBox.shrink(),
      ),
    ),
  );

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      'PDF menu uses app localizations and selection actions on $platform',
      (tester) async {
        final selection = _DocumentPdfSelectionDelegate();
        await tester.pumpWidget(app(selection, platform: platform));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(selection.copies, 1);
        await tester.tap(find.textContaining(RegExp(r'^Select [aA]ll$')));
        await tester.pump();
        expect(selection.selections, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('PDF menu respects copy permission and selection availability', (
    tester,
  ) async {
    final selection = _DocumentPdfSelectionDelegate()..copyAllowed = false;
    await tester.pumpWidget(app(selection));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(find.textContaining(RegExp(r'^Select [aA]ll$')), findsOneWidget);
    selection.allSelected = true;
    await tester.pumpWidget(app(selection));
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    selection
      ..copyAllowed = true
      ..allSelected = false
      ..selected = false;
    await tester.pumpWidget(app(selection));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    await tester.pumpWidget(app(selection, enabled: false));
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final class _DocumentPdfSelectionDelegate extends Fake
    implements PdfTextSelectionDelegate {
  bool copyAllowed = true;
  bool selected = true;
  bool allSelected = false;
  int copies = 0;
  int selections = 0;

  @override
  bool get isCopyAllowed => copyAllowed;

  @override
  bool get hasSelectedText => selected;

  @override
  bool get isSelectingAllText => allSelected;

  @override
  Future<bool> copyTextSelection() async {
    copies++;
    return true;
  }

  @override
  Future<void> selectAllText() async {
    selections++;
  }
}
