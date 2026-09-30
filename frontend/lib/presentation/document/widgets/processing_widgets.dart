import 'package:flutter/material.dart';

import '../../../domain/document/models/document_processing.dart';
import '../../../ui/domabas_ui.dart';

String processingLabel(String value) => switch (value) {
  'queued' => 'Queued',
  'running' => 'Running',
  'succeeded' => 'Succeeded',
  'failed' => 'Failed',
  'superseded' => 'Superseded',
  'cancelled' => 'Cancelled',
  'skipped' => 'Skipped',
  'enumerating' => 'Finding originals',
  'completed_with_failures' => 'Completed with failures',
  'upload' => 'Upload',
  'retry' => 'Retry',
  'ocr_correction' => 'OCR correction',
  'reindex' => 'Reindex',
  'legacy' => 'Retained processing',
  'configuration_change' => 'Pipeline changed',
  'adoption' => 'Pipeline update',
  'manual' => 'Requested reindex',
  'automatic' => 'Automatic discovery',
  'eng' => 'English',
  'deu' => 'German',
  'eng+deu' => 'English + German',
  'auto' => 'Automatic layout',
  'single_block' => 'Single text block',
  'extracting' => 'Extracting text',
  'enriching' => 'Extracting properties',
  'invoicing' => 'Checking and extracting invoice',
  'embedding' => 'Building embeddings',
  'finalizing' => 'Publishing',
  'complete' => 'Complete',
  'discovering' => 'Finding items',
  'fetching' => 'Fetching emails',
  'importing' => 'Importing originals',
  'rendering' => 'Rendering thumbnail',
  _ => value,
};
AppTone processingTone(String status) => switch (status) {
  'succeeded' => AppTone.success,
  'failed' => AppTone.danger,
  'completed_with_failures' || 'superseded' || 'cancelled' => AppTone.warning,
  _ => AppTone.neutral,
};
String processingTime(DateTime value) =>
    value.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first;
String processingFailure(String? code) => switch (code) {
  'configuration_unavailable' =>
    'This run needs a pipeline configuration that is no longer available.',
  'inference_unavailable' => 'The model service was unavailable.',
  'property_extraction_unavailable' =>
    'The property extraction service was unavailable.',
  'property_extraction_invalid' =>
    'The property extraction service returned an invalid result.',
  'storage_unavailable' => 'The original could not be read from storage.',
  'invalid_file' => 'The original could not be processed.',
  'invalid_classification' =>
    'The model returned an invalid invoice decision. Extraction was not run.',
  'output_limit' => 'The model reached its output limit before finishing. Try again or select another model.',
  'empty_response' => 'The model finished without a final answer.',
  'response_too_large' => 'The model response exceeded the size limit.',
  'invalid_invoice' => 'The invoice data could not be read. Check the original document before retrying.',
  'encrypted_pdf' =>
    'Open the document and enter its PDF password to continue.',
  'resource_limit' => 'The original exceeded processing limits.',
  'no_text' => 'No text could be extracted from the original.',
  'processing_timeout' ||
  'delivery_timeout' => 'This attempt reached its time limit.',
  'document_deleted' => 'The document was deleted.',
  'processing_cancelled' => 'This processing attempt was cancelled.',
  'processing_terminated' => 'This processing attempt was terminated.',
  'thumbnail_unavailable' => 'The thumbnail service was unavailable.',
  'thumbnail_invalid' => 'The thumbnail service returned an invalid preview.',
  'obsolete' =>
    'This thumbnail attempt no longer matches the current original.',
  'unsupported_media' => 'This original cannot be used to create a thumbnail.',
  _ => 'This attempt could not finish. The job history preserves its outcome.',
};

final class DocumentThumbnailPipelineDiagram extends StatelessWidget {
  const DocumentThumbnailPipelineDiagram({super.key, this.job});

  final DocumentProcessingJob? job;

