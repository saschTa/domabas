import 'dart:async';

import 'package:domabas/domain/document/interfaces/document_processing_repository.dart';
import 'package:domabas/domain/document/models/document_processing.dart';

DocumentPipelineConfiguration testPipelineConfiguration({
  int revision = 1,
  String language = 'eng+deu',
  String segmentation = 'auto',
  bool? propertyExtractionEnabled,
  String? propertyExtractionModel,
  bool? invoiceExtractionEnabled,
  String? invoiceExtractionModel,
}) => DocumentPipelineConfiguration(
  revision: revision,
  language: language,
  segmentation: segmentation,
  ocrEngine: 'tesseract',
  ocrVersion: '5.5.3',
  ocrModel: 'tessdata_fast',
  embeddingModel: 'nomic-embed-text:v1.5',
  embeddingDigest: 'a' * 64,
  embeddingDimensions: 768,
  fingerprint: 'b' * 64,
  manifestRevision: 1,
  extractionRevision: '1',
  chunkingRevision: '1',
  embeddingInputRevision: '1',
  indexingRevision: '1',
  weights: [DocumentProcessingWeight('eng', 'c' * 64)],
  propertyExtractionEnabled: propertyExtractionEnabled,
  propertyExtractionModel: propertyExtractionModel,
  invoiceExtractionEnabled: invoiceExtractionEnabled,
  invoiceExtractionModel: invoiceExtractionModel,
);

DocumentProcessingPipeline testPipeline({
  int revision = 1,
  String language = 'eng+deu',
  String segmentation = 'auto',
  bool? propertyExtractionEnabled,
  String? propertyExtractionModel,
  bool? invoiceExtractionEnabled,
  String? invoiceExtractionModel,
  DocumentProcessingScheduling? scheduling,
}) => DocumentProcessingPipeline(
  configuration: testPipelineConfiguration(
    revision: revision,
    language: language,
    segmentation: segmentation,
    propertyExtractionEnabled: propertyExtractionEnabled,
    propertyExtractionModel: propertyExtractionModel,
    invoiceExtractionEnabled: invoiceExtractionEnabled,
    invoiceExtractionModel: invoiceExtractionModel,
  ),
  ready: true,
  languages: ['eng', 'deu', 'eng+deu'],
  segmentations: ['auto', 'single_block'],
  scheduling: scheduling,
);

DocumentReindexBatch testReindexBatch({
  String id = '11111111-1111-4111-8111-111111111111',
  String scope = 'namespace',
  String status = 'running',
  int revision = 1,
}) => DocumentReindexBatch(
  id: id,
  scope: scope,
  reason: 'manual',
  status: status,
  configurationRevision: revision,
  configurationFingerprint: 'b' * 64,
  createdAt: DateTime.utc(2026, 9, 18),
  enumerationComplete: true,
  discovered: 1,
  waiting: status == 'running' ? 1 : 0,
  running: 0,
  succeeded: status == 'succeeded' ? 1 : 0,
  failed: status == 'completed_with_failures' ? 1 : 0,
  skipped: 0,
  superseded: 0,
);

DocumentProcessingJob testProcessingJob({
  String id = 'job',
  String status = 'running',
  String reason = 'reindex',
  String? stage,
  bool? propertyExtractionEnabled,
  String pipeline = 'ingestion',
  int pipelineVersion = 2,
  int? attempt,
  bool? invoiceExtractionEnabled,
}) => DocumentProcessingJob(
  id: id,
  documentId: '11111111-1111-4111-8111-111111111111',
  documentTitle: 'Invoice',
  generation: 1,
  pipeline: pipeline,
  pipelineVersion: pipelineVersion,
  attempt: attempt,
  reason: reason,
  status: status,
  stage: stage ?? (status == 'succeeded' ? 'complete' : 'extracting'),
  configuration: testPipelineConfiguration(
    propertyExtractionEnabled: propertyExtractionEnabled,
    invoiceExtractionEnabled: invoiceExtractionEnabled,
    propertyExtractionModel: propertyExtractionEnabled == true
        ? 'qwen3.5:4b'
        : null,
  ),
  textSource: 'machine',
  createdAt: DateTime.utc(2026, 9, 18),
  updatedAt: DateTime.utc(2026, 9, 18),
  isCurrent: true,
  documentDeleted: false,
);

