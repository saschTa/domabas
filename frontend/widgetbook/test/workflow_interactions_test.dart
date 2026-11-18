import 'package:domabas/ui/domabas_ui.dart';
import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('job history opens matching evidence in a dismissible modal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entry = catalogCases().singleWhere(
      (entry) => entry.id == 'jobs-history',
    );
    await tester.pumpWidget(CatalogPreview(entry: entry, reduceMotion: true));
    await tester.tap(find.text('Studio lease · 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.text(
        'A recorded embedding step is running. Its remaining time is unknown.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry attempt'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Studio lease · 2026'), findsOneWidget);
  });
  testWidgets(
    'composer sends with Control Enter and preserves ordinary Enter',
    (tester) async {
      final controller = TextEditingController(text: 'Find my lease');
      addTearDown(controller.dispose);
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: Scaffold(
            body: GlacierChatComposer(
              controller: controller,
              onSend: () => sends++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(sends, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sends, 1);
      controller.value = const TextEditingValue(
        text: 'unfinished',
        composing: TextRange(start: 0, end: 10),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(sends, 1);
      controller.clear();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(sends, 1);
    },
  );

  testWidgets(
    'uncertain acceptance checks the original request instead of sending',
    (tester) async {
      final controller = TextEditingController(text: 'A retained question');
      addTearDown(controller.dispose);
      var sends = 0, checks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.dark(),
          home: Scaffold(
            body: GlacierChatComposer(
              controller: controller,
              onSend: () => sends++,
              onCheck: () => checks++,
            ),
          ),
        ),
      );
      expect(find.text('Send'), findsNothing);
      await tester.tap(find.text('Check sent message'));
      expect(checks, 1);
      expect(sends, 0);
      expect(controller.text, 'A retained question');
    },
  );

  testWidgets('history delete does not select the conversation', (
    tester,
  ) async {
    String? selected, deleted;
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
        home: Scaffold(
          body: GlacierConversationHistory(
            conversations: const [
              GlacierConversation(
                id: 'lease',
                title: 'Lease',
                updated: 'Today',
              ),
            ],
            selectedId: null,
            onSelect: (id) => selected = id,
            onNew: () {},
            onDelete: (id) => deleted = id,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Delete Lease'));
    expect(deleted, 'lease');
    expect(selected, isNull);
    await tester.tap(find.text('Lease'));
    expect(selected, 'lease');
  });

  testWidgets('compact history returns to the same chat screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entry = catalogCases().singleWhere(
      (entry) => entry.id == 'chat-conversation',
    );
    await tester.pumpWidget(CatalogPreview(entry: entry, reduceMotion: true));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('New conversation'), findsOneWidget);
    await tester.tap(find.byTooltip('Close history'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.byType(GlacierChatComposer), findsOneWidget);
  });

  testWidgets('unknown stage evidence never becomes complete automatically', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
        home: const Scaffold(
          body: GlacierPipelineTimeline(
            stages: [
              GlacierPipelineStage(
                label: 'Original',
                state: GlacierStageState.unknown,
              ),
              GlacierPipelineStage(
                label: 'Index',
                state: GlacierStageState.failed,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Complete'), findsNothing);
  });
}
