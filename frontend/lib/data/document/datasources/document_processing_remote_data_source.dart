import 'dart:async';

import 'package:domabas_api/api.dart' as api;

final class DocumentProcessingRemoteDataSource {
  DocumentProcessingRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
  });
  final api.DocumentsApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;

  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.DocumentProcessingPipeline> pipeline({Future<void>? cancel}) =>
      _request(
        (abort) => _api.getNamespaceDocumentProcessing(abortTrigger: abort),
        cancel,
      );
  Future<api.OllamaModelContext> modelContext(
    String model, {
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.getDocumentModelContext(model, abortTrigger: abort),
    cancel,
  );
  Future<api.DocumentJobPage> jobs({
    bool activeOnly = false,
    required int limit,
    String? cursor,
    String? status,
    String? pipeline,
    String? documentId,
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.listDocumentJobs(
      activeOnly: activeOnly ? true : null,
      limit: limit,
      cursor: cursor,
      status: status,
      pipeline: pipeline,
      documentId: documentId,
      abortTrigger: abort,
    ),
    cancel,
  );
  Future<api.DocumentJob> job(String id, {Future<void>? cancel}) =>
      _request((abort) => _api.getDocumentJob(id, abortTrigger: abort), cancel);
  Future<api.DocumentReindexBatchPage> batches({
    bool activeOnly = false,
    required bool system,
    required int limit,
    String? cursor,
    Future<void>? cancel,
  }) => _request(
    (abort) => system
        ? _api.listSystemDocumentReindexBatches(
            activeOnly: activeOnly ? true : null,
            limit: limit,
            cursor: cursor,
            abortTrigger: abort,
          )
        : _api.listDocumentReindexBatches(
            activeOnly: activeOnly ? true : null,
            limit: limit,
            cursor: cursor,
            abortTrigger: abort,
          ),
    cancel,
  );
  Future<api.DocumentReindexBatch> batch(
    String id, {
    required bool system,
    Future<void>? cancel,
  }) => _request(
    (abort) => system
        ? _api.getSystemDocumentReindexBatch(id, abortTrigger: abort)
        : _api.getDocumentReindexBatch(id, abortTrigger: abort),
    cancel,
  );
  Future<api.DocumentReindexBatch> createBatch(
    String id,
    int revision, {
    required bool system,
    Future<void>? cancel,
  }) => _request((abort) {
    final request = api.CreateDocumentReindexBatch(
      requestId: id,
      configurationRevision: revision,
    );
    return system
        ? _api.createSystemDocumentReindexBatch(request, abortTrigger: abort)
        : _api.createDocumentReindexBatch(request, abortTrigger: abort);
  }, cancel);
  Future<api.DocumentProcessingConfiguration> configuration({
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.getDocumentProcessingConfiguration(abortTrigger: abort),
    cancel,
  );
  Future<api.DocumentProcessingConfiguration> update({
    required String language,
    required String segmentation,
    int? revision,
    api.UpdateLLMConfiguration? llm,
    Future<void>? cancel,
  }) => _request(
    (abort) => _api.updateDocumentProcessingConfiguration(
      _DocumentProcessingSettingsUpdate(language, segmentation, revision, llm),
      abortTrigger: abort,
    ),
    cancel,
  );

  Future<T> _request<T>(
    Future<T?> Function(Future<void>) send,
    Future<void>? cancel,
  ) async {
    if (_cancelled) throw api.ApiException(499, 'Cancelled');
    final abort = Completer<void>();
    _requests.add(abort);
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      stop();
    });
    if (cancel != null) unawaited(cancel.then((_) => stop()));
    try {
      final value = await send(abort.future).timeout(timeout);
      if (timedOut) throw TimeoutException('Processing request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (value == null) {
        throw const FormatException('Missing processing response');
      }
      return value;
    } on TypeError {
      throw const FormatException('Invalid processing response');
    } on AssertionError {
      throw const FormatException('Missing processing fields');
    } catch (_) {
      if (timedOut) throw TimeoutException('Processing request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}

final class _DocumentProcessingSettingsUpdate
    extends api.UpdateDocumentProcessingConfiguration {
  _DocumentProcessingSettingsUpdate(
    this.languageValue,
    this.segmentationValue,
    int? revision,
    api.UpdateLLMConfiguration? llm,
  ) : super(
        language:
            api.UpdateDocumentProcessingConfigurationLanguageEnum.fromJson(
              languageValue,
            )!,
        segmentation:
            api.UpdateDocumentProcessingConfigurationSegmentationEnum.fromJson(
              segmentationValue,
            )!,
        expectedRevision: revision,
        llm: llm,
      );
  final String languageValue, segmentationValue;
  @override
  Map<String, dynamic> toJson() => {
    'language': languageValue,
    'segmentation': segmentationValue,
    if (expectedRevision != null) 'expectedRevision': expectedRevision,
    if (llm != null)
      'llm': {
        'enabled': llm!.enabled,
        if (llm!.invoiceEnabled != null) 'invoiceEnabled': llm!.invoiceEnabled,
        if (llm!.propertyThinkingEnabled != null)
          'propertyThinkingEnabled': llm!.propertyThinkingEnabled,
        if (llm!.invoiceThinkingEnabled != null)
          'invoiceThinkingEnabled': llm!.invoiceThinkingEnabled,
        if (llm!.lmStudioCompatibility != null)
          'lmStudioCompatibility': llm!.lmStudioCompatibility,
        'provider': llm!.provider.toString(),
        'model': llm!.model,
        if (llm!.contextLength != null) 'contextLength': llm!.contextLength,
        'baseUrl': llm!.baseUrl,
        if (llm!.apiKey != null) 'apiKey': llm!.apiKey,
        'clearApiKey': llm!.clearApiKey,
      },
  };
}