final class FakeExternalLinkLauncher implements ExternalLinkLauncher {
  final List<Uri> opened = [];
  bool result = true;
  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

class FakeProcessingRepository implements DocumentProcessingRepository {
  DocumentProcessingPipeline pipeline = testPipeline();
  DocumentProcessingConfiguration? systemConfiguration;
  List<DocumentProcessingJob> jobs = [];
  List<DocumentReindexBatch> namespaceBatches = [], systemBatches = [];
  int cancellations = 0, pipelineReads = 0, systemReads = 0;
  final List<DocumentReindexRequest> namespaceRequests = [],
      systemRequests = [];
  Future<DocumentProcessingPipeline> Function()? onPipeline;
  Future<DocumentProcessingJobPage> Function(String?, String?)? onJobs;
  Future<DocumentProcessingJobPage> Function(String?, String?, String?)?
  onPipelineJobs;
  final List<String?> jobPipelines = [];
  Future<DocumentProcessingJob> Function(String)? onJob;
  Future<DocumentReindexBatchPage> Function(String?)? onNamespaceBatches,
      onSystemBatches;
  Future<DocumentReindexBatch> Function(
    DocumentReindexRequest,
  )? onNamespaceCreate,
      onSystemCreate;
  Future<DocumentProcessingConfiguration> Function()? onConfiguration;
  Future<DocumentProcessingConfiguration> Function(String, String, int?)?
  onUpdate;
  final List<DocumentLLMSettingsDraft?> llmUpdates = [];
  Future<DocumentModelContext> Function(String)? onModelContext;
  @override
  Future<DocumentModelContext> modelContext(
    String model, {
    Future<void>? cancel,
  }) async => onModelContext != null
      ? onModelContext!(model)
      : DocumentModelContext(model: model, maxContextLength: 131072);
  @override
  void cancelRequests() {
    cancellations++;
  }

  @override
  Future<DocumentProcessingPipeline> getNamespacePipeline({
    Future<void>? cancel,
  }) async {
    pipelineReads++;
    return onPipeline != null ? await onPipeline!() : pipeline;
  }

  @override
  Future<DocumentProcessingJobPage> listJobs({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    String? pipeline,
    String? documentId,
    Future<void>? cancel,
  }) async {
    jobPipelines.add(pipeline);
    return onPipelineJobs != null
        ? onPipelineJobs!(cursor, status, pipeline)
        : onJobs != null
        ? onJobs!(cursor, status)
        : DocumentProcessingJobPage(
            counts: {
              for (final job in jobs)
                (job.pipeline, job.status): jobs
                    .where(
                      (v) =>
                          v.pipeline == job.pipeline && v.status == job.status,
                    )
                    .length,
            },
            items: jobs
                .where(
                  (j) =>
                      (!activeOnly || j.active) &&
                      (status == null || j.status == status) &&
                      (pipeline == null || j.pipeline == pipeline) &&
                      (documentId == null || j.documentId == documentId),
                )
                .take(limit),
          );
  }

  @override
  Future<DocumentProcessingJob> getJob(
    String id, {
    Future<void>? cancel,
  }) async {
    if (onJob != null) return onJob!(id);
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    throw const DocumentProcessingFailure(
      DocumentProcessingFailureKind.notFound,
    );
  }

