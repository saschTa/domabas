import 'dart:async';

import 'paperless_job_counts_mapper.dart';

import 'dart:convert';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/paperless/models/paperless.dart';
import '../../../domain/paperless/interfaces/paperless_repository.dart';
import '../datasources/paperless_remote_data_source.dart';

final class RemotePaperlessRepository implements PaperlessRepository {
  RemotePaperlessRepository(this._source);
  final PaperlessRemoteDataSource _source;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  @override
  void cancelRequests() => _source.cancelRequests();
  @override
  Future<PaperlessOptions> options({Future<void>? cancel}) =>
      _translate(() async {
        final v = await _source.options(cancel);
        if (v.pageSize < 1 || v.pageSize > 100) {
          throw const FormatException('Invalid options');
        }
        return PaperlessOptions(pageSize: v.pageSize);
      });
  @override
  Future<PaperlessRunPage> runs({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) => _translate(() async {
    final v = await _source.runs(limit, cursor, status, activeOnly, cancel);
    if (v.items.length > limit ||
        v.items.map((r) => r.id).toSet().length != v.items.length) {
      throw const FormatException('Invalid runs');
    }
    _cursor(v.nextCursor, cursor, v.items.isEmpty);
    return PaperlessRunPage(
      v.items.map(_paperlessRunMapper),
      counts: paperlessJobCountsMapper(v.counts),
      nextCursor: v.nextCursor,
    );
  });
  @override
  Future<PaperlessRun> get(String id, {Future<void>? cancel}) =>
      _translate(() async => _matching(await _source.get(id, cancel), id));
  @override
  Future<PaperlessRun> start(
    String requestId,
    PaperlessConnection connection, {
    Future<void>? cancel,
  }) => _translate(
    () async => _matching(
      await _source.start(
        api.StartPaperlessRun(
          requestId: requestId,
          serverUrl: connection.serverUrl,
          token: connection.token,
        ),
        cancel,
      ),
      requestId,
    ),
  );
  @override
  Future<PaperlessRun> cancelRun(String id, {Future<void>? cancel}) =>
      _translate(
        () async => _matching(await _source.cancelRun(id, cancel), id),
      );
  PaperlessRun _matching(api.PaperlessRun v, String id) {
    if (v.id != id) throw const FormatException('Mismatched run');
    return _paperlessRunMapper(v);
  }

  PaperlessRun _paperlessRunMapper(api.PaperlessRun v) {
    if (!_uuid.hasMatch(v.id) ||
        !{
          'queued',
          'running',
          'succeeded',
          'failed',
          'cancelled',
        }.contains(v.state.toString()) ||
        !{
          'queued',
          'discovering',
          'importing',
          'complete',
        }.contains(v.stage.toString()) ||
        v.discovered < 0 ||
        v.imported < 0 ||
        v.duplicates < 0 ||
        v.failed < 0 ||
        v.imported + v.duplicates + v.failed > v.discovered ||
        v.outcomes.length > 100) {
      throw const FormatException('Invalid import');
    }
    return PaperlessRun(
      id: v.id,
      serverUrl: v.serverUrl,
      state: v.state.toString(),
      stage: v.stage.toString(),
      discovered: v.discovered,
      imported: v.imported,
      duplicates: v.duplicates,
      failed: v.failed,
      cancelRequested: v.cancelRequested,
      createdAt: v.createdAt,
      updatedAt: v.updatedAt,
      failureCode: v.failureCode,
      outcomes: v.outcomes.map(_paperlessOutcomeMapper),
    );
  }

  PaperlessOutcome _paperlessOutcomeMapper(api.PaperlessOutcome o) {
    if (o.sourceId < 1 ||
        !{'imported', 'duplicate', 'failed'}.contains(o.status.toString()) ||
        (o.documentId != null && !_uuid.hasMatch(o.documentId!))) {
      throw const FormatException('Invalid outcome');
    }
    return PaperlessOutcome(
      sourceId: o.sourceId,
      title: o.title,
      status: o.status.toString(),
      failureCode: o.failureCode,
      documentId: o.documentId,
    );
  }

  void _cursor(String? next, String? previous, bool empty) {
    if (next != null &&
        (next.isEmpty || next.length > 4096 || next == previous || empty)) {
      throw const FormatException('Invalid continuation');
    }
  }

  @override
  Future<PaperlessOutcomePage> outcomes(
    String id, {
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) => _translate(() async {
    final value = await _source.outcomes(id, limit, cursor, status, cancel);
    if (value.items.length > limit ||
        value.items.map((v) => v.sourceId).toSet().length !=
            value.items.length) {
      throw const FormatException('Invalid outcomes');
    }
    _cursor(value.nextCursor, cursor, value.items.isEmpty);
    return PaperlessOutcomePage(
      value.items.map(_paperlessOutcomeMapper),
      nextCursor: value.nextCursor,
    );
  });

  Future<T> _translate<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on api.ApiException catch (e) {
      if (e.code == 401) throw const PaperlessFailure('unauthorized');
      if (e.code == 403) throw const PaperlessFailure('forbidden');
      if (e.code == 499) throw const PaperlessFailure('cancelled');
      if (e.code == 0 || e.code >= 500) {
        throw const PaperlessFailure('unavailable');
      }
      var code = 'unavailable';
      try {
        final body = jsonDecode(e.message ?? '');
        if (body is Map && body['code'] is String) {
          code = body['code'] as String;
        }
      } on FormatException {
        code = 'unavailable';
      }
      throw PaperlessFailure(code);
    } on FormatException {
      throw const PaperlessFailure('unavailable');
    } on TimeoutException {
      throw const PaperlessFailure('unavailable');
    } on http.ClientException {
      throw const PaperlessFailure('unavailable');
    }
  }
}