  @override
  Widget build(BuildContext context) {
    final rendering = job?.stage == 'rendering';
    final succeeded = job?.status == 'succeeded';
    String? status(int index) {
      if (job == null) return null;
      if (succeeded) return 'Complete';
      if (index == 0 && rendering) return 'Complete';
      if (index == 1 && rendering) {
        if (job!.status == 'running') return 'In progress';
        if (job!.status == 'failed') return 'Stopped here';
      }
      if (job!.active) return 'Waiting';
      if (job!.status == 'superseded') return 'Superseded';
      return rendering ? 'Not completed' : 'Not recorded';
    }

    const stages = <(IconData, String, String)>[
      (
        Icons.insert_drive_file_outlined,
        'Original',
        'A retained PDF, PNG or JPEG original',
      ),
      (
        Icons.image_outlined,
        'Render thumbnail',
        'Create and save a preview from the first PDF page or image',
      ),
      (
        Icons.photo_library_outlined,
        'Thumbnail ready',
        'Available on document collection cards',
      ),
    ];
    return AppPipelineDiagram(
      stageKeyPrefix: 'thumbnail-pipeline-stage',
      steps: [
        for (var i = 0; i < stages.length; i++)
          AppPipelineStep(
            icon: stages[i].$1,
            title: stages[i].$2,
            description: stages[i].$3,
            status: status(i),
            current: i == 1 && rendering && job?.status == 'running',
            failed: i == 1 && rendering && job?.status == 'failed',
          ),
      ],
    );
  }
}

final class PipelineDiagram extends StatelessWidget {
  const PipelineDiagram({
    super.key,
    required this.configuration,
    this.job,
    this.onEditExtraction,
  });
  final DocumentPipelineConfiguration configuration;
  final DocumentProcessingJob? job;
  final VoidCallback? onEditExtraction;
  @override
  Widget build(BuildContext context) {
    if (job != null && (job!.pipelineVersion == 1 || job!.reason == 'legacy')) {
      return _LegacyDocumentPipelineDiagram(
        configuration: configuration,
        job: job,
      );
    }
    final current = switch (job?.stage) {
      'extracting' => 1,
      'embedding' => 2,
      'finalizing' => 3,
      'complete' => 4,
      _ => 0,
    };
    final correction = job?.reason == 'ocr_correction';
    final stages = <(IconData, String, String)>[
      (
        Icons.insert_drive_file_outlined,
        'Original',
        'PDF, image, or email kept in your library',
      ),
      (
        Icons.document_scanner_outlined,
        job?.extractionMethod == 'mime'
            ? 'Email text extraction'
            : 'OCR / extraction',
        correction
            ? 'Your saved OCR correction stays in use; extraction is not repeated'
            : job?.extractionMethod == 'mime'
            ? 'MIME body text · domabas-mime 1'
            : job != null && job!.extractionMethod == null
            ? 'Extraction method not recorded'
            : '${configuration.ocrEngine} ${configuration.ocrVersion} · ${processingLabel(configuration.language)}',
      ),
      (
        Icons.hub_outlined,
        'Embeddings',
        '${configuration.embeddingModel} · text is indexed when available',
      ),
      (
        Icons.search_rounded,
        'Searchable',
        'Publish the original, text and index before AI processing',
      ),
    ];
    return AppPipelineDiagram(
      steps: [
        for (var i = 0; i < stages.length; i++)
          AppPipelineStep(
            icon: stages[i].$1,
            title: stages[i].$2,
            description: stages[i].$3,
            current: job?.status == 'running' && current == i,
            failed: job?.status == 'failed' && current == i,
            status: correction && i == 1
                ? 'Not repeated'
                : job == null
                ? null
                : job!.status == 'failed' && current == i
                ? 'Stopped here'
                : job!.status == 'running' && current == i
                ? 'In progress'
                : current > i || job!.status == 'succeeded'
                ? 'Complete'
                : job!.active
                ? 'Waiting'
                : 'Not completed',
          ),
      ],
    );
  }
}

