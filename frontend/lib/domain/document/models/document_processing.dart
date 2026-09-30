import 'dart:math';

final class DocumentProcessingWeight {
  const DocumentProcessingWeight(this.name, this.sha256);
  final String name;
  final String sha256;
}

final class DocumentPipelineConfiguration {
  DocumentPipelineConfiguration({
    required this.revision,
    required this.language,
    required this.segmentation,
    required this.ocrEngine,
    required this.ocrVersion,
    required this.ocrModel,
    required this.embeddingModel,
    required this.embeddingDigest,
    required this.embeddingDimensions,
    required this.fingerprint,
    required this.manifestRevision,
    required this.extractionRevision,
    required this.chunkingRevision,
    required this.embeddingInputRevision,
    required this.indexingRevision,
    required Iterable<DocumentProcessingWeight> weights,
    this.propertyExtractionEnabled,
    this.propertyExtractionModel,
    this.invoiceExtractionEnabled,
    this.invoiceExtractionModel,
  }) : weights = List.unmodifiable(weights);
  final int revision, embeddingDimensions, manifestRevision;
  final String language, segmentation, ocrEngine, ocrVersion, ocrModel;
  final String embeddingModel, embeddingDigest, fingerprint;
  final String extractionRevision,
      chunkingRevision,
      embeddingInputRevision,
      indexingRevision;
  final List<DocumentProcessingWeight> weights;
  final bool? propertyExtractionEnabled;
  final String? propertyExtractionModel;
  final bool? invoiceExtractionEnabled;
  final String? invoiceExtractionModel;
}

final class DocumentLLMConfiguration {
  const DocumentLLMConfiguration({
    this.enabled = false,
    this.invoiceEnabled = false,
    this.propertyThinkingEnabled = false,
    this.invoiceThinkingEnabled = false,
    this.lmStudioCompatibility = false,
    this.provider = 'ollama',
    this.model = 'qwen3.5:4b',
    this.baseUrl = '',
    this.credentialConfigured = false,
    this.contextLength = 32768,
  });
  final bool enabled,
      invoiceEnabled,
      propertyThinkingEnabled,
      invoiceThinkingEnabled,
      lmStudioCompatibility,
      credentialConfigured;
  final String provider, model, baseUrl;
  final int contextLength;
}

final class DocumentModelContext {
  const DocumentModelContext({
    required this.model,
    required this.maxContextLength,
  });
  final String model;
  final int maxContextLength;
}

final class DocumentLLMSettingsDraft {
  const DocumentLLMSettingsDraft({
    this.enabled = false,
    this.invoiceEnabled = false,
    this.propertyThinkingEnabled = false,
    this.invoiceThinkingEnabled = false,
    this.lmStudioCompatibility = false,
    this.provider = 'ollama',
    this.model = 'qwen3.5:4b',
    this.baseUrl = '',
    this.apiKey = '',
    this.clearApiKey = false,
    this.contextLength = '32768',
  });
  factory DocumentLLMSettingsDraft.fromConfiguration(
    DocumentLLMConfiguration configuration,
  ) => DocumentLLMSettingsDraft(
    enabled: configuration.enabled,
    invoiceEnabled: configuration.invoiceEnabled,
    propertyThinkingEnabled: configuration.propertyThinkingEnabled,
    invoiceThinkingEnabled: configuration.invoiceThinkingEnabled,
    lmStudioCompatibility: configuration.lmStudioCompatibility,
    provider: configuration.provider,
    model: configuration.model,
    baseUrl: configuration.baseUrl,
    contextLength: configuration.contextLength.toString(),
  );
  final bool enabled,
      invoiceEnabled,
      propertyThinkingEnabled,
      invoiceThinkingEnabled,
      lmStudioCompatibility,
      clearApiKey;
  final String provider, model, baseUrl, apiKey, contextLength;
  DocumentLLMSettingsDraft copyWith({
    bool? enabled,
    bool? invoiceEnabled,
    bool? propertyThinkingEnabled,
    bool? invoiceThinkingEnabled,
    bool? lmStudioCompatibility,
    String? provider,
    String? model,
    String? baseUrl,
    String? apiKey,
    bool? clearApiKey,
    String? contextLength,
  }) => DocumentLLMSettingsDraft(
    enabled: enabled ?? this.enabled,
    invoiceEnabled: invoiceEnabled ?? this.invoiceEnabled,
    propertyThinkingEnabled:
        propertyThinkingEnabled ?? this.propertyThinkingEnabled,
    invoiceThinkingEnabled:
        invoiceThinkingEnabled ?? this.invoiceThinkingEnabled,
    lmStudioCompatibility: lmStudioCompatibility ?? this.lmStudioCompatibility,
    provider: provider ?? this.provider,
    model: model ?? this.model,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    clearApiKey: clearApiKey ?? this.clearApiKey,
    contextLength: contextLength ?? this.contextLength,
  );
  bool matches(DocumentLLMConfiguration configuration) =>
      enabled == configuration.enabled &&
      invoiceEnabled == configuration.invoiceEnabled &&
      propertyThinkingEnabled == configuration.propertyThinkingEnabled &&
      invoiceThinkingEnabled == configuration.invoiceThinkingEnabled &&
      lmStudioCompatibility == configuration.lmStudioCompatibility &&
      provider == configuration.provider &&
      model.trim() == configuration.model &&
      (contextLengthValue != null
          ? contextLengthValue == configuration.contextLength
          : provider != 'ollama') &&
      (provider == 'ollama' ? '' : baseUrl.trim()) == configuration.baseUrl;
  bool changed(DocumentLLMConfiguration configuration) =>
      !matches(configuration) || apiKey.isNotEmpty || clearApiKey;
  String? get modelError => model.trim().isEmpty || model.trim().length > 128
      ? 'Enter a model name of up to 128 characters.'
      : null;
  String? get baseUrlError {
    if (provider != 'openai') return null;
    final uri = Uri.tryParse(baseUrl.trim());
    return uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
            baseUrl.trim().length > 2048
        ? 'Enter an HTTP or HTTPS base URL without credentials or query parameters.'
        : null;
  }

