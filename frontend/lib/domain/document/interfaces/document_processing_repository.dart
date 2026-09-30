import '../models/document_processing.dart';

abstract interface class DocumentProcessingRepository {
  Future<DocumentModelContext> modelContext(
    String model, {
    Future<void>? cancel,
  });
  Future<DocumentProcessingPipeline> getNamespacePipeline({
    Future<void>? cancel,
  });
  Future<DocumentProcessingJobPage> listJobs({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    String? pipeline,
    String? documentId,
    Future<void>? cancel,
  });
  Future<DocumentProcessingJob> getJob(String id, {Future<void>? cancel});
  Future<DocumentReindexBatchPage> listNamespaceBatches({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  });
  Future<DocumentReindexBatch> createNamespaceBatch(
    DocumentReindexRequest request, {
    Future<void>? cancel,
  });
  Future<DocumentReindexBatch> getNamespaceBatch(
    String id, {
    Future<void>? cancel,
  });
  Future<DocumentProcessingConfiguration> getSystemConfiguration({
    Future<void>? cancel,
  });
  Future<DocumentProcessingConfiguration> updateSystemConfiguration({
    required String language,
    required String segmentation,
    int? expectedRevision,
    DocumentLLMSettingsDraft? llm,
    Future<void>? cancel,
  });
  Future<DocumentReindexBatchPage> listSystemBatches({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  });
  Future<DocumentReindexBatch> createSystemBatch(
    DocumentReindexRequest request, {
    Future<void>? cancel,
  });
  Future<DocumentReindexBatch> getSystemBatch(
    String id, {
    Future<void>? cancel,
  });
  void cancelRequests();
}

abstract interface class ExternalLinkLauncher {
  Future<bool> open(Uri uri);
}
