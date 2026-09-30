import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/app/session_client.dart';
import 'package:domabas/data/identity/datasources/identity_remote_data_source.dart';
import 'package:domabas/data/identity/repos/remote_identity_repository.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:domabas/domain/identity/interfaces/session_store.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final class _SessionStore implements SessionStore {
  String? token;
  bool signedOut = false;

  @override
  Future<String?> readToken() async => token;
  @override
  Future<bool> isSignedOut() async => signedOut;
  @override
  Future<void> saveToken(String value) async {
    token = value;
    signedOut = false;
  }

  @override
  Future<void> clear() async {
    token = null;
    signedOut = true;
  }
}

void main() {
  late HttpServer server;
  late api.ApiClient generated;
  late RemoteIdentityRepository repository;
  late Future<void> Function(HttpRequest) respond;
  const userId = 'ba0e7b7e-5d42-4b71-9bb7-afb3c8889c2c';
  const accountId = '8f88bb47-38fb-4e7b-bdc4-bb9c4c83c52c';
  final token = base64Url.encode(List.filled(32, 17)).replaceAll('=', '');
  final identity = {
    'user': {
      'id': userId,
      'email': 'person@example.com',
      'mustChangePassword': false,
    },
    'account': {'id': accountId, 'name': 'Private library'},
    'role': 'admin',
    'isOwner': true,
    'claims': <String>[],
    'systemRole': 'user',
    'permissions': ['documents:read', 'documents:create', 'users:manage'],
  };
  final member = {
    'id': userId,
    'email': 'person@example.com',
    'role': 'viewer',
    'enabled': true,
    'mustChangePassword': true,
    'isOwner': false,
    'claims': <String>[],
    'permissions': ['documents:read'],
  };
  Map<String, Object> session() => {
    'token': token,
    'expiresAt': '2100-01-01T00:00:00Z',
    'identity': identity,
  };

  test(
    'missing and malformed expiry cannot become a persistent session',
    () async {
      for (final expiry in [true, 42, 'not-a-date', '2026-09-18', <String>[]]) {
        respond = (request) async => request.response.write(
          jsonEncode({
            'token': token,
            'identity': identity,
            'expiresAt': expiry,
          }),
        );
        await expectLater(
          repository.login(email: 'person@example.com', password: 'password'),
          throwsA(
            isA<IdentityFailure>().having(
              (failure) => failure.kind,
              'kind',
              IdentityFailureKind.invalidResponse,
            ),
          ),
        );
      }
      respond = (request) async => request.response.write(
        jsonEncode({'token': token, 'identity': identity}),
      );
      await expectLater(
        repository.login(email: 'person@example.com', password: 'password'),
        throwsA(
          isA<IdentityFailure>().having(
            (failure) => failure.kind,
            'kind',
            IdentityFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'revocation uses the explicitly issued bearer through the generated API',
    () async {
      respond = (request) async {
        expect(request.method, 'DELETE');
        expect(request.uri.path, '/api/v1/auth/session');
        expect(request.headers.value('Authorization'), 'Bearer $token');
        request.response.statusCode = 204;
      };
      await repository.revoke(
        AuthSession(
          token: token,
          expiresAt: null,
          identity: Identity(
            userId: userId,
            email: 'person@example.com',
            accountId: accountId,
            accountName: 'Private library',
            role: AccountRole.admin,
            mustChangePassword: false,
            permissions: [],
          ),
        ),
      );
    },
  );

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    generated = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}');
    repository = RemoteIdentityRepository(
      IdentityRemoteDataSource(api.IdentityApi(generated)),
    );
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      await respond(request);
      await request.response.close();
    });
  });
  tearDown(() async {
    generated.client.close();
    await server.close(force: true);
  });

  test(
    'restore validates saved native credentials and maps nullable expiry',
    () async {
      final store = _SessionStore()..token = token;
      repository = RemoteIdentityRepository(
        IdentityRemoteDataSource(api.IdentityApi(generated)),
        sessionStore: store,
      );
      respond = (request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/auth/restore');
        expect(request.headers.value('Authorization'), 'Bearer $token');
        request.response.write(
          jsonEncode({'token': token, 'expiresAt': null, 'identity': identity}),
        );
      };
      final restored = await repository.restore();
      expect(restored!.expiresAt, isNull);
      expect(restored.identity.accountId, accountId);
      expect(store.token, token);
    },
  );

  test(
    'restore keeps unavailable credentials and clears rejected credentials',
    () async {
      final store = _SessionStore()..token = token;
      repository = RemoteIdentityRepository(
        IdentityRemoteDataSource(api.IdentityApi(generated)),
        sessionStore: store,
      );
      respond = (request) async => request.response.statusCode = 503;
      await expectLater(repository.restore(), throwsA(isA<IdentityFailure>()));
      expect(store.token, token);
      respond = (request) async => request.response.statusCode = 401;
      expect(await repository.restore(), isNull);
      expect(store.token, isNull);
      expect(store.signedOut, isTrue);
    },
  );

  test('browser signed-out marker skips restore and absent cookie is ordinary sign-out', () async {
    final store = _SessionStore();
    repository = RemoteIdentityRepository(
      IdentityRemoteDataSource(api.IdentityApi(generated)),
      sessionStore: store,
    );
    var requests = 0;
    respond = (request) async {
      requests++;
      expect(request.headers.value('Authorization'), isNull);
      request.response.statusCode = 204;
    };
    expect(await repository.restore(), isNull);
    expect(requests, 1);
    await repository.forget();
    expect(await repository.restore(), isNull);
    expect(requests, 1);
  });

  test('generated public auth transport canonicalizes email but preserves password and maps immutable claims', () async {
    const password = '  My long password 2026  ';
    final paths = <String>[];
    respond = (request) async {
      paths.add(request.uri.path);
      expect(request.headers.value('authorization'), isNull);
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      expect(body['email'], 'person@example.com');
      expect(body['password'], password);
      if (request.uri.path.endsWith('register')) {
        expect(body['accountName'], 'Private library');
        request.response.statusCode = 201;
      }
      request.response.write(jsonEncode(session()));
    };
    final registered = await repository.register(
      accountName: ' Private library ',
      email: ' Person@Example.com ',
      password: password,
    );
    expect(registered.identity.accountId, accountId);
    expect(registered.identity.allows(IdentityPermission.manageUsers), isTrue);
    expect(
      () => registered.identity.permissions.clear(),
      throwsUnsupportedError,
    );
    final loggedIn = await repository.login(
      email: ' PERSON@example.com ',
      password: password,
    );
    expect(loggedIn.token, token);
    expect(paths, ['/api/v1/auth/register', '/api/v1/auth/login']);
  });

  test('session transport sends immutable bearer for member operations, password change and logout', () async {
    var expired = 0;
    generated.client.close();
    generated.client = SessionClient(
      http.Client(),
      token: token,
      onUnauthorized: () => expired++,
    );
    final calls = <String>[];
    respond = (request) async {
      expect(request.headers.value('authorization'), 'Bearer $token');
      calls.add('${request.method} ${request.uri.path}');
      if (request.method == 'GET') {
        expect(request.uri.queryParameters, {'limit': '25', 'offset': '5'});
        request.response.write(
          jsonEncode({
            'items': [member],
            'total': 6,
          }),
        );
      } else if (request.method == 'POST') {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'email': 'person@example.com',
          'password': 'Initial password here',
          'role': 'viewer',
          'claims': <String>[],
        });
        request.response.statusCode = 201;
        request.response.write(jsonEncode(member));
      } else if (request.method == 'PATCH') {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'role': 'user',
          'enabled': false,
          'claims': <String>[],
        });
        request.response.write(
          jsonEncode({...member, 'role': 'user', 'enabled': false}),
        );
      } else if (request.method == 'PUT') {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'currentPassword': ' Current password ',
          'newPassword': ' New password here ',
        });
        request.response.statusCode = 204;
      } else {
        request.response.statusCode = 204;
      }
    };
    final page = await repository.listMembers(limit: 25, offset: 5);
    expect(page.total, 6);
    expect(page.items.single.mustChangePassword, isTrue);
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      (await repository.createMember(
        email: 'Person@example.com',
        password: 'Initial password here',
        role: AccountRole.viewer,
      )).role,
      AccountRole.viewer,
    );
    final updated = await repository.updateMember(
      id: userId,
      role: AccountRole.user,
      enabled: false,
    );
    expect(updated.enabled, isFalse);
    expect(updated.role, AccountRole.user);
    await repository.changePassword(
      currentPassword: ' Current password ',
      newPassword: ' New password here ',
    );
    await repository.logout();
    expect(expired, 0);
    expect(calls, [
      'GET /api/v1/account/users',
      'POST /api/v1/account/users',
      'PATCH /api/v1/account/users/$userId',
      'PUT /api/v1/auth/password',
      'DELETE /api/v1/auth/session',
    ]);
  });

  test(
    'future claim IDs survive identity decoding as immutable strings',
    () async {
      respond = (request) async => request.response.write(
        jsonEncode({
          ...session(),
          'identity': {
            ...identity,
            'permissions': ['documents:read', 'documents:semantic-search'],
          },
        }),
      );
      final value = await repository.login(
        email: 'person@example.com',
        password: 'password',
      );
      expect(value.identity.permissions, contains('documents:semantic-search'));
      expect(
        () => value.identity.permissions.add('invented'),
        throwsUnsupportedError,
      );
    },
  );

  test('namespace, invitation, catalog and system operations use generated transport and boundary mapping', () async {
    final membership = {
      'account': {'id': accountId, 'name': 'Shared library'},
      'role': 'viewer',
      'isOwner': false,
      'claims': ['documents:create'],
      'permissions': ['documents:read', 'documents:create'],
    };
    final invitation = {
      'id': userId,
      'email': 'person@example.com',
      'role': 'viewer',
      'claims': ['documents:create'],
      'createdAt': '2026-09-17T12:00:00Z',
      'expiresAt': '2026-09-24T12:00:00Z',
      'status': 'pending',
    };
    final systemUser = {
      'id': userId,
      'email': 'person@example.com',
      'role': 'user',
      'createdAt': '2026-09-17T12:00:00Z',
    };
    final seen = <String>[];
    respond = (request) async {
      final path = request.uri.path;
      seen.add('${request.method} $path');
      if (path.endsWith('/switch-account')) {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'accountId': accountId,
        });
        request.response.write(jsonEncode(session()));
      } else if (path.endsWith('/accept-invitation')) {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'code': token,
        });
        request.response.statusCode = 201;
        request.response.write(jsonEncode(membership));
      } else if (path.endsWith('/claims')) {
        request.response.write(
          jsonEncode({
            'items': [
              {
                'id': 'documents:future',
                'label': 'Future action',
                'scope': 'namespace',
                'roles': ['viewer', 'future-role'],
              },
              {
                'id': 'system:users:manage',
                'label': 'System users',
                'scope': 'system',
                'roles': ['admin'],
              },
            ],
          }),
        );
      } else if (path.endsWith('/accounts')) {
        expect(request.uri.queryParameters, {'limit': '10', 'offset': '3'});
        request.response.write(
          jsonEncode({
            'items': [membership],
            'total': 4,
          }),
        );
      } else if (path.endsWith('/invitations')) {
        if (request.method == 'POST') {
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'email': 'person@example.com',
            'role': 'viewer',
            'claims': ['documents:create'],
          });
          request.response.statusCode = 201;
          request.response.write(
            jsonEncode({'invitation': invitation, 'code': token}),
          );
        } else {
          request.response.write(
            jsonEncode({
              'items': [invitation],
              'total': 1,
            }),
          );
        }
      } else if (path.contains('/invitations/')) {
        expect(request.method, 'DELETE');
        request.response.statusCode = 204;
      } else if (request.method == 'PATCH') {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'role': 'admin',
        });
        request.response.write(jsonEncode({...systemUser, 'role': 'admin'}));
      } else {
        request.response.write(
          jsonEncode({
            'items': [systemUser],
            'total': 3,
            'adminCount': 2,
          }),
        );
      }
    };
    final accounts = await repository.listAccounts(limit: 10, offset: 3);
    expect(accounts.items.single.claims, {'documents:create'});
    expect(() => accounts.items.clear(), throwsUnsupportedError);
    expect((await repository.switchAccount(accountId)).token, token);
    final catalog = await repository.listClaims();
    expect(catalog.first.id, 'documents:future');
    expect(catalog.first.roles, {'viewer', 'future-role'});
    expect(catalog.first.includesRole(AccountRole.viewer), isTrue);
    expect(catalog.last.includesRole(AccountRole.admin), isFalse);
    expect(() => catalog.first.roles.clear(), throwsUnsupportedError);
    expect(catalog.last.scope, IdentityClaimScope.system);
    expect(() => catalog.clear(), throwsUnsupportedError);
    final issued = await repository.createInvitation(
      email: ' Person@Example.com ',
      role: AccountRole.viewer,
      claims: {IdentityPermission.createDocuments},
    );
    expect(issued.code, token);
    expect(issued.invitation.status, InvitationStatus.pending);
    expect(
      (await repository.listInvitations()).items.single.email,
      'person@example.com',
    );
    await repository.revokeInvitation(userId);
    expect((await repository.acceptInvitation(' $token ')).id, accountId);
    final systemUsers = await repository.listSystemUsers();
    expect(systemUsers.items.single.role, SystemRole.user);
    expect(systemUsers.adminCount, 2);
    expect(
      (await repository.updateSystemUser(userId, SystemRole.admin)).role,
      SystemRole.admin,
    );
    expect(seen, hasLength(9));
  });

  for (final adminCount in [-1, 0, 3]) {
    test(
      'invalid global administrator count $adminCount fails decoding',
      () async {
        respond = (request) async {
          request.response.write(
            jsonEncode({
              'items': [
                {
                  'id': userId,
                  'email': 'person@example.com',
                  'role': 'admin',
                  'createdAt': '2026-09-17T12:00:00Z',
                },
              ],
              'total': 2,
              'adminCount': adminCount,
            }),
          );
        };
        await expectLater(
          repository.listSystemUsers(),
          throwsA(
            isA<IdentityFailure>().having(
              (failure) => failure.kind,
              'kind',
              IdentityFailureKind.invalidResponse,
            ),
          ),
        );
      },
    );
  }

  for (final entry in <(int, String, IdentityFailureKind)>[
    (400, 'invalid_credentials', IdentityFailureKind.invalidCredentials),
    (401, 'unauthorized', IdentityFailureKind.unauthorized),
    (403, 'forbidden', IdentityFailureKind.forbidden),
    (
      403,
      'password_change_required',
      IdentityFailureKind.passwordChangeRequired,
    ),
    (409, 'conflict', IdentityFailureKind.conflict),
    (429, 'rate_limited', IdentityFailureKind.rateLimited),
    (500, 'internal', IdentityFailureKind.unavailable),
  ]) {
    test('HTTP ${entry.$1}/${entry.$2} maps to safe domain failure', () async {
      respond = (request) async {
        request.response.statusCode = entry.$1;
        request.response.write(
          jsonEncode({'code': entry.$2, 'message': 'private server secret'}),
        );
      };
      await expectLater(
        repository.changePassword(currentPassword: 'old', newPassword: 'new'),
        throwsA(
          isA<IdentityFailure>()
              .having((failure) => failure.kind, 'kind', entry.$3)
              .having(
                (failure) => failure.message,
                'message',
                isNot(contains('secret')),
              ),
        ),
      );
    });
  }

  test('closed old session ignores late 401', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    var callbacks = 0;
    generated.client.close();
    final old = SessionClient(
      http.Client(),
      token: token,
      onUnauthorized: () => callbacks++,
    );
    generated.client = old;
    respond = (request) async {
      expect(request.headers.value('authorization'), 'Bearer $token');
      received.complete();
      await release.future;
      request.response.statusCode = 401;
    };
    final pending = repository.logout();
    final failure = expectLater(pending, throwsA(isA<IdentityFailure>()));
    await received.future;
    old.close();
    release.complete();
    await failure;
    expect(callbacks, 0);
  });

  test('malformed identity response cannot become a session', () async {
    for (final body in [
      'not-json',
      jsonEncode({...session(), 'token': 'bad-token'}),
      jsonEncode({
        ...session(),
        'identity': {...identity, 'role': 'unknown'},
      }),
    ]) {
      respond = (request) async => request.response.write(body);
      await expectLater(
        repository.login(email: 'person@example.com', password: 'password'),
        throwsA(
          isA<IdentityFailure>().having(
            (failure) => failure.kind,
            'kind',
            IdentityFailureKind.invalidResponse,
          ),
        ),
      );
    }
  });
}
