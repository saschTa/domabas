import 'workspace_actions.dart'
    show revealWorkspaceAction, revealWorkspaceHeader;

import 'package:domabas_api/api.dart' as api;
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> exerciseEmailIngestion(
  WidgetTester tester, {
  required api.ApiClient client,
}) async {
  const host = String.fromEnvironment('EMAIL_FIXTURE_HOST');
  const port = String.fromEnvironment('EMAIL_FIXTURE_PORT');
  const username = String.fromEnvironment('EMAIL_FIXTURE_USERNAME');
  const password = String.fromEnvironment('EMAIL_FIXTURE_PASSWORD');
  const mailbox = String.fromEnvironment('EMAIL_FIXTURE_MAILBOX');
  expect(
    host,
    isNotEmpty,
    reason: 'The E2E harness must provide its disposable TLS IMAP fixture.',
  );
  final email = api.EmailApi(client),
      documents = api.DocumentsApi(client),
      identity = api.IdentityApi(client);
  final label = 'Fixture mailbox ${DateTime.now().microsecondsSinceEpoch}';
  debugPrint(
    'Email E2E: configure, test and import from the disposable TLS mailbox',
  );
  await _emailSettings(tester);
  await _wait(
    tester,
    () =>
        find
            .byKey(const Key('email-add'))
            .hitTestable()
            .evaluate()
            .isNotEmpty &&
        tester.widget<FilledButton>(find.byKey(const Key('email-add'))).enabled,
    'email capabilities enable account creation',
  );
  await tester.tap(find.byKey(const Key('email-add')));
  await _wait(
    tester,
    () => find.byKey(const Key('email-label')).evaluate().isNotEmpty,
    'email account editor opened',
  );
  await tester.pumpAndSettle();
  for (final entry in {
    'label': label,
    'endpoint': host,
    'port': port,
    'username': username,
    'password': password,
    'mailbox': mailbox,
    'page': '1',
  }.entries) {
    final field = find.byKey(Key('email-${entry.key}'));
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
  }
  await tester.ensureVisible(find.byKey(const Key('email-test')));
  await tester.tap(find.byKey(const Key('email-test')));
  await _wait(
    tester,
    () =>
        find.text('Connection successful.').hitTestable().evaluate().isNotEmpty,
    'verified TLS connection tested from UI',
  );
  expect(
    find.byKey(const Key('email-test-result')).hitTestable(),
    findsOneWidget,
  );
  expect(
    tester.widget<SwitchListTile>(find.byKey(const Key('email-enabled'))).value,
    isTrue,
  );
  await tester.ensureVisible(find.byKey(const Key('email-save')));
  await tester.tap(find.byKey(const Key('email-save')));
  await _wait(
    tester,
    () =>
        find.byKey(const Key('email-editor-close')).evaluate().isEmpty &&
        find.text(label).evaluate().isNotEmpty,
    'email provider saved',
  );
  final provider = (await email.listEmailProviders())!.items.singleWhere(
    (value) => value.label == label,
  );
  final detail = (await email.getEmailProvider(provider.id))!;
  expect(detail.enabled, isTrue);
  expect(detail.pageSize, 1);
  expect(detail.username, username);
  expect(detail.hasPassword, isTrue);
  expect(detail.toJson().containsKey('password'), isFalse);

  api.EmailRun? run;
  final importDeadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(importDeadline)) {
    final runs = (await email.listEmailRuns(provider.id))!.items;
    if (runs.isNotEmpty) {
      run = runs.first;
      if (!['queued', 'running'].contains(run.status.toString())) break;
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(
    run,
    isNotNull,
    reason: 'Enabling the account schedules the first retrieval.',
  );
  expect(run!.status.toString(), 'succeeded', reason: run.failureCode);
  expect(run.reason.toString(), 'scheduled');
  expect(run.messagesAccepted + run.messagesReused, 1);
  expect(run.attachmentsAccepted + run.attachmentsReused, 2);
  expect(
    run.messagesFailed +
        run.attachmentsFailed +
        run.messagesWithContentFailures,
    0,
  );

  final mail = (await documents.listDocuments(limit: 100))!.items.singleWhere(
    (value) => value.file?.mediaType.toString() == 'message/rfc822',
  );
  final links = (await documents.getDocumentEmailLinks(mail.id))!;
  expect(links.attachments.length, 2);
  expect(links.attachments.every((value) => value.document != null), isTrue);
  final ids = [
    mail.id,
    ...links.attachments.map((value) => value.document!.documentId),
  ];
  for (final id in ids) {
    await _ready(tester, documents, id);
  }
  final original = (await documents.downloadDocumentWithHttpInfo(mail.id))
      .bodyBytes;
  expect(
    String.fromCharCodes(original),
    contains('Subject: Domabas email fixture\r\n'),
  );
  expect(
    (await documents.getDocumentProcessing(mail.id))!.extractionMethod
        .toString(),
    'mime',
  );
  expect(
    (await documents.getDocumentOCR(mail.id))!.text,
    contains('searchable body and two attachments'),
  );
  for (final attachment in links.attachments) {
    expect(
      (await documents.getDocumentEmailParents(
        attachment.document!.documentId,
      ))!.items.single.documentId,
      mail.id,
    );
  }
  final search = (await documents.searchDocuments(
    _EmailTextSearch(
      query: 'searchable body',
      mode: api.DocumentSearchModeEnum.fulltext,
    ),
  ))!;
  expect(search.items.any((value) => value.document.id == mail.id), isTrue);

  await _openWorkspaceDestination(tester, 'processingNavigation');
  await _wait(
    tester,
    () => find.text('Email import pipeline').evaluate().isNotEmpty,
    'email pipeline visible',
  );
  await tester.tap(find.text('Email import pipeline'));
  await tester.pumpAndSettle();
  expect(find.text('Email originals'), findsOneWidget);
  expect(find.text('Attachments'), findsOneWidget);
  await tester.tap(find.text('Email import pipeline'));
  await tester.pumpAndSettle();
  for (final key in ['pipeline-filter-email', 'job-filter-all']) {
    final filter = find.byKey(Key(key));
    await tester.scrollUntilVisible(
      filter,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(filter), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(filter);
    await tester.pumpAndSettle();
  }
  await _wait(
    tester,
    () => find.byKey(Key('email-job-${run!.id}')).evaluate().isNotEmpty,
    'automatic email job visible',
  );
  await tester.ensureVisible(find.byKey(Key('email-job-${run.id}')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byKey(Key('email-job-${run.id}')),
      matching: find.text('Details'),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Job details'), findsOneWidget);
  expect(find.text('Pipeline for this attempt'), findsOneWidget);
  expect(
    find.text('Emails: 1 accepted · 0 reused · 0 skipped · 0 failed'),
    findsOneWidget,
  );
  expect(
    find.text('Attachments: 2 accepted · 0 reused · 0 skipped · 0 failed'),
    findsOneWidget,
  );
  final back = find.text('Back to jobs');
  await revealWorkspaceHeader(tester, back);
  await tester.tap(back);
  await tester.pumpAndSettle();
  await _emailSettings(tester);

  await tester.ensureVisible(find.byKey(const Key('email-refresh')));
  await tester.tap(find.byKey(const Key('email-refresh')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('email-import')));
  await tester.tap(find.byKey(const Key('email-import')));
  await _wait(
    tester,
    () => find
        .text('Import accepted. Document processing continues separately.')
        .evaluate()
        .isNotEmpty,
    'manual import acknowledged by the UI',
  );
  final secondDeadline = DateTime.now().add(const Duration(minutes: 2));
  api.EmailRun? second;
  while (DateTime.now().isBefore(secondDeadline)) {
    second = (await email.listEmailRuns(provider.id))!.items
        .where((value) => value.id != run!.id)
        .firstOrNull;
    if (second != null &&
        !['queued', 'running'].contains(second.status.toString())) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(second?.status.toString(), 'succeeded');
  expect(
    (await documents.listDocuments(limit: 100))!.items
        .where((value) => ids.contains(value.id))
        .length,
    3,
  );
  expect(
    (await documents.downloadDocumentWithHttpInfo(mail.id)).bodyBytes,
    original,
  );

  await revealWorkspaceAction(tester, 'personal-activity');
  await tester.tap(find.byKey(const Key('personal-activity')));
  await tester.pumpAndSettle();
  await _wait(
    tester,
    () => find.text('Finished jobs').evaluate().isNotEmpty,
    'private activity displayed',
  );
  final activity = (await identity.getPersonalActivity())!;
  expect(activity.finished.length, lessThanOrEqualTo(5));
  expect(
    activity.finished.any(
      (value) => value.kind.toString() == 'email_retrieval',
    ),
    isTrue,
  );
  await tester.ensureVisible(find.byKey(const Key('personal-activity-close')));
  await tester.tap(find.byKey(const Key('personal-activity-close')));
  await tester.pumpAndSettle();

  await _openWorkspaceDestination(tester, 'documentsNavigation');
  await _revealDocumentToolbar(tester);
  final clearSearch = find.byKey(const Key('clearDocumentSearch'));
  if (clearSearch.evaluate().isNotEmpty) {
    await tester.ensureVisible(clearSearch);
    await tester.pumpAndSettle();
    await tester.tap(clearSearch);
    await tester.pumpAndSettle();
  }
  await _revealDocumentToolbar(tester);
  await tester.tap(find.byKey(const Key('refreshDocuments')));
  await _wait(
    tester,
    () => find.text(mail.title).evaluate().isNotEmpty,
    'imported email visible',
  );
  await tester.tap(find.text(mail.title));
  await _wait(
    tester,
    () => find.byKey(const Key('email-body')).evaluate().isNotEmpty,
    'email body view loaded',
  );
  final attachment = find
      .byKey(Key('email-attachment-${links.attachments.first.part_}'))
      .last;
  await tester.ensureVisible(attachment);
  await tester.tap(attachment);
  await _wait(
    tester,
    () =>
        find
            .byKey(const Key('documentDetails'), skipOffstage: false)
            .evaluate()
            .length ==
        2,
    'linked attachment opened',
  );
  await tester.tap(find.byKey(const Key('closeDocument')).last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();

  await _emailSettings(tester);
  await _wait(
    tester,
    () =>
        find.byType(AppStripedProgressIndicator).evaluate().isEmpty &&
        find.byKey(const Key('email-delete')).evaluate().isNotEmpty &&
        tester
                .widget<TextButton>(find.byKey(const Key('email-delete')))
                .onPressed !=
            null,
    'provider is ready for deletion',
  );
  await tester.ensureVisible(find.byKey(const Key('email-delete')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('email-delete')).hitTestable(), findsOneWidget);
  await tester.tap(find.byKey(const Key('email-delete')));
  await _wait(
    tester,
    () => find.byKey(const Key('email-confirm-delete')).evaluate().isNotEmpty,
    'provider deletion confirmation opened',
  );
  await tester.ensureVisible(find.byKey(const Key('email-confirm-delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('email-confirm-delete')));
  await _wait(
    tester,
    () => find.byKey(const Key('email-add')).evaluate().isNotEmpty,
    'provider deletion confirmed',
  );
  expect((await documents.getDocument(mail.id))!.id, mail.id);
  expect(
    (await documents.downloadDocumentWithHttpInfo(mail.id)).bodyBytes,
    original,
  );
  await _openWorkspaceDestination(tester, 'documentsNavigation');
  expect(tester.takeException(), isNull);
}

final class _EmailTextSearch extends api.DocumentSearch {
  _EmailTextSearch({required super.query, required super.mode});

  @override
  Map<String, dynamic> toJson() => {'query': query, 'mode': mode};
}

Future<void> _revealDocumentToolbar(WidgetTester tester) async {
  final collection = find.byKey(const Key('documentCollectionScroll'));
  await _wait(
    tester,
    () => collection.evaluate().isNotEmpty,
    'document collection restored',
  );
  final scrollable = find
      .descendant(of: collection, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();
  final refresh = find.byKey(const Key('refreshDocuments'));
  for (
    var attempt = 0;
    attempt < 12 && refresh.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    if (refresh.evaluate().isNotEmpty) {
      await tester.ensureVisible(refresh);
    } else {
      await tester.drag(scrollable, const Offset(0, -100));
    }
    await tester.pumpAndSettle();
  }
  expect(
    refresh.hitTestable(),
    findsOneWidget,
    reason:
        'The document toolbar is reachable after restoring collection scroll.',
  );
}

Future<void> _emailSettings(WidgetTester tester) async {
  final destination = find.byKey(const Key('emailNavigation'));
  if (destination.evaluate().isEmpty) {
    final bottom = find.byKey(
      Key(
        find.byKey(const Key('navigation-more')).evaluate().isNotEmpty
            ? 'navigation-more'
            : 'navigation-user-settings',
      ),
    );
    final trigger = bottom.evaluate().isNotEmpty
        ? bottom
        : find.byTooltip('User settings');
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    expect(trigger.hitTestable(), findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }
  await _openWorkspaceDestination(tester, 'emailNavigation');
}

Future<void> _openWorkspaceDestination(WidgetTester tester, String key) async {
  final destination = find.byKey(Key(key));
  await tester.ensureVisible(destination);
  await tester.pumpAndSettle();
  expect(
    destination.hitTestable(),
    findsOneWidget,
    reason: '$key is visible before navigation.',
  );
  await tester.tap(destination);
  await tester.pumpAndSettle();
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull, reason: reason);
  expect(ready(), isTrue, reason: reason);
}

Future<void> _ready(
  WidgetTester tester,
  api.DocumentsApi documents,
  String id,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final processing = (await documents.getDocumentProcessing(id))!;
    if (processing.state.toString() == 'ready') return;
    expect(
      processing.state.toString(),
      isNot('failed'),
      reason: processing.failureCode,
    );
    await tester.pump(const Duration(milliseconds: 500));
  }
  fail('Imported document processing did not complete.');
}
