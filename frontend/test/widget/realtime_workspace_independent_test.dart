import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/personal_activity.dart';
import 'package:domabas/domain/realtime/models/realtime.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/workspace_navigation.dart';

class _Activity extends FakeActivityRepository {
  int reads = 0;
  @override
  Future<PersonalActivity> getActivity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  }) {
    reads++;
    return super.getActivity(cancel: cancel);
  }
}

class _Email extends FakeEmailRepository {
  int reads = 0;
  @override
  Future<EmailProviderPage> listProviders({
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) {
    reads++;
    return super.listProviders(limit: limit, cursor: cursor, cancel: cancel);
  }
}

Identity _display(Identity old) => Identity(
  userId: old.userId,
  email: 'renamed@example.test',
  accountId: old.accountId,
  accountName: 'Renamed live library',
  role: old.role,
  mustChangePassword: old.mustChangePassword,
  isOwner: old.isOwner,
  systemRole: old.systemRole,
  claims: old.claims,
  permissions: old.permissions,
);

void main() {
  late FakeRealtimeRepository realtime;
  late FakeDocumentRepository documents;
  late FakeProcessingRepository processing;
  late FakeIdentityRepository identity;
  late _Activity activity;
  late _Email email;
  late AuthenticatedDependencies dependencies;
  late AuthSession session;
  late List<String> ended;
  var closes = 0;

  setUp(() {
    realtime = FakeRealtimeRepository();
    documents = FakeDocumentRepository();
    processing = FakeProcessingRepository();
    identity = FakeIdentityRepository();
    activity = _Activity();
    email = _Email();
    ended = [];
    closes = 0;
    session = testSession(
      extraPermissions: [
        IdentityPermission.connectRealtime,
        IdentityPermission.readDocumentJobs,
        IdentityPermission.reindexDocuments,
        IdentityPermission.manageEmail,
        IdentityPermission.uploadDocuments,
        IdentityPermission.readOwnActivity,
      ],
    );
    identity.onCurrentIdentity = () async => session.identity;
    documents.records = [
      Document(
        id: 'document',
        title: 'Initial title',
        description: '',
        createdAt: DateTime.utc(2026),
      ),
    ];
    dependencies = AuthenticatedDependencies(
      documents: documents,
      identity: identity,
      processing: processing,
      email: email,
      activity: activity,
      realtime: realtime,
      externalLinks: FakeExternalLinkLauncher(),
      close: () {
        closes++;
      },
    );
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AccountWorkspace(
          session: session,
          dependencies: dependencies,
          onLogout: () {},
          onSessionEnded: ended.add,
          onSwitch: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    dependencies.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'ready refreshes visible documents and display identity; hidden email stays dirty',
    (tester) async {
      await mount(tester);
      expect(realtime.connectCalls, 1);
      final initialReads = documents.offsets.length;
      documents.records = [
        Document(
          id: 'document',
          title: 'Remote title',
          description: '',
          createdAt: DateTime.utc(2026),
        ),
      ];
      identity.onCurrentIdentity = () async => _display(session.identity);
      realtime.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [
            RealtimeTopic.documents,
            RealtimeTopic.identity,
            RealtimeTopic.email,
            RealtimeTopic.activity,
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(documents.offsets.length, initialReads + 1);
      expect(find.text('Remote title'), findsOneWidget);
      expect(find.text('Renamed live library'), findsWidgets);
      expect(ended, isEmpty);
      expect(realtime.connectCalls, 1);
      expect(email.reads, 0);
      expect(processing.pipelineReads, 0);
      await navigateWorkspace(tester, 'emailNavigation');
      expect(email.reads, greaterThan(0));
      await unmount(tester);
    },
  );

  testWidgets(
    'activity never polls during disconnect and reconnect refreshes its baseline',
    (tester) async {
      await mount(tester);
      realtime.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.activity],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final baseline = activity.reads;
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(activity.reads, baseline);
      realtime.emit(
        RealtimeEvent(RealtimeEventKind.disconnected, closeCode: 1013),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(activity.reads, baseline);
      await revealWorkspaceAction(tester, 'liveUpdatesStatus');
      await tester.tap(find.byKey(const Key('liveUpdatesStatus')));
      await tester.pump();
      expect(
        find.text(
          'Live updates unavailable. Job progress will resume when reconnected.',
        ),
        findsOneWidget,
      );
      realtime.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.activity],
        ),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(activity.reads, greaterThan(baseline));
      await unmount(tester);
    },
  );

  testWidgets(
    'background ignores frames; foreground reconnects; disposal ends owned work',
    (tester) async {
      await mount(tester);
      realtime.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.documents, RealtimeTopic.activity],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final reads = documents.offsets.length, activityReads = activity.reads;
      realtime.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.documents, RealtimeTopic.activity],
        ),
      );
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(documents.offsets.length, reads);
      expect(activity.reads, activityReads);
      expect(realtime.connectCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(realtime.connectCalls, 2);
      realtime.emit(
        RealtimeEvent(RealtimeEventKind.disconnected, closeCode: 4403),
      );
      await tester.pump();
      expect(ended, hasLength(1));
      await unmount(tester);
      dependencies.dispose();
      expect(realtime.disposed, isTrue);
      expect(realtime.disposeCalls, 1);
      expect(documents.cancelled, isTrue);
      expect(activity.cancelled, isTrue);
      expect(email.cancelled, isTrue);
      expect(processing.cancellations, 1);
      expect(closes, 1);
    },
  );
}