  @override
  Future<DocumentReindexBatchPage> listNamespaceBatches({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) async => onNamespaceBatches != null
      ? onNamespaceBatches!(cursor)
      : DocumentReindexBatchPage(
          counts: {
            for (final batch in namespaceBatches)
              batch.status: namespaceBatches
                  .where((v) => v.status == batch.status)
                  .length,
          },
          items: namespaceBatches
              .where((v) => !activeOnly || v.active)
              .take(limit),
        );
  @override
  Future<DocumentReindexBatchPage> listSystemBatches({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) async => onSystemBatches != null
      ? onSystemBatches!(cursor)
      : DocumentReindexBatchPage(
          counts: {
            for (final batch in systemBatches)
              batch.status: systemBatches
                  .where((v) => v.status == batch.status)
                  .length,
          },
          items: systemBatches
              .where((v) => !activeOnly || v.active)
              .take(limit),
        );
  @override
  Future<DocumentReindexBatch> createNamespaceBatch(
    DocumentReindexRequest request, {
    Future<void>? cancel,
  }) async {
    namespaceRequests.add(request);
    if (onNamespaceCreate != null) return onNamespaceCreate!(request);
    final batch = testReindexBatch(
      id: request.id,
      revision: request.configurationRevision,
    );
    namespaceBatches = [batch, ...namespaceBatches];
    return batch;
  }

  @override
  Future<DocumentReindexBatch> createSystemBatch(
    DocumentReindexRequest request, {
    Future<void>? cancel,
  }) async {
    systemRequests.add(request);
    if (onSystemCreate != null) return onSystemCreate!(request);
    final batch = testReindexBatch(
      id: request.id,
      revision: request.configurationRevision,
      scope: 'system',
    );
    systemBatches = [batch, ...systemBatches];
    return batch;
  }

  @override
  Future<DocumentReindexBatch> getNamespaceBatch(
    String id, {
    Future<void>? cancel,
  }) async => namespaceBatches.firstWhere(
    (b) => b.id == id,
    orElse: () => throw const DocumentProcessingFailure(
      DocumentProcessingFailureKind.notFound,
    ),
  );
  @override
  Future<DocumentReindexBatch> getSystemBatch(
    String id, {
    Future<void>? cancel,
  }) async => systemBatches.firstWhere(
    (b) => b.id == id,
    orElse: () => throw const DocumentProcessingFailure(
      DocumentProcessingFailureKind.notFound,
    ),
  );
  @override
  Future<DocumentProcessingConfiguration> getSystemConfiguration({
    Future<void>? cancel,
  }) async {
    systemReads++;
    return onConfiguration != null
        ? onConfiguration!()
        : systemConfiguration ??
              DocumentProcessingConfiguration(pipeline: pipeline);
  }

  @override
  Future<DocumentProcessingConfiguration> updateSystemConfiguration({
    required String language,
    required String segmentation,
    int? expectedRevision,
    DocumentLLMSettingsDraft? llm,
    Future<void>? cancel,
  }) async {
    llmUpdates.add(llm);
    await delayedSettingsSave?.future;
    if (onUpdate != null) {
      return onUpdate!(language, segmentation, expectedRevision);
    }
    pipeline = testPipeline(
      revision: pipeline.configuration.revision + 1,
      language: language,
      segmentation: segmentation,
      propertyExtractionEnabled:
          llm?.enabled ?? systemConfiguration?.llm.enabled,
      propertyExtractionModel: llm?.model ?? systemConfiguration?.llm.model,
      invoiceExtractionEnabled:
          llm?.invoiceEnabled ?? systemConfiguration?.llm.invoiceEnabled,
      invoiceExtractionModel: llm?.model ?? systemConfiguration?.llm.model,
    );
    final previous =
        systemConfiguration?.llm ?? const DocumentLLMConfiguration();
    return systemConfiguration = DocumentProcessingConfiguration(
      pipeline: pipeline,
      llm: llm == null
          ? previous
          : DocumentLLMConfiguration(
              enabled: llm.enabled,
              invoiceEnabled: llm.invoiceEnabled,
              propertyThinkingEnabled: llm.propertyThinkingEnabled,
              invoiceThinkingEnabled: llm.invoiceThinkingEnabled,
              lmStudioCompatibility: llm.lmStudioCompatibility,
              provider: llm.provider,
              model: llm.model.trim(),
              contextLength: llm.contextLengthValue ?? previous.contextLength,
              baseUrl: llm.provider == 'ollama' ? '' : llm.baseUrl.trim(),
              credentialConfigured:
                  llm.apiKey.isNotEmpty ||
                  (!llm.clearApiKey &&
                      llm.provider == previous.provider &&
                      llm.baseUrl.trim() == previous.baseUrl &&
                      previous.credentialConfigured),
            ),
    );
  }

  Completer<void>? delayedSettingsSave;
}
