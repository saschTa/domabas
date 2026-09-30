import 'dart:async';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/identity/interfaces/personal_activity_repository.dart';
import '../../../domain/identity/models/personal_activity.dart';
import '../datasources/personal_activity_remote_data_source.dart';

final class RemotePersonalActivityRepository
    implements PersonalActivityRepository {
  RemotePersonalActivityRepository(this._source);
  final PersonalActivityRemoteDataSource _source;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  @override
  void cancelRequests() => _source.cancelRequests();
  @override
  Future<PersonalActivity> getActivity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  }) async {
    try {
      final value = await _source.activity(
        activeCursor: activeCursor,
        finishedCursor: finishedCursor,
        cancel: cancel,
      );
      if (value.active.length > 20 ||
          value.finished.length > 5 ||
          value.activeLimit.toString() != '20' ||
          (value.activeTruncated && value.active.length != 20)) {
        throw const FormatException('Invalid activity bounds');
      }
      final active = value.active.map(_personalActivityItemMapper).toList(),
          finished = value.finished.map(_personalActivityItemMapper).toList();
      if (active.any((item) => !item.active) ||
          finished.any((item) => item.active) ||
          [
                ...active,
                ...finished,
              ].map((item) => '${item.kind}/${item.id}').toSet().length !=
              active.length + finished.length) {
        throw const FormatException('Invalid activity ordering or identity');
      }
      for (var i = 1; i < finished.length; i++) {
        if (finished[i].finishedAt!.isAfter(finished[i - 1].finishedAt!)) {
          throw const FormatException('Invalid activity finish order');
        }
      }
      return PersonalActivity(
        active: active,
        activeNextCursor: value.activeNextCursor,
        finishedNextCursor: value.finishedNextCursor,
        finished: finished,
        activeTruncated: value.activeTruncated,
        generatedAt: value.generatedAt.toUtc(),
      );
    } on api.ApiException catch (error) {
      throw ActivityFailure(switch (error.code) {
        401 => ActivityFailureKind.unauthorized,
        403 => ActivityFailureKind.forbidden,
        499 => ActivityFailureKind.cancelled,
        _ => ActivityFailureKind.unavailable,
      });
    } on TimeoutException {
      throw const ActivityFailure(ActivityFailureKind.unavailable);
    } on http.ClientException {
      throw const ActivityFailure(ActivityFailureKind.unavailable);
    } on FormatException {
      throw const ActivityFailure(ActivityFailureKind.invalidResponse);
    } on TypeError {
      throw const ActivityFailure(ActivityFailureKind.invalidResponse);
    }
  }

  static PersonalActivityItem _personalActivityItemMapper(
    api.PersonalActivityItem value,
  ) {
    final active = {'queued', 'running'}.contains(value.status.toString());
    if (!_uuid.hasMatch(value.id) ||
        !_uuid.hasMatch(value.namespaceId) ||
        value.namespaceName.isEmpty ||
        active != (value.finishedAt == null) ||
        [
          value.documentId,
          value.providerId,
          value.batchId,
        ].whereType<String>().any((id) => !_uuid.hasMatch(id)) ||
        (value.canOpen &&
            value.documentId == null &&
            value.providerId == null &&
            value.batchId == null)) {
      throw const FormatException('Invalid activity item');
    }
    return PersonalActivityItem(
      id: value.id,
      kind: value.kind.toString(),
      namespaceId: value.namespaceId,
      namespaceName: value.namespaceName,
      status: value.status.toString(),
      stage: value.stage,
      createdAt: value.createdAt.toUtc(),
      startedAt: value.startedAt?.toUtc(),
      finishedAt: value.finishedAt?.toUtc(),
      documentId: value.documentId,
      providerId: value.providerId,
      batchId: value.batchId,
      title: value.title,
      failureCode: value.failureCode,
      canOpen: value.canOpen,
    );
  }
}
