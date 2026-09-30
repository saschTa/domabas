import 'dart:async';

import 'package:domabas/domain/document/models/document_email.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/presentation/document/cubits/document_email_links_cubit.dart';
import 'package:domabas/presentation/identity/cubits/current_identity_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_identity_repository.dart';

const _parent = DocumentLink(
  id: 'parent',
  title: 'Source email',
  mediaType: 'message/rfc822',
);
const _attachment = DocumentEmailAttachment(
  part: '1',
  filename: 'Attachment',
  status: 'accepted',
  document: _parent,
);

class _Links extends FakeDocumentRepository {
  final attachmentCursors = <String?>[], parentCursors = <String?>[];
  bool fail = false, replacement = false;
  Completer<DocumentEmailLinks>? first;
  @override
  Future<DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) async {
    attachmentCursors.add(cursor);
    if (first != null && attachmentCursors.length == 1) return first!.future;
    if (fail) throw const DocumentFailure(DocumentFailureKind.unavailable);
    return DocumentEmailLinks(
      attachments: replacement ? [] : [_attachment],
      nextCursor: cursor == null ? 'next-attachment' : null,
    );
  }

  @override
  Future<DocumentEmailParents> emailParents(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) async {
    parentCursors.add(cursor);
    if (fail) throw const DocumentFailure(DocumentFailureKind.unavailable);
    return DocumentEmailParents(
      items: replacement ? [] : [_parent],
      nextCursor: cursor == null ? 'next-parent' : null,
    );
  }
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 3)) {
      fail('Projection did not refresh');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Identity _identity({
  String user = 'user',
  String account = 'account',
  String email = 'user@example.test',
  String name = 'Library',
  AccountRole role = AccountRole.viewer,
  SystemRole systemRole = SystemRole.user,
  bool owner = false,
  bool mustChange = false,
  List<String> claims = const [],
  List<String> permissions = const ['documents:read', 'realtime:connect'],
}) => Identity(
  userId: user,
  accountId: account,
  email: email,
  accountName: name,
  role: role,
  systemRole: systemRole,
  isOwner: owner,
  mustChangePassword: mustChange,
  claims: claims,
  permissions: permissions,
);

void main() {
  for (final parents in [false, true]) {
    test(
      'paged ${parents ? 'parents' : 'attachments'} stay stale until successful explicit reset',
      () async {
        final repository = _Links();
        final cubit = DocumentEmailLinksCubit(repository, 'document');
        addTearDown(cubit.close);
        await cubit.load();
        await cubit.load(moreParents: parents, moreAttachments: !parents);
        cubit.setActive(true);
        cubit.invalidate();
        await _until(() => cubit.state.stale);
        final calls =
            repository.attachmentCursors.length +
            repository.parentCursors.length;
        expect(cubit.state.attachments.single, _attachment);
        expect(cubit.state.parents.single, _parent);
        await cubit.load(moreAttachments: true);
        await cubit.load(moreParents: true);
        expect(
          repository.attachmentCursors.length + repository.parentCursors.length,
          calls,
        );
        repository.fail = true;
        await cubit.reload();
        expect(cubit.state.stale, isTrue);
        expect(cubit.state.attachments.single, _attachment);
        expect(cubit.state.parents.single, _parent);
        repository.fail = false;
        repository.replacement = true;
        await cubit.reload();
        expect(cubit.state.stale, isFalse);
        expect(cubit.state.attachments, isEmpty);
        expect(cubit.state.parents, isEmpty);
        expect(repository.attachmentCursors.last, isNull);
        expect(repository.parentCursors.last, isNull);
      },
    );
  }

  test('hint during initial links read survives busy state and refreshes first page', () async {
    final repository = _Links()..first = Completer<DocumentEmailLinks>();
    final cubit = DocumentEmailLinksCubit(repository, 'document');
    addTearDown(cubit.close);
    cubit.setActive(true);
    final pending = cubit.load();
    cubit.invalidate();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(repository.attachmentCursors, hasLength(1));
    repository.replacement = true;
    repository.first!.complete(DocumentEmailLinks(attachments: [_attachment]));
    await pending;
    await _until(
      () =>
          repository.attachmentCursors.length == 2 &&
          cubit.state.attachments.isEmpty,
    );
    expect(cubit.state.attachments, isEmpty);
    expect(cubit.state.stale, isFalse);
  });

  test(
    'display-only identity changes preserve scope and set order is irrelevant',
    () async {
      final repository = FakeIdentityRepository();
      final ended = <String>[];
      final cubit = CurrentIdentityCubit(
        repository,
        _identity(),
        onSessionEnded: ended.add,
      );
      addTearDown(cubit.close);
      repository.onCurrentIdentity = () async => _identity(
        name: 'Renamed',
        email: 'new@example.test',
        permissions: ['realtime:connect', 'documents:read'],
      );
      cubit.setActive(true);
      cubit.invalidate();
      await _until(() => cubit.state.accountName == 'Renamed');
      expect(cubit.state.email, 'new@example.test');
      expect(ended, isEmpty);
    },
  );

  final changed = <String, Identity>{
    'user': _identity(user: 'other'),
    'library': _identity(account: 'other'),
    'role': _identity(role: AccountRole.user),
    'system role': _identity(systemRole: SystemRole.admin),
    'ownership': _identity(owner: true),
    'password requirement': _identity(mustChange: true),
    'claims': _identity(claims: ['email:manage']),
    'permissions': _identity(permissions: ['documents:read']),
  };
  for (final entry in changed.entries) {
    test(
      'changed ${entry.key} ends scope instead of silently replacing authority',
      () async {
        final repository = FakeIdentityRepository()
          ..onCurrentIdentity = () async => entry.value;
        final initial = _identity(), ended = <String>[];
        final cubit = CurrentIdentityCubit(
          repository,
          initial,
          onSessionEnded: ended.add,
        );
        addTearDown(cubit.close);
        cubit.setActive(true);
        cubit.invalidate();
        await _until(() => ended.isNotEmpty);
        expect(ended, hasLength(1));
        expect(identical(cubit.state, initial), isTrue);
      },
    );
  }

  test('unavailable identity keeps session, while close fences a late authority result', () async {
    final repository = FakeIdentityRepository();
    final ended = <String>[];
    final response = Completer<Identity>();
    var reads = 0;
    repository.onCurrentIdentity = () {
      reads++;
      return response.future;
    };
    final cubit = CurrentIdentityCubit(
      repository,
      _identity(),
      onSessionEnded: ended.add,
    );
    cubit.setActive(true);
    cubit.invalidate();
    await _until(() => reads == 1);
    await cubit.close();
    response.complete(_identity(role: AccountRole.admin));
    await Future<void>.delayed(Duration.zero);
    expect(ended, isEmpty);
    final next = CurrentIdentityCubit(
      repository,
      _identity(),
      onSessionEnded: ended.add,
    );
    addTearDown(next.close);
    repository.onCurrentIdentity = () async {
      reads++;
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    };
    next.setActive(true);
    next.invalidate();
    await _until(() => reads == 2);
    await Future<void>.delayed(Duration.zero);
    expect(ended, isEmpty);
  });
}
