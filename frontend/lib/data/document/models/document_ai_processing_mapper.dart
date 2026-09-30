import 'package:domabas_api/api.dart' as api;

import 'document_invoice_classification_mapper.dart';

import '../../../domain/document/models/document_processing.dart';

DocumentAIProcessing documentAIProcessingMapper(
  api.DocumentAIProcessing value,
) {
  final status = value.status.toString();
  final stage = value.stage.toString();
  if (!RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value.jobId) ||
      value.attempt < 1 ||
      value.configurationRevision < 1 ||
      !{
        'queued',
        'running',
        'succeeded',
        'failed',
        'skipped',
        'cancelled',
        'superseded',
      }.contains(status) ||
      !{
        'queued',
        'invoicing',
        'enriching',
        'complete',
        'failed',
      }.contains(stage) ||
      (value.failureCode?.length ?? 0) > 64) {
    throw const FormatException('Invalid AI processing attempt');
  }
  return DocumentAIProcessing(
    invoiceClassification: documentInvoiceClassificationMapper(
      value.invoiceClassification,
    ),
    jobId: value.jobId,
    attempt: value.attempt,
    status: status,
    stage: stage,
    configurationRevision: value.configurationRevision,
    updatedAt: value.updatedAt.toUtc(),
    failureCode: value.failureCode,
    startedAt: value.startedAt?.toUtc(),
    finishedAt: value.finishedAt?.toUtc(),
  );
}