  bool get valid =>
      {'ollama', 'openai'}.contains(provider) &&
      modelError == null &&
      (provider != 'ollama' || contextLengthError == null) &&
      baseUrlError == null &&
      apiKeyError == null &&
      !(clearApiKey && apiKey.isNotEmpty);
  String? get apiKeyError =>
      apiKey.length > 4096 || apiKey.contains('\n') || apiKey.contains('\r')
      ? 'Enter a single-line API key of up to 4096 characters.'
      : null;
  int? get contextLengthValue {
    final value = int.tryParse(contextLength.trim());
    return value != null && value >= 1024 && value <= 1048576 ? value : null;
  }

  String? get contextLengthError => contextLengthValue == null
      ? 'Enter a whole number from 1,024 to 1,048,576 tokens.'
      : null;
}

final class DocumentProcessingPipeline {
  DocumentProcessingPipeline({
    required this.configuration,
    required this.ready,
    required Iterable<String> languages,
    required Iterable<String> segmentations,
    this.scheduling,
  }) : languages = List.unmodifiable(languages),
       segmentations = List.unmodifiable(segmentations);
  final DocumentPipelineConfiguration configuration;
  final bool ready;
  final List<String> languages, segmentations;
  final DocumentProcessingScheduling? scheduling;
}

final class DocumentProcessingScheduling {
  const DocumentProcessingScheduling({
    required this.ingestionConcurrency,
    required this.aiConcurrency,
    required this.ollamaQueueSize,
    required this.ingestionConcurrencyMode,
    required this.aiConcurrencyMode,
    required this.providerStepRetries,
    required this.priorityPolicy,
  });

  final int ingestionConcurrency, aiConcurrency, ollamaQueueSize;
  final int providerStepRetries;
  final String ingestionConcurrencyMode, aiConcurrencyMode, priorityPolicy;
}

final class DocumentProcessingConfiguration {
  const DocumentProcessingConfiguration({
    required this.pipeline,
    this.dashboardUrl,
    this.automaticBatchId,
    this.llm = const DocumentLLMConfiguration(),
  });
  final DocumentProcessingPipeline pipeline;
  final Uri? dashboardUrl;
  final String? automaticBatchId;
  final DocumentLLMConfiguration llm;
}

final class DocumentProcessingJob {
  final DocumentInvoiceClassification? invoiceClassification;
  const DocumentProcessingJob({
    this.invoiceClassification,
    required this.id,
    required this.documentId,
    this.documentTitle,
    this.generation,
    required this.reason,
    required this.status,
    required this.stage,
    this.configuration,
    this.textSource,
    this.extractionMethod,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    required this.updatedAt,
    this.failureCode,
    required this.isCurrent,
    required this.documentDeleted,
    this.pipeline = 'ingestion',
    this.attempt,
    this.pipelineVersion = 2,
    this.rendererRevision,
  });
  final String id, documentId, reason, status, stage;
  final String? documentTitle, failureCode, extractionMethod, textSource;
  final int? generation, rendererRevision;
  final String pipeline;
  final int? attempt;
  final int pipelineVersion;
  final DocumentPipelineConfiguration? configuration;
  final DateTime createdAt, updatedAt;
  final DateTime? startedAt, finishedAt;
  final bool isCurrent, documentDeleted;
  String get label =>
      documentTitle ??
      'Document ${documentId.substring(0, min(8, documentId.length))}';
  bool get active => status == 'queued' || status == 'running';
  bool get isAI => pipeline == 'ai';
  bool get isThumbnail => pipeline == 'thumbnail';
  String get pipelineLabel => switch (pipeline) {
    'ai' => 'AI processing',
    'thumbnail' => 'Thumbnail generation',
    _ => 'Document ingestion',
  };
  int get attemptNumber => attempt ?? generation!;
}

