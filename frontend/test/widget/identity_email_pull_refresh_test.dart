import 'dart:async';

import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/personal_activity.dart';
import 'package:domabas/presentation/email/cubits/email_providers_cubit.dart';
import 'package:domabas/presentation/email/views/email_providers_screen.dart';
import 'package:domabas/presentation/identity/cubits/account_cubit.dart';
import 'package:domabas/presentation/identity/cubits/libraries_cubit.dart';
import 'package:domabas/presentation/identity/cubits/personal_activity_cubit.dart';
import 'package:domabas/presentation/identity/cubits/system_users_cubit.dart';
import 'package:domabas/presentation/identity/views/libraries_screen.dart';
import 'package:domabas/presentation/identity/views/members_screen.dart';
import 'package:domabas/presentation/identity/views/system_users_screen.dart';
import 'package:domabas/presentation/identity/widgets/personal_activity_action.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';

void main() {
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pull(WidgetTester tester) async {
    final list = find.byType(ListView).last;
    final bounds = tester.getRect(list);
    await tester.dragFrom(
      Offset(bounds.center.dx, bounds.top + 40),
      const Offset(0, 500),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final invitations in [false, true]) {
    testWidgets(
      'empty ${invitations ? 'invitations' : 'members'} list pulls and waits for its read',
      (tester) async {
        final repository = FakeIdentityRepository();
        final cubit = AccountCubit(
          repository,
          identity: testSession().identity,
          onSessionEnded: (_) {},
        );
        addTearDown(cubit.close);
        await cubit.load();
        await cubit.loadInvitations();
        await mount(
          tester,
          MembersScreen(
            cubit: cubit,
            invitations: invitations,
            copyInvitation: (_) async => true,
          ),
        );
        expect(find.byIcon(Icons.refresh), findsNothing);
        var reads = 0;
        final members = Completer<MemberPage>();
        final invites = Completer<InvitationPage>();
        repository.onList = () {
          reads++;
          return members.future;
        };
        repository.onInvitations = () {
          reads++;
          return invites.future;
        };
        await pull(tester);
        expect(reads, 1);
        expect(find.byType(RefreshProgressIndicator), findsOneWidget);
        expect(invitations ? cubit.loadingInvitations : cubit.loading, isTrue);
        if (invitations) {
          invites.complete(InvitationPage(items: const [], total: 0));
        } else {
          members.complete(MemberPage(items: const [], total: 0));
        }
        await tester.pumpAndSettle();
        expect(find.byType(RefreshProgressIndicator), findsNothing);
        expect(
          find.text(
            invitations ? 'No invitations yet' : 'No members to display',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty system user list supports pull to refresh', (
    tester,
  ) async {
    final repository = FakeIdentityRepository();
    final cubit = SystemUsersCubit(
      repository,
      identity: testSession(systemRole: SystemRole.admin).identity,
      onSessionEnded: (_) {},
    );
    addTearDown(cubit.close);
    await cubit.load();
    await mount(tester, SystemUsersScreen(cubit: cubit));
    expect(find.byTooltip('Refresh users'), findsNothing);
    final response = Completer<SystemUserPage>();
    var reads = 0;
    repository.onSystemUsers = (_, _) {
      reads++;
      return response.future;
    };
    await pull(tester);
    expect(reads, 1);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    response.complete(SystemUserPage(items: const [], total: 0, adminCount: 0));
    await tester.pumpAndSettle();
    expect(find.text('No users to display'), findsOneWidget);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling libraries retains an invitation draft while loading', (
    tester,
  ) async {
    final repository = FakeIdentityRepository();
    final cubit = LibrariesCubit(
      repository,
      identity: testSession().identity,
      onSwitch: (_) async => null,
    );
    addTearDown(cubit.close);
    await cubit.load();
    await mount(tester, LibrariesScreen(cubit: cubit));
    expect(find.byTooltip('Refresh libraries'), findsNothing);
    final field = find.byKey(const Key('acceptInvitationCode'));
    await tester.enterText(field, 'pending invitation code');
    final element = tester.element(field);
    final response = Completer<AccountPage>();
    var reads = 0;
    repository.onAccounts = () {
      reads++;
      return response.future;
    };
    await pull(tester);
    expect(reads, 1);
    expect(tester.element(field), same(element));
    expect(find.text('pending invitation code'), findsOneWidget);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    response.complete(AccountPage(items: const [], total: 0));
    await tester.pumpAndSettle();
    expect(find.text('pending invitation code'), findsOneWidget);
    expect(tester.element(field), same(element));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty email accounts pull waits for server response', (
    tester,
  ) async {
    final repository = _PullEmailRepository();
    final cubit = EmailProvidersCubit(
      repository,
      allowed: true,
      canImport: true,
    );
    addTearDown(cubit.close);
    await cubit.load();
    await mount(tester, EmailProvidersScreen(cubit: cubit));
    expect(find.byKey(const Key('email-refresh')), findsNothing);
    expect(find.text('No email accounts'), findsOneWidget);
    repository.pending = Completer<EmailProviderPage>();
    await pull(tester);
    expect(repository.reads, 2);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    repository.pending!.complete(EmailProviderPage(items: const []));
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(find.text('No email accounts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Your jobs supports pulling an empty activity list', (
    tester,
  ) async {
    final repository = _PullActivityRepository();
    final cubit = PersonalActivityCubit(repository)..setActive(true);
    addTearDown(cubit.close);
    await mount(
      tester,
      PersonalActivityAction(
        cubit: cubit,
        namespaceId: 'library',
        onOpen: (_) async {},
      ),
    );
    await tester.tap(find.byKey(const Key('personal-activity')));
    await tester.pumpAndSettle();
    expect(find.text('Refresh jobs'), findsNothing);
    final before = repository.reads;
    repository.pending = Completer<PersonalActivity>();
    await pull(tester);
    expect(repository.reads, before + 1);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    repository.pending!.complete(repository.activity);
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(find.text('No active jobs.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _PullEmailRepository extends FakeEmailRepository {
  int reads = 0;
  Completer<EmailProviderPage>? pending;
  @override
  Future<EmailProviderPage> listProviders({
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) async {
    reads++;
    return pending == null
        ? super.listProviders(limit: limit, cursor: cursor, cancel: cancel)
        : pending!.future;
  }
}

final class _PullActivityRepository extends FakeActivityRepository {
  int reads = 0;
  Completer<PersonalActivity>? pending;
  @override
  Future<PersonalActivity> getActivity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  }) async {
    reads++;
    return pending == null ? activity : pending!.future;
  }
}
