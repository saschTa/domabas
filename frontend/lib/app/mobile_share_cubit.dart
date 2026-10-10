import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/document/datasources/mobile_share_data_source.dart';
import '../data/identity/models/session_store_key.dart';
import '../domain/identity/models/identity.dart';
import '../presentation/document/cubits/document_uploads_cubit.dart';
import 'document_upload_coordinator.dart';

final class MobileShareState {
  const MobileShareState({this.batch, this.library, this.canUpload = false});
  final MobileShareBatch? batch;
  final String? library;
  final bool canUpload;
}

final class MobileShareCubit extends Cubit<MobileShareState> {
  MobileShareCubit({
    required this.endpoint,
    required this.uploads,
    required this.source,
    required this.platform,
  }) : super(const MobileShareState()) {
    if (platform == TargetPlatform.android) {
      source.listen(refresh);
      refresh();
    }
  }

  static MobileShareCubit? production(
    String endpoint,
    DocumentUploadCoordinator uploads,
  ) =>
      kIsWeb ||
          !{
            TargetPlatform.android,
            TargetPlatform.iOS,
          }.contains(defaultTargetPlatform)
      ? null
      : MobileShareCubit(
          endpoint: endpoint,
          uploads: uploads,
          source: MobileShareDataSource(),
          platform: defaultTargetPlatform,
        );

  final String endpoint;
  final DocumentUploadCoordinator uploads;
  final MobileShareDataSource source;
  final TargetPlatform platform;
  AuthSession? _session;
  DocumentUploadsCubit? _target;
  bool _busy = true;
  bool _refreshing = false;
  bool _closed = false;
  int _generation = 0;
  final _active = <String>{};
  final _released = <String>{};
  final _subscriptions = <StreamSubscription<DocumentUploadsState>>{};

  void attach(
    AuthSession? session,
    DocumentUploadsCubit? target, {
    required bool busy,
  }) {
    final previous = _session;
    _session = session;
    _target = target;
    _busy = busy;
    if (previous != null && (!identical(previous, session) || busy)) {
      _generation++;
      discard();
    }
    _publish(state.batch);
    final identity = session?.identity;
    final context =
        session == null ||
            busy ||
            !(identity?.allows(IdentityPermission.uploadDocuments) ?? false)
        ? null
        : <String, String>{
            'endpoint': endpoint,
            'credentialKey': '${sessionStoreKey(endpoint)}.credential',
            'tokenHash': sha256.convert(utf8.encode(session.token)).toString(),
            'userId': identity!.userId,
            'accountId': identity.accountId,
          };
    unawaited(source.setSession(context).catchError((Object _) {}));
    if (platform == TargetPlatform.android) {
      refresh();
    }
  }

  void refresh() {
    if (_closed || _refreshing || platform != TargetPlatform.android) return;
    _refreshing = true;
    final generation = _generation;
    unawaited(() async {
      try {
        final batch = await source.pending();
        if (_closed || batch == null || _active.contains(batch.id)) {
          return;
        }
        if (_released.contains(batch.id)) {
          _release(batch.id);
          return;
        }
        if (generation != _generation) {
          _release(batch.id);
          return;
        }
        _publish(batch);
      } catch (_) {
        // A failed platform read leaves the native batch available for resume.
      } finally {
        _refreshing = false;
      }
    }());
  }

  void _publish(MobileShareBatch? batch) {
    if (_closed) return;
    emit(
      MobileShareState(
        batch: batch,
        library: _session?.identity.accountName,
        canUpload:
            !_busy &&
            (_session?.identity.allows(IdentityPermission.uploadDocuments) ??
                false) &&
            (_target?.admissionAllowed ?? false) &&
            batch?.error == null,
      ),
    );
  }

  void confirm() {
    final batch = state.batch;
    final target = _target;
    if (_closed || batch == null || target == null || !state.canUpload) return;
    final ids = uploads.receiveSharedPaths(target, batch.paths);
    if (ids.isEmpty) return;
    _active.add(batch.id);
    _publish(null);
    late final StreamSubscription<DocumentUploadsState> subscription;
    void completed(DocumentUploadsState value) {
      if (value.rows.any(
        (row) => ids.contains(row.candidate.id) && row.pending,
      )) {
        return;
      }
      _subscriptions.remove(subscription);
      unawaited(subscription.cancel());
      _release(batch.id);
    }

    subscription = target.stream.listen(
      completed,
      onDone: () {
        _subscriptions.remove(subscription);
        _release(batch.id);
      },
    );
    _subscriptions.add(subscription);
    completed(target.state);
  }

  void discard() {
    final batch = state.batch;
    if (batch == null) return;
    _publish(null);
    _release(batch.id);
  }

  void _release(String id) {
    _active.remove(id);
    _released.add(id);
    if (_released.length > 32) _released.remove(_released.first);
    unawaited(source.release(id).catchError((Object _) {}));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    discard();
    _closed = true;
    unawaited(source.setSession(null).catchError((Object _) {}));
    for (final subscription in _subscriptions.toList()) {
      await subscription.cancel();
    }
    for (final id in _active.toList()) {
      unawaited(source.release(id).catchError((Object _) {}));
    }
    source.dispose();
    return super.close();
  }
}