final class DocumentAIPipelineDiagram extends StatelessWidget {
  const DocumentAIPipelineDiagram({
    super.key,
    required this.configuration,
    this.job,
    this.onEditExtraction,
  });
  final DocumentPipelineConfiguration configuration;
  final DocumentProcessingJob? job;
  final VoidCallback? onEditExtraction;
  @override
  Widget build(BuildContext context) {
    final invoiceEnabled = configuration.invoiceExtractionEnabled;
    final propertiesEnabled = configuration.propertyExtractionEnabled;
    final stages = <(IconData, String, String)>[
      (
        Icons.receipt_long_outlined,
        invoiceEnabled == false
            ? 'Structured invoice extraction'
            : 'Invoice extraction',
        invoiceEnabled == true
            ? 'AI enabled · ${configuration.invoiceExtractionModel ?? 'Configured model'} · embedded XML takes priority'
            : invoiceEnabled == false
            ? 'Embedded e-invoice XML is read automatically without AI; invoice AI is off'
            : 'AI settings were not recorded; embedded XML does not use AI',
      ),
      (
        Icons.auto_awesome_outlined,
        'Property extraction',
        propertiesEnabled == true
            ? 'AI enabled · ${configuration.propertyExtractionModel ?? 'Configured model'} · fills missing properties'
            : propertiesEnabled == false
            ? 'AI off · document properties stay unchanged'
            : 'AI settings were not recorded',
      ),
    ];
    final current = switch (job?.stage) {
      'invoicing' => 0,
      'enriching' => 1,
      'complete' => 2,
      _ => -1,
    };
    String? status(int i) {
      final enabled = i == 0 ? invoiceEnabled : propertiesEnabled;
      if (job == null) return i == 1 && enabled == false ? 'Off' : null;
      if (job!.status == 'skipped') return 'Skipped';
      if (i == 0 && job!.invoiceClassification?.decision == 'not_invoice') {
        return 'Not an invoice · extraction skipped';
      }
      if (i == 0 && job!.invoiceClassification?.decision == 'uncertain') {
        return 'Needs review · extraction skipped';
      }
      if (i == 1 && enabled == false) return 'Off for this attempt';
      if (job!.status == 'failed' && current == i) return 'Stopped here';
      if (job!.status == 'running' && current == i) return 'In progress';
      if (enabled == null) return 'Not recorded';
      if (i == 0 &&
          enabled == false &&
          propertiesEnabled != false &&
          current != 0) {
        return 'Not recorded';
      }
      if (current > i || job!.status == 'succeeded') return 'Complete';
      return job!.active ? 'Waiting' : 'Not completed';
    }

    return AppPipelineDiagram(
      steps: [
        for (var i = 0; i < stages.length; i++)
          AppPipelineStep(
            icon: stages[i].$1,
            title: stages[i].$2,
            description: stages[i].$3,
            status: status(i),
            current: job?.status == 'running' && current == i,
            failed: job?.status == 'failed' && current == i,
            actionLabel: job == null && onEditExtraction != null
                ? i == 0
                      ? 'Edit invoice extraction'
                      : 'Edit property extraction'
                : null,
            onAction: job == null ? onEditExtraction : null,
          ),
      ],
    );
  }
}