final class DocumentAIProcessing {
  final DocumentInvoiceClassification? invoiceClassification;
  const DocumentAIProcessing({
    this.invoiceClassification,
    required this.jobId,
    required this.attempt,
    required this.status,
    required this.stage,
    required this.configurationRevision,
    required this.updatedAt,
    this.failureCode,
    this.startedAt,
    this.finishedAt,
  });
  final String jobId, status, stage;
  final int attempt, configurationRevision;
  final DateTime updatedAt;
  final String? failureCode;
  final DateTime? startedAt, finishedAt;
  bool get active => status == 'queued' || status == 'running';
  bool get canRetry =>
      status == 'failed' ||
      status == 'cancelled' ||
      (status == 'succeeded' && invoiceClassification?.decision == 'uncertain');
}

final class DocumentAIRetryRequest {
  const DocumentAIRetryRequest(this.id, this.configurationRevision);
  final String id;
  final int configurationRevision;
}

final class DocumentReindexBatch {
  const DocumentReindexBatch({
    required this.id,
    required this.scope,
    required this.reason,
    required this.status,
    required this.configurationRevision,
    required this.configurationFingerprint,
    required this.createdAt,
    this.finishedAt,
    required this.enumerationComplete,
    required this.discovered,
    required this.waiting,
    required this.running,
    required this.succeeded,
    required this.failed,
    required this.skipped,
    required this.superseded,
  });
  final String id, scope, reason, status, configurationFingerprint;
  final int configurationRevision,
      discovered,
      waiting,
      running,
      succeeded,
      failed,
      skipped,
      superseded;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final bool enumerationComplete;
  bool get active => status == 'enumerating' || status == 'running';
  int get finished => succeeded + failed + skipped + superseded;
  double? get progress => !enumerationComplete
      ? null
      : discovered == 0
      ? (active ? 0 : 1)
      : (finished / discovered).clamp(0, 1);
}

final class DocumentProcessingJobPage {
  DocumentProcessingJobPage({
    required Iterable<DocumentProcessingJob> items,
    Map<(String, String), int>? counts,
    this.nextCursor,
  }) : items = List.unmodifiable(items),
       counts = counts == null ? null : Map.unmodifiable(counts);
  final List<DocumentProcessingJob> items;
  final String? nextCursor;
  final Map<(String, String), int>? counts;
}

final class DocumentReindexBatchPage {
  DocumentReindexBatchPage({
    Map<String, int>? counts,
    required Iterable<DocumentReindexBatch> items,
    this.nextCursor,
  }) : counts = counts == null ? null : Map.unmodifiable(counts),
       items = List.unmodifiable(items);
  final Map<String, int>? counts;
  final List<DocumentReindexBatch> items;
  final String? nextCursor;
}

final class DocumentReindexRequest {
  const DocumentReindexRequest(this.id, this.configurationRevision);
  final String id;
  final int configurationRevision;
}

String processingRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

enum DocumentProcessingFailureKind {
  unavailable,
  notFound,
  rejected,
  invalidResponse,
  unauthorized,
  forbidden,
  conflict,
  cancelled,
}

final class DocumentProcessingFailure implements Exception {
  const DocumentProcessingFailure(this.kind);
  final DocumentProcessingFailureKind kind;
  String get message => switch (kind) {
    DocumentProcessingFailureKind.unavailable =>
      'The processing server could not be reached. Please try again.',
    DocumentProcessingFailureKind.notFound =>
      'This processing record is no longer available.',
    DocumentProcessingFailureKind.rejected =>
      'Check the processing settings and try again.',
    DocumentProcessingFailureKind.invalidResponse =>
      'The server returned an unexpected processing response.',
    DocumentProcessingFailureKind.unauthorized =>
      'Your session ended. Please sign in again.',
    DocumentProcessingFailureKind.forbidden =>
      'Your role does not allow this processing action.',
    DocumentProcessingFailureKind.conflict =>
      'Processing changed. Refresh the latest settings and requests.',
    DocumentProcessingFailureKind.cancelled => 'The request was cancelled.',
  };
}

final class DocumentInvoiceClassification {
  const DocumentInvoiceClassification({
    required this.decision,
    required this.reason,
    required this.pass,
    required this.inputCharacters,
    required this.sourceCharacters,
  });
  final String decision, reason;
  final int pass, inputCharacters, sourceCharacters;
}
