import 'package:domabas/presentation/chat/cubits/chat_cubit.dart';
import 'package:domabas/presentation/chat/views/chat_screen.dart';
import 'package:domabas/presentation/chat/widgets/chat_message_card.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:domabas/presentation/invoice/views/invoices_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';
import '../support/fake_invoice_repository.dart';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 1,
  double bottom = 0,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light().copyWith(platform: platform),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: bottom),
            textScaler: TextScaler.linear(scale),
          ),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> wheel(WidgetTester tester, Finder target, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(target),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition position(WidgetTester tester, Finder list) => tester
    .state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    )
    .position;

void main() {
  for (final desktop in [false, true]) {
    testWidgets(
      'content scrolls within a fixed pane with ${desktop ? 'desktop wheel' : 'phone drag'}',
      (tester) async {
        late StateSetter refresh;
        var revision = 0;
        await mount(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return AppPage(
                title: 'Library members',
                description: 'Manage the people who share your library.',
                actions: [
                  FilledButton(onPressed: () {}, child: const Text('Invite')),
                ],
                child: ListView.builder(
                  key: const Key('pageRecords'),
                  itemCount: 100,
                  itemExtent: 80,
                  itemBuilder: (context, index) =>
                      Text('Member $index · $revision'),
                ),
              );
            },
          ),
          size: desktop ? const Size(1440, 900) : const Size(390, 844),
          platform: desktop ? TargetPlatform.windows : TargetPlatform.android,
        );
        final list = find.byKey(const Key('pageRecords'));
        final heading = find.text('Library members');
        final initialHeight = tester.getSize(list).height;
        final surface = tester.getRect(find.byKey(const Key('pageSurface')));
        final controls = tester.getRect(find.byKey(const Key('pageControls')));
        expect(heading, findsNothing);
        expect(find.text('Member 99 · 0'), findsNothing);
        if (desktop) {
          await wheel(tester, list, 500);
        } else {
          await tester.drag(list, const Offset(0, -500));
          await tester.pumpAndSettle();
        }
        expect(heading.hitTestable(), findsNothing);
        expect(tester.getSize(list).height, initialHeight);
        expect(tester.getRect(find.byKey(const Key('pageSurface'))), surface);
        expect(tester.getRect(find.byKey(const Key('pageControls'))), controls);
        expect(find.text('Invite').hitTestable(), findsOneWidget);
        final scrolled = position(tester, list).pixels;
        expect(scrolled, greaterThan(0));
        refresh(() => revision++);
        await tester.pumpAndSettle();
        expect(position(tester, list).pixels, closeTo(scrolled, .1));
        expect(heading.hitTestable(), findsNothing);
        if (desktop) {
          await wheel(tester, list, -5000);
        } else {
          await tester.drag(list, const Offset(0, 5000));
          await tester.pumpAndSettle();
        }
        expect(heading, findsNothing);
        expect(find.text('Invite').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short enlarged page retains actions and final row clearance', (
    tester,
  ) async {
    var saved = false;
    await mount(
      tester,
      Builder(
        builder: (context) => AppPage(
          title: 'Workload settings',
          description:
              'Manage work and provider capacity across your libraries.',
          actions: [
            FilledButton(
              onPressed: () {},
              child: const Text('Refresh settings'),
            ),
          ],
          insetBody: false,
          child: ListView(
            key: const Key('settingsFields'),
            padding: AppLayout.cardListPadding(context),
            children: [
              for (var index = 0; index < 10; index++)
                SizedBox(height: 90, child: Text('Capacity $index')),
              FilledButton(
                key: const Key('saveSettings'),
                onPressed: () => saved = true,
                child: const Text('Save settings'),
              ),
            ],
          ),
        ),
      ),
      size: const Size(390, 360),
      scale: 2,
      bottom: 100,
    );
    final list = find.byKey(const Key('settingsFields'));
    await tester.drag(list, const Offset(0, -1800));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('saveSettings'));
    expect(find.text('Workload settings').hitTestable(), findsNothing);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(260));
    await tester.tap(save);
    expect(saved, isTrue);
    await tester.drag(list, const Offset(0, 1800));
    await tester.pumpAndSettle();
    final headingScroll = find.byKey(const Key('pageControls'));
    await tester.drag(headingScroll, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Refresh settings').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice pane keeps its height and refresh position', (
    tester,
  ) async {
    final repository = FakeInvoiceRepository();
    for (var index = 0; index < 20; index++) {
      final invoice = invoiceFixture(index);
      repository.records[invoice.id] = invoice;
    }
    final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
    await mount(tester, InvoicesScreen(cubit: cubit));
    final list = find.byKey(const PageStorageKey('invoiceWorkspaceScroll'));
    expect(find.text('Invoices'), findsNothing);
    final surface = tester.getRect(find.byKey(const Key('pageSurface')));
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Invoices').hitTestable(), findsNothing);
    final before = position(tester, list).pixels;
    cubit.invalidate();
    await tester.pumpAndSettle();
    expect(position(tester, list).pixels, closeTo(before, .1));
    expect(tester.getRect(find.byKey(const Key('pageSurface'))), surface);
    expect(find.text('Invoices').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'chat controls stay fixed while composer and transcript follow survive at $width',
      (tester) async {
        final conversation = chatConversation('one');
        final repository = FakeChatRepository()
          ..history = List.generate(30, (index) => chatConversation('$index'))
          ..history.add(conversation)
          ..transcript['one'] = List.generate(
            25,
            (index) => chatMessage(
              'answer-$index',
              sequence: index + 1,
              content: 'Answer $index\n${'Document detail. ' * 15}',
            ),
          );
        final cubit = ChatCubit(repository, allowed: true)..setActive(true);
        addTearDown(cubit.close);
        await mount(
          tester,
          ChatScreen(cubit: cubit, libraryName: 'My library'),
          size: Size(width, 844),
        );
        await cubit.select(conversation);
        await tester.pumpAndSettle();
        final list = find.byKey(const Key('chatTranscript'));
        await wheel(tester, list, -20000);
        await tester.pumpAndSettle();
        expect(find.text('AI chat'), findsNothing);
        final controls = tester.getRect(find.byKey(const Key('pageControls')));
        final composer = find.byKey(const Key('chatMessage'));
        final composerBottom = tester.getRect(composer).bottom;
        await tester.drag(list, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(find.text('AI chat').hitTestable(), findsNothing);
        expect(composer.hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byKey(const Key('pageControls'))), controls);
        expect(find.byKey(const Key('newChat')).hitTestable(), findsOneWidget);
        expect(tester.getRect(composer).bottom, closeTo(composerBottom, .1));
        expect(find.text('Jump to latest').hitTestable(), findsOneWidget);
        final before = position(tester, list).pixels;
        repository.transcript['one']!.add(
          chatMessage(
            'new-answer',
            sequence: 26,
            content: 'A new answer arrived.',
          ),
        );
        await cubit.refreshMessages();
        await tester.pumpAndSettle();
        expect(position(tester, list).pixels, closeTo(before, .1));
        await tester.tap(find.text('Jump to latest'));
        await tester.pumpAndSettle();
        expect(position(tester, list).extentAfter, closeTo(0, .1));
        repository.transcript['one']!.add(
          chatMessage(
            'newer-answer',
            sequence: 27,
            content: 'Another answer arrived.',
          ),
        );
        await cubit.refreshMessages();
        await tester.pumpAndSettle();
        expect(position(tester, list).extentAfter, closeTo(0, .1));
        if (width > 1000) {
          final history = find.byKey(const Key('chatHistoryList'));
          final transcriptOffset = position(tester, list).pixels;
          await tester.drag(history, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(position(tester, list).pixels, closeTo(transcriptOffset, .1));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'loading earlier chat keeps the visible message and fixed controls in place',
    (tester) async {
      final conversation = chatConversation('one');
      final repository = FakeChatRepository()
        ..history = [conversation]
        ..transcript['one'] = List.generate(
          25,
          (index) => chatMessage(
            'answer-$index',
            sequence: index + 1,
            content: 'Answer $index',
          ),
        );
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await mount(tester, ChatScreen(cubit: cubit, libraryName: 'My library'));
      await cubit.select(conversation);
      await tester.pumpAndSettle();
      final list = find.byKey(const Key('chatTranscript'));
      await wheel(tester, list, -20000);
      final anchor = find.byWidgetPredicate(
        (widget) =>
            widget is ChatMessageCard && widget.message.id == 'answer-5',
      );
      expect(find.text('AI chat'), findsNothing);
      expect(find.byKey(const Key('newChat')).hitTestable(), findsOneWidget);
      final before = tester.getTopLeft(anchor).dy;
      await tester.tap(find.byKey(const Key('earlierChatMessages')));
      await tester.pumpAndSettle();
      expect(cubit.state.messages.length, 25);
      expect(find.text('AI chat'), findsNothing);
      expect(find.byKey(const Key('newChat')).hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
      expect(tester.takeException(), isNull);
    },
  );
}