final class _LegacyDocumentPipelineDiagram extends StatelessWidget {
  const _LegacyDocumentPipelineDiagram({required this.configuration, this.job});
  final DocumentPipelineConfiguration configuration;
  final DocumentProcessingJob? job;
  final VoidCallback? onEditExtraction = null;
  @override
  Widget build(BuildContext context) {
    final correction = job?.reason == 'ocr_correction';
    final retained = job?.reason == 'legacy';
    final stages = <(IconData, String, String)>[
      (
        Icons.insert_drive_file_outlined,
        'Original',
        'PDF, image, or email kept in your library',
      ),
      (
        Icons.document_scanner_outlined,
        job?.extractionMethod == 'mime'
            ? 'Email text extraction'
            : 'OCR / extraction',
        correction
            ? 'Your saved OCR correction stays in use; extraction is not repeated'
            : job?.textSource == 'manual'
            ? 'Your saved OCR correction stays in use'
            : job?.extractionMethod == 'mime'
            ? 'MIME body text · domabas-mime 1'
            : job != null && job!.extractionMethod == null
            ? 'Extraction method not recorded'
            : job == null
            ? '${configuration.ocrEngine} ${configuration.ocrVersion} for PDF/images; MIME parsing for email'
            : '${configuration.ocrEngine} ${configuration.ocrVersion} · ${processingLabel(configuration.language)}',
      ),
      (
        Icons.receipt_long_outlined,
        'Invoice extraction',
        configuration.invoiceExtractionEnabled == true
            ? 'AI enabled · ${configuration.invoiceExtractionModel ?? 'Configured model'} · PDF and email text; embedded XML first'
            : configuration.invoiceExtractionEnabled == null && job != null
            ? 'AI settings were not recorded; embedded XML does not use AI'
            : 'AI off · embedded e-invoice XML is still read without AI',
      ),
      (
        Icons.auto_awesome_outlined,
        'Property extraction',
        configuration.propertyExtractionEnabled == true
            ? 'AI enabled · ${configuration.propertyExtractionModel ?? 'Configured model'} · ${job == null ? 'fills missing properties' : 'configured for this attempt'}'
            : configuration.propertyExtractionEnabled == null && job != null
            ? 'Extraction settings were not recorded'
            : 'AI off · document properties stay unchanged',
      ),
      (
        Icons.hub_outlined,
        'Embeddings',
        '${configuration.embeddingModel} · text is indexed when available',
      ),
      (
        Icons.search_rounded,
        'Searchable',
        'Publish the current text and index',
      ),
    ];
    final active = switch (job?.stage) {
      'extracting' => 1,
      'invoicing' => 2,
      'enriching' => 3,
      'embedding' => 4,
      'finalizing' => 5,
      'complete' => 6,
      _ => 0,
    };
    AppPipelineStep stage(int index) {
      final skipped = correction && index == 1;
      final extractionOff =
          index == 3 && configuration.propertyExtractionEnabled == false;
      final extractionUnknown =
          index == 3 && configuration.propertyExtractionEnabled == null;
      final invoiceUnknown =
          index == 2 &&
          job != null &&
          (active > 2 || (!job!.active && active != 2));
      final finished =
          job != null &&
          !retained &&
          !skipped &&
          !extractionOff &&
          !extractionUnknown &&
          index != 2 &&
          index != 3 &&
          (index < active || job!.status == 'succeeded');
      final current = !retained && job?.status == 'running' && index == active;
      final failed = !retained && job?.status == 'failed' && index == active;
      final label =
          retained || invoiceUnknown || (extractionUnknown && job != null)
          ? 'Not recorded'
          : index == 3 && (extractionOff || extractionUnknown)
          ? job == null
                ? 'Off'
                : 'Off for this attempt'
          : skipped
          ? 'Not repeated'
          : failed
          ? 'Stopped here'
          : finished
          ? 'Complete'
          : current
          ? 'In progress'
          : index == 3 && job != null
          ? 'Configured'
          : job == null
          ? null
          : !job!.active
          ? 'Not completed'
          : 'Waiting';
      return AppPipelineStep(
        icon: failed
            ? Icons.error_outline
            : skipped || extractionOff
            ? Icons.skip_next_outlined
            : finished
            ? Icons.check_circle_outline
            : stages[index].$1,
        title: stages[index].$2,
        description: stages[index].$3,
        status: label,
        current: current,
        failed: failed,
        actionLabel: (index == 2 || index == 3) && job == null
            ? index == 2
                  ? 'Edit invoice extraction'
                  : 'Edit property extraction'
            : null,
        onAction: (index == 2 || index == 3) && job == null
            ? onEditExtraction
            : null,
      );
    }

    return AppPipelineDiagram(
      steps: [for (var i = 0; i < stages.length; i++) stage(i)],
    );
  }
}

