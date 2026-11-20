import 'package:domabas_api/api.dart' as api;

import '../../../domain/document/models/document_processing.dart';

DocumentProcessingScheduling? documentProcessingSchedulingMapper(
  api.DocumentProcessingScheduling? value,
) {
  if (value == null) return null;
  if (value.ingestionConcurrency < 1 ||
      value.aiConcurrency < 1 ||
      value.embeddingQueueSize < 1 ||
      value.providerStepRetries != 4 ||
      value.priorityPolicy.toString() != 'ingestion_first') {
    throw const FormatException('Invalid processing scheduling');
  }
  return DocumentProcessingScheduling(
    ingestionConcurrency: value.ingestionConcurrency,
    aiConcurrency: value.aiConcurrency,
    embeddingQueueSize: value.embeddingQueueSize,
    ingestionConcurrencyMode: value.ingestionConcurrencyMode.toString(),
    aiConcurrencyMode: value.aiConcurrencyMode.toString(),
    providerStepRetries: value.providerStepRetries,
    priorityPolicy: value.priorityPolicy.toString(),
  );
}
