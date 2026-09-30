import 'dart:async';

import 'package:domabas/domain/document/interfaces/document_upload_repository.dart';
import 'package:domabas/domain/document/interfaces/document_upload_scheduler.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/presentation/document/cubits/document_uploads_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_upload_host.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _WaitingScheduler implements DocumentUploadScheduler {
  @override
  bool get contentBusy => true;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  bool start(Future<void> Function() operation) => false;
}

final class _Repository implements DocumentUploadRepository {
  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) => throw StateError('Read must stay queued');
  @override
  void release(Iterable<String> ids) {}
  @override
  void dispose() {}
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'passive overlay preserves route/form/focus at 320px and 200% ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.reset();
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cubit = DocumentUploadsCubit(
          repository: _Repository(),
          scheduler: _WaitingScheduler(),
          libraryName: 'Household documents',
          canRead: true,
          allowed: true,
        );
        final text = TextEditingController(text: 'Unsaved notes');
        final focus = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: DocumentUploadHost(cubit: cubit, child: child!),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Unsaved form')),
                          body: TextField(controller: text, focusNode: focus),
                        ),
                      ),
                    ),
                    child: const Text('Open form'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open form'));

        await tester.pumpAndSettle();

        focus.requestFocus();
        await tester.pump();
        final originalSelection = text.selection;

        cubit.setHover(true);
        await tester.pump();
        expect(find.byKey(const Key('fileDropInvitation')), findsOneWidget);
        expect(find.text('Unsaved form'), findsOneWidget);
        expect(focus.hasFocus, isTrue);
        expect(text.text, 'Unsaved notes');
        expect(text.selection, originalSelection);
        expect(tester.takeException(), isNull);
        cubit.setHover(false);
        cubit.reserveBatch(1);
        cubit.receiveBatch([
          const DocumentUploadCandidate(
            id: 'one',
            displayName: 'Annual invoice 世界.pdf',
          ),
        ]);
        await tester.pump();
        expect(find.byKey(const Key('uploadFeedback')), findsNothing);
        expect(cubit.state.pending, 1);
        expect(focus.hasFocus, isTrue);
        expect(text.text, 'Unsaved notes');

        cubit.reserveBatch(21);
        await tester.pump();
        expect(cubit.state.feedback, contains('None of this batch'));
        expect(find.textContaining('None of this batch'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());

        await tester.runAsync(cubit.close);
        text.dispose();
        focus.dispose();
      },
    );
  }
}