final class ProcessingConfigurationDetails extends StatelessWidget {
  const ProcessingConfigurationDetails({
    super.key,
    required this.configuration,
  });
  final DocumentPipelineConfiguration configuration;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey(
      'pipeline-configuration-${configuration.revision}-${configuration.fingerprint}',
    ),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    title: Text('Configuration ${configuration.revision}'),
    subtitle: Text(
      '${processingLabel(configuration.language)} · ${processingLabel(configuration.segmentation)}',
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${configuration.ocrEngine} ${configuration.ocrVersion} · ${configuration.ocrModel}',
            ),
            const SizedBox(height: 8),
            Text(
              '${configuration.embeddingModel} · ${configuration.embeddingDimensions} dimensions',
            ),
            const SizedBox(height: 12),
            const Text('Configuration fingerprint'),
            SelectionArea(child: Text(configuration.fingerprint)),
            const SizedBox(height: 12),
            const Text('Embedding model digest'),
            SelectionArea(child: Text(configuration.embeddingDigest)),
            const SizedBox(height: 12),
            Text('Pipeline manifest ${configuration.manifestRevision}'),
            Text(
              'Extraction ${configuration.extractionRevision} · chunks ${configuration.chunkingRevision}',
            ),
            Text(
              'Embedding input ${configuration.embeddingInputRevision} · index ${configuration.indexingRevision}',
            ),
          ],
        ),
      ),
    ],
  );
}

final class ReindexBatchCard extends StatelessWidget {
  const ReindexBatchCard({super.key, required this.batch});
  final DocumentReindexBatch batch;
  @override
  Widget build(BuildContext context) => AppSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              processingLabel(batch.reason),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            AppStatusBadge(
              running: batch.active,
              label: processingLabel(batch.status),
              tone: processingTone(batch.status),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(batch.scope == 'system' ? 'All libraries' : 'Current library'),
        Text(
          '${processingTime(batch.createdAt)} · configuration ${batch.configurationRevision}',
        ),
        const SizedBox(height: 16),
        AppJobProgress(
          label: reindexProgressLabel(batch),
          value: batch.progress,
          animate: batch.active,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            Text('${batch.discovered} discovered'),
            Text('${batch.waiting} waiting'),
            Text('${batch.running} running'),
            Text('${batch.succeeded} succeeded'),
            Text('${batch.failed} failed'),
            Text('${batch.skipped} skipped'),
            if (batch.superseded > 0) Text('${batch.superseded} superseded'),
          ],
        ),
        if (!batch.enumerationComplete) ...[
          const SizedBox(height: 12),
          Text(
            batch.active
                ? 'Still finding originals. The final total is not known yet.'
                : 'This request stopped before the final total was known.',
          ),
        ],
        if (batch.skipped > 0) ...[
          const SizedBox(height: 8),
          const Text(
            'Skipped entries include documents without an original or documents that were deleted.',
          ),
        ],
      ],
    ),
  );
}

String reindexProgressLabel(DocumentReindexBatch batch) =>
    !batch.enumerationComplete
    ? '${batch.active ? 'Finding originals' : 'Total not determined'} · ${batch.discovered} found'
    : batch.discovered == 0
    ? 'No originals to reindex'
    : '${batch.finished} of ${batch.discovered} finished · ${(batch.progress! * 100).floor()}%';

Future<bool> confirmReindex(
  BuildContext context, {
  required bool system,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: system
            ? 'Reindex all library originals?'
            : 'Reindex library originals?',
        description: system
            ? 'This request covers originals across every library.'
            : 'This request covers originals in the current library.',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmReindex'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Request reindex'),
          ),
        ],
        child: const Text(
          'OCR, text processing and embeddings will run again with the current pipeline. Your saved OCR corrections and original files are preserved. Documents without originals are skipped.',
        ),
      ),
    ) ??
    false;

String invoiceClassificationLabel(DocumentInvoiceClassification value) {
  if (value.decision == 'invoice') return 'Invoice detected';
  if (value.decision == 'not_invoice') {
    return 'Not an invoice · extraction skipped';
  }
  return switch (value.reason) {
    'insufficient_text' => 'Needs review · not enough readable text',
    'incomplete_coverage' =>
      'Needs review · only part of the text could be checked',
    'prior_invoice' =>
      'Needs review · decision differs from the existing invoice',
    'mixed_document' => 'Needs review · mixed document types',
    _ => 'Needs review · invoice decision uncertain',
  };
}
