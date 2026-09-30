import 'dart:async';

import 'document_job_counts_mapper.dart';
import '../models/document_invoice_classification_mapper.dart';
import 'document_processing_scheduling_mapper.dart';
import 'document_model_context_mapper.dart';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/document/interfaces/document_processing_repository.dart';
import '../../../domain/document/models/document_processing.dart';
import '../datasources/document_processing_remote_data_source.dart';
import '../models/response_size_exception.dart';

final class RemoteDocumentProcessingRepository
    implements DocumentProcessingRepository {
  RemoteDocumentProcessingRepository(this._source);
  final DocumentProcessingRemoteDataSource _source;
  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  @override
  void cancelRequests() => _source.cancelRequests();

  @override
  Future<DocumentModelContext> modelContext(
    String model, {
    Future<void>? cancel,
  }) => _translate(
    () async => documentModelContextMapper(
      await _source.modelContext(model, cancel: cancel),
      model,
    ),
  );

  @override
  Future<DocumentProcessingPipeline> getNamespacePipeline({
    Future<void>? cancel,
  }) => _translate(() async {
    final value = await _source.pipeline(cancel: cancel);
    return _documentProcessingPipelineMapper(
      _documentPipelineConfigurationMapper(value.configuration.toJson()),
      value.ready,
      value.languages.map((v) => v.toString()),
      value.segmentations.map((v) => v.toString()),
      documentProcessingSchedulingMapper(value.scheduling),
    );
  });
  @override
  Future<DocumentProcessingJobPage> listJobs({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    String? pipeline,
    String? documentId,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.jobs(
      activeOnly: activeOnly,
      limit: limit,
      cursor: cursor,
      status: status,
      pipeline: pipeline,
      documentId: documentId,
      cancel: cancel,
    );
    final items = page.items.map(_documentProcessingJobMapper).toList();
    _page(items.map((item) => item.id), limit);
    return DocumentProcessingJobPage(
      counts: documentJobCountsMapper(page.counts),
      items: items,
      nextCursor: _cursor(page.nextCursor),
    );
  });
  @override
  Future<DocumentProcessingJob> getJob(String id, {Future<void>? cancel}) =>
      _translate(() async {
        final value = _documentProcessingJobMapper(
          await _source.job(id, cancel: cancel),
        );
        if (value.id != id) {
          throw const FormatException('Job identity mismatch');
        }
        return value;
      });
  @override
  Future<DocumentReindexBatchPage> listNamespaceBatches({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) => _batches(false, limit, cursor, activeOnly, cancel);
  @override
  Future<DocumentReindexBatchPage> listSystemBatches({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) => _batches(true, limit, cursor, activeOnly, cancel);
  Future<DocumentReindexBatchPage> _batches(
    bool system,
    int limit,
    String? cursor,
    bool activeOnly,
    Future<void>? cancel,
  ) => _translate(() async {
    final page = await _source.batches(
      activeOnly: activeOnly,
      system: system,
      limit: limit,
      cursor: cursor,
      cancel: cancel,
    );
    final items = page.items
        .map((item) => _documentReindexBatchMapper(item, system))
        .toList();
    _page(items.map((item) => item.id), limit);
    return DocumentReindexBatchPage(
      counts: documentReindexCountsMapper(page.counts),
      items: items,
      nextCursor: _cursor(page.nextCursor),
    );
  });
  @override
  Future<DocumentReindexBatch> getNamespaceBatch(
    String id, {
    Future<void>? cancel,
  }) => _getBatch(id, false, cancel);
  @override
  Future<DocumentReindexBatch> getSystemBatch(
    String id, {
    Future<void>? cancel,
  }) => _getBatch(id, true, cancel);
  Future<DocumentReindexBatch> _getBatch(
    String id,
    bool system,
    Future<void>? cancel,
  ) => _translate(() async {
    final result = _documentReindexBatchMapper(
      await _source.batch(id, system: system, cancel: cancel),
      system,
    );
    if (result.id != id) throw const FormatException('Batch identity mismatch');
    return result;
  });
  @override
  Future<DocumentReindexBatch> createNamespaceBatch(
    DocumentReindexRequest request, {
    Future<void>? cancel,
  }) => _createBatch(request, false, cancel);
  @override
  Future<DocumentReindexBatch> createSystemBatch(
    DocumentReindexRequest request, {
    Future<void>? cancel,
  }) => _createBatch(request, true, cancel);
  Future<DocumentReindexBatch> _createBatch(
    DocumentReindexRequest request,
    bool system,
    Future<void>? cancel,
  ) => _translate(() async {
    final value = _documentReindexBatchMapper(
      await _source.createBatch(
        request.id,
        request.configurationRevision,
        system: system,
        cancel: cancel,
      ),
      system,
    );
    if (value.id != request.id ||
        value.configurationRevision != request.configurationRevision) {
      throw const FormatException('Accepted batch mismatch');
    }
    return value;
  });
  @override
  Future<DocumentProcessingConfiguration> getSystemConfiguration({
    Future<void>? cancel,
  }) => _translate(
    () async => _documentProcessingConfigurationMapper(
      await _source.configuration(cancel: cancel),
    ),
  );
  @override
  Future<DocumentProcessingConfiguration> updateSystemConfiguration({
    required String language,
    required String segmentation,
    int? expectedRevision,
    DocumentLLMSettingsDraft? llm,
    Future<void>? cancel,
  }) => _translate(
    () async => _documentProcessingConfigurationMapper(
      await _source.update(
        language: language,
        segmentation: segmentation,
        revision: expectedRevision,
        llm: llm == null
            ? null
            : api.UpdateLLMConfiguration(
                enabled: llm.enabled,
                invoiceEnabled: llm.invoiceEnabled,
                propertyThinkingEnabled: llm.propertyThinkingEnabled,
                invoiceThinkingEnabled: llm.invoiceThinkingEnabled,
                lmStudioCompatibility: llm.lmStudioCompatibility,
                provider: api.UpdateLLMConfigurationProviderEnum.fromJson(
                  llm.provider,
                )!,
                model: llm.model.trim(),
                contextLength: llm.contextLengthValue,
                baseUrl: llm.provider == 'ollama' ? '' : llm.baseUrl.trim(),
                apiKey: llm.provider == 'openai' && llm.apiKey.isNotEmpty
                    ? llm.apiKey
                    : null,
                clearApiKey: llm.clearApiKey,
              ),
        cancel: cancel,
      ),
    ),
  );

  static DocumentProcessingConfiguration _documentProcessingConfigurationMapper(
    api.DocumentProcessingConfiguration value,
  ) {
    Uri? dashboard;
    if (value.dashboardUrl case final String url) {
      dashboard = Uri.tryParse(url);
      if (dashboard == null ||
          !{'http', 'https'}.contains(dashboard.scheme) ||
          dashboard.host.isEmpty ||
          dashboard.userInfo.isNotEmpty ||
          dashboard.hasQuery ||
          dashboard.hasFragment ||
          (dashboard.hasPort &&
              (dashboard.port < 1 || dashboard.port > 65535))) {
        throw const FormatException('Invalid dashboard URL');
      }
    }
    if (value.automaticBatchId != null &&
        !_uuid.hasMatch(value.automaticBatchId!)) {
      throw const FormatException('Invalid automatic batch');
    }
    return DocumentProcessingConfiguration(
      pipeline: _documentProcessingPipelineMapper(
        _documentPipelineConfigurationMapper({
          ...value.toJson(),
          if (value.llm != null) ...{
            'propertyExtractionEnabled': value.llm!.enabled,
            'propertyExtractionModel': value.llm!.model,
            'invoiceExtractionEnabled': value.llm!.invoiceEnabled,
            'invoiceExtractionModel': value.llm!.model,
          },
        }),
        value.ready,
        value.languages.map((v) => v.toString()),
        value.segmentations.map((v) => v.toString()),
        documentProcessingSchedulingMapper(value.scheduling),
      ),
      dashboardUrl: dashboard,
      automaticBatchId: value.automaticBatchId,
      llm: _documentLlmConfigurationMapper(value.llm),
    );
  }

  static DocumentLLMConfiguration _documentLlmConfigurationMapper(
    api.LLMConfiguration? value,
  ) {
    if (value == null) return const DocumentLLMConfiguration();
    final config = DocumentLLMConfiguration(
      enabled: value.enabled,
      invoiceEnabled: value.invoiceEnabled,
      propertyThinkingEnabled: value.propertyThinkingEnabled,
      invoiceThinkingEnabled: value.invoiceThinkingEnabled,
      lmStudioCompatibility: value.lmStudioCompatibility,
      provider: value.provider.toString(),
      model: value.model,
      baseUrl: value.baseUrl,
      credentialConfigured: value.credentialConfigured,
      contextLength: value.contextLength,
    );
    if (!DocumentLLMSettingsDraft.fromConfiguration(config).valid) {
      throw const FormatException('Invalid property extraction settings');
    }
    return config;
  }

  static DocumentProcessingPipeline _documentProcessingPipelineMapper(
    DocumentPipelineConfiguration config,
    bool ready,
    Iterable<String> languages,
    Iterable<String> segmentations,
    DocumentProcessingScheduling? scheduling,
  ) {
    final l = languages.toList(), s = segmentations.toList();
    if (l.isEmpty ||
        l.length > 3 ||
        !l.contains(config.language) ||
        l.toSet().length != l.length ||
        l.any((v) => !{'eng', 'deu', 'eng+deu'}.contains(v)) ||
        s.isEmpty ||
        s.length > 2 ||
        !s.contains(config.segmentation) ||
        s.toSet().length != s.length ||
        s.any((v) => !{'auto', 'single_block'}.contains(v))) {
      throw const FormatException('Invalid supported settings');
    }
    return DocumentProcessingPipeline(
      configuration: config,
      ready: ready,
      languages: l,
      segmentations: s,
      scheduling: scheduling,
    );
  }

  static DocumentPipelineConfiguration _documentPipelineConfigurationMapper(
    Map<String, dynamic> fields,
  ) {
    String text(String key, int maximum) {
      final value = fields[key]?.toString() ?? '';
      if (value.isEmpty || value.length > maximum) {
        throw const FormatException('Invalid configuration value');
      }
      return value;
    }

    final revision = fields['revision'] as int,
        manifest = fields['manifestRevision'] as int;
    final dimensions = fields['embeddingDimensions'] as int;
    final fingerprint = text('fingerprint', 64),
        digest = text('embeddingDigest', 64);
    final language = text('language', 16),
        segmentation = text('segmentation', 32);
    final weights =
        (fields['ocrWeights'] as Iterable<api.DocumentProcessingWeight>)
            .map((value) => DocumentProcessingWeight(value.name, value.sha256))
            .toList();
    if (revision < 1 ||
        manifest < 1 ||
        dimensions != 768 ||
        !_hash.hasMatch(fingerprint) ||
        !_hash.hasMatch(digest) ||
        !{'eng', 'deu', 'eng+deu'}.contains(language) ||
        !{'auto', 'single_block'}.contains(segmentation) ||
        weights.isEmpty ||
        weights.length > 16 ||
        weights.map((w) => w.name).toSet().length != weights.length ||
        weights.any(
          (w) =>
              w.name.isEmpty || w.name.length > 64 || !_hash.hasMatch(w.sha256),
        )) {
      throw const FormatException('Invalid configuration snapshot');
    }
    return DocumentPipelineConfiguration(
      revision: revision,
      language: language,
      segmentation: segmentation,
      ocrEngine: text('ocrEngine', 64),
      ocrVersion: text('ocrVersion', 64),
      ocrModel: text('ocrModel', 128),
      embeddingModel: text('embeddingModel', 128),
      embeddingDigest: digest,
      embeddingDimensions: dimensions,
      fingerprint: fingerprint,
      manifestRevision: manifest,
      extractionRevision: text('extractionRevision', 64),
      chunkingRevision: text('chunkingRevision', 64),
      embeddingInputRevision: text('embeddingInputRevision', 64),
      indexingRevision: text('indexingRevision', 64),
      weights: weights,
      propertyExtractionEnabled: fields['propertyExtractionEnabled'] as bool?,
      propertyExtractionModel: fields['propertyExtractionModel'] as String?,
      invoiceExtractionEnabled: fields['invoiceExtractionEnabled'] as bool?,
      invoiceExtractionModel: fields['invoiceExtractionModel'] as String?,
    );
  }

  static DocumentProcessingJob _documentProcessingJobMapper(
    api.DocumentJob value,
  ) {
    final thumbnail = value.pipeline.toString() == 'thumbnail';
    final config = thumbnail
        ? null
        : value.configuration == null
        ? throw const FormatException('Missing job configuration')
        : _documentPipelineConfigurationMapper(value.configuration!.toJson());
    final status = value.status.toString(),
        reason = value.reason.toString(),
        stage = value.stage.toString();
    if (!_uuid.hasMatch(value.id) ||
        !_uuid.hasMatch(value.documentId) ||
        !{'ingestion', 'ai', 'thumbnail'}.contains(value.pipeline.toString()) ||
        (value.attempt != null && value.attempt! < 1) ||
        (thumbnail &&
            ((value.attempt ?? 0) < 1 ||
                (value.rendererRevision ?? 0) < 1 ||
                !{'automatic', 'retry'}.contains(reason) ||
                !{
                  'queued',
                  'rendering',
                  'complete',
                  'failed',
                }.contains(stage))) ||
        (!thumbnail &&
            ((value.generation ?? 0) < 1 ||
                value.textSource == null ||
                config!.revision != value.configurationRevision ||
                config.fingerprint != value.configurationFingerprint)) ||
        (value.documentTitle?.runes.length ?? 0) > 200 ||
        !{
          'queued',
          'running',
          'succeeded',
          'failed',
          'superseded',
          'cancelled',
          'skipped',
        }.contains(status) ||
        !{
          'upload',
          'retry',
          'ocr_correction',
          'reindex',
          'legacy',
          'configuration_change',
          'automatic',
        }.contains(reason) ||
        !{
          'queued',
          'extracting',
          'enriching',
          'invoicing',
          'embedding',
          'finalizing',
          'complete',
          'failed',
          'rendering',
        }.contains(stage) ||
        (value.documentDeleted && value.documentTitle != null)) {
      throw const FormatException('Invalid job');
    }
    return DocumentProcessingJob(
      invoiceClassification: documentInvoiceClassificationMapper(
        value.invoiceClassification,
      ),
      id: value.id,
      documentId: value.documentId,
      documentTitle: value.documentTitle,
      generation: value.generation,
      reason: reason,
      status: status,
      stage: stage,
      configuration: config,
      textSource: value.textSource?.toString(),
      extractionMethod: value.extractionMethod?.toString(),
      createdAt: value.createdAt.toUtc(),
      startedAt: value.startedAt?.toUtc(),
      finishedAt: value.finishedAt?.toUtc(),
      updatedAt: value.updatedAt.toUtc(),
      failureCode: value.failureCode,
      isCurrent: value.isCurrent,
      documentDeleted: value.documentDeleted,
      pipeline: value.pipeline.toString(),
      attempt: value.attempt,
      pipelineVersion: value.pipelineVersion ?? 1,
      rendererRevision: value.rendererRevision,
    );
  }

  static DocumentReindexBatch _documentReindexBatchMapper(
    api.DocumentReindexBatch value,
    bool system,
  ) {
    final counts = [
      value.waiting,
      value.running,
      value.succeeded,
      value.failed,
      value.skipped,
      value.superseded,
    ];
    if (!_uuid.hasMatch(value.id) ||
        value.scope.toString() != (system ? 'system' : 'namespace') ||
        value.configurationRevision < 1 ||
        !_hash.hasMatch(value.configurationFingerprint) ||
        value.discovered < 0 ||
        counts.any((n) => n < 0) ||
        counts.fold(0, (a, b) => a + b) != value.discovered) {
      throw const FormatException('Invalid reindex batch');
    }
    return DocumentReindexBatch(
      id: value.id,
      scope: value.scope.toString(),
      reason: value.reason.toString(),
      status: value.status.toString(),
      configurationRevision: value.configurationRevision,
      configurationFingerprint: value.configurationFingerprint,
      createdAt: value.createdAt.toUtc(),
      finishedAt: value.finishedAt?.toUtc(),
      enumerationComplete: value.enumerationComplete,
      discovered: value.discovered,
      waiting: value.waiting,
      running: value.running,
      succeeded: value.succeeded,
      failed: value.failed,
      skipped: value.skipped,
      superseded: value.superseded,
    );
  }

  static String? _cursor(String? value) {
    if (value != null && (value.isEmpty || value.length > 4096)) {
      throw const FormatException('Invalid processing cursor');
    }
    return value;
  }

  static void _page(Iterable<String> ids, int limit) {
    if (ids.length > limit || ids.toSet().length != ids.length) {
      throw const FormatException('Invalid processing page');
    }
  }

  static Future<T> _translate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on api.ApiException catch (error) {
      if (error.innerException != null || error.code >= 500) {
        throw const DocumentProcessingFailure(
          DocumentProcessingFailureKind.unavailable,
        );
      }
      throw DocumentProcessingFailure(switch (error.code) {
        401 => DocumentProcessingFailureKind.unauthorized,
        403 => DocumentProcessingFailureKind.forbidden,
        404 => DocumentProcessingFailureKind.notFound,
        409 => DocumentProcessingFailureKind.conflict,
        499 => DocumentProcessingFailureKind.cancelled,
        400 || 413 || 415 || 422 => DocumentProcessingFailureKind.rejected,
        _ => DocumentProcessingFailureKind.invalidResponse,
      });
    } on TimeoutException {
      throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.unavailable,
      );
    } on ResponseSizeException {
      throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.invalidResponse,
      );
    } on http.ClientException {
      throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.unavailable,
      );
    } on FormatException {
      throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.invalidResponse,
      );
    } on TypeError {
      throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.invalidResponse,
      );
    }
  }
}
