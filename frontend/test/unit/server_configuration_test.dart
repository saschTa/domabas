import 'dart:async';

import 'package:domabas/data/server/repos/local_server_repository.dart';
import 'package:domabas/data/server/repos/server_sources.dart';
import 'package:domabas/domain/server/models/server_address.dart';
import 'package:domabas/domain/server/models/server_failure.dart';
import 'package:domabas/presentation/server/cubits/server_configuration_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server_repository.dart';

void main() {
  test('canonical server addresses preserve port and installation path', () {
    expect(
      ServerAddress.parse(' HTTPS://EXAMPLE.COM:443/library/// ').value,
      'https://example.com/library',
    );
    expect(
      ServerAddress.parse('http://127.0.0.1:8080/').value,
      'http://127.0.0.1:8080',
    );
    expect(
      ServerAddress.parse('http://192.168.0.230:8088/').value,
      'http://192.168.0.230:8088',
    );
    expect(
      ServerAddress.parse('http://[::1]:8080/base').value,
      'http://[::1]:8080/base',
    );
    expect(
      ServerAddress.parse('https://example.com/a/../b').value,
      'https://example.com/b',
    );
  });

  test(
    'rejects absent hosts, credentials, query strings and invalid ports',
    () {
      for (final value in [
        '',
        'localhost:8080',
        'ftp://example.com',
        'https://',
        'https://user:password@example.com',
        'https://example.com?token=abc',
        'https://example.com#fragment',
        'https://example.com:0',
        'https://example.com:65536',
        'https://exa mple.com',
      ]) {
        expect(
          () => ServerAddress.parse(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );

  test(
    'saved server wins over build default and restore makes no request',
    () async {
      final repository = FakeServerRepository()
        ..stored = ServerAddress.parse('https://saved.example.com');
      final cubit = ServerConfigurationCubit(
        repository,
        initialAddress: 'http://localhost:8080',
      );
      await cubit.restore();
      expect(cubit.state.address, repository.stored);
      expect(repository.checks, isEmpty);
      await cubit.close();
    },
  );

  test(
    'new installation requires setup unless build explicitly supplies a server',
    () async {
      final repository = FakeServerRepository();
      final cubit = ServerConfigurationCubit(repository);
      await cubit.restore();
      expect(cubit.state.address, isNull);
      expect(cubit.state.loading, isFalse);
      await cubit.close();
      final seeded = ServerConfigurationCubit(
        repository,
        initialAddress: 'http://localhost:8080',
      );
      await seeded.restore();
      expect(seeded.state.address?.value, 'http://localhost:8080');
      expect(repository.saves, isEmpty);
      await seeded.close();
    },
  );

  test('failed probe does not persist or replace the current server', () async {
    final old = ServerAddress.parse('https://old.example.com');
    final repository = FakeServerRepository()
      ..stored = old
      ..onCheck = (_) async =>
          throw const ServerFailure(ServerFailureKind.notReady);
    final cubit = ServerConfigurationCubit(repository);
    await cubit.restore();
    expect(await cubit.connect('https://new.example.com'), isFalse);
    expect(cubit.state.address, old);
    expect(cubit.state.error, contains('not ready'));
    expect(repository.saves, isEmpty);
    await cubit.close();
  });

  test('failed storage keeps current server and offers retry', () async {
    final old = ServerAddress.parse('https://old.example.com');
    final repository = FakeServerRepository()
      ..stored = old
      ..onSave = (_) async =>
          throw const ServerFailure(ServerFailureKind.storage);
    final cubit = ServerConfigurationCubit(repository);
    await cubit.restore();
    expect(await cubit.connect('https://new.example.com'), isFalse);
    expect(cubit.state.address, old);
    expect(cubit.state.busy, isFalse);
    repository.onSave = null;
    expect(await cubit.connect('https://new.example.com'), isTrue);
    expect(cubit.state.address, repository.stored);
    await cubit.close();
  });

  test('pending write cannot be overtaken after its status deadline', () async {
    final pending = Completer<void>();
    final repository = FakeServerRepository()..onSave = (_) => pending.future;
    final cubit = ServerConfigurationCubit(
      repository,
      storageTimeout: const Duration(milliseconds: 5),
    );
    await cubit.restore();
    final connecting = cubit.connect('https://first.example.com');
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(cubit.state.busy, isTrue);
    expect(cubit.state.message, contains('Still saving'));
    expect(await cubit.connect('https://second.example.com'), isFalse);
    expect(repository.saves, hasLength(1));
    pending.complete();
    expect(await connecting, isTrue);
    expect(cubit.state.address?.value, 'https://first.example.com');
    await cubit.close();
  });

  test(
    'late preference read does not override an explicit connection',
    () async {
      final pending = Completer<ServerAddress?>();
      final repository = FakeServerRepository()..onRead = () => pending.future;
      final cubit = ServerConfigurationCubit(
        repository,
        initialAddress: 'http://localhost:8080',
        storageTimeout: const Duration(milliseconds: 5),
      );
      await cubit.restore();
      expect(cubit.state.address, isNull);
      expect(cubit.state.error, isNotNull);
      await cubit.connect('https://selected.example.com');
      pending.complete(ServerAddress.parse('https://stale.example.com'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.address?.value, 'https://selected.example.com');
      await cubit.close();
    },
  );

  test('disposal during check prevents persistence and selection', () async {
    final pending = Completer<void>();
    final repository = FakeServerRepository()..onCheck = (_) => pending.future;
    final cubit = ServerConfigurationCubit(repository);
    await cubit.restore();
    final connecting = cubit.connect('https://new.example.com');
    await cubit.close();
    pending.complete();
    expect(await connecting, isFalse);
    expect(repository.saves, isEmpty);
  });

  test(
    'repository detects corrupt settings and unsuccessful persistence',
    () async {
      final preferences = _Preferences()..value = 'invalid';
      final repository = LocalServerRepository(preferences, _Connection());
      await expectLater(repository.read(), throwsA(isA<ServerFailure>()));
      preferences.value = null;
      preferences.discardWrites = true;
      await expectLater(
        repository.save(ServerAddress.parse('https://example.com')),
        throwsA(isA<ServerFailure>()),
      );
      preferences.discardWrites = false;
      await repository.save(ServerAddress.parse('https://example.com'));
      expect((await repository.read())?.value, 'https://example.com');
    },
  );
}

final class _Preferences implements ServerPreferencesSource {
  String? value;
  bool discardWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (!discardWrites) this.value = value;
  }
}

final class _Connection implements ServerConnectionSource {
  @override
  Future<ServerProbeResult> check(String address) async =>
      ServerProbeResult.ready;
}
