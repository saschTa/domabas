import 'package:domabas/data/document/models/document_invoice_classification_mapper.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'classification survives transport and malformed coverage is rejected',
    () {
      final value = api.InvoiceClassification.fromJson({
        'decision': 'uncertain',
        'reason': 'incomplete_coverage',
        'pass': 2,
        'inputCharacters': 22000,
        'sourceCharacters': 40000,
      })!;
      final classification = documentInvoiceClassificationMapper(value)!;
      expect(classification.sourceCharacters, 40000);
      expect(
        invoiceClassificationLabel(classification),
        contains('Needs review'),
      );
      value.inputCharacters = 40001;
      expect(
        () => documentInvoiceClassificationMapper(value),
        throwsFormatException,
      );
      expect(documentInvoiceClassificationMapper(null), isNull);
    },
  );
  test(
    'uncertain completed classification can be retried without redoing OCR',
    () {
      final ai = DocumentAIProcessing(
        jobId: 'job',
        attempt: 1,
        status: 'succeeded',
        stage: 'complete',
        configurationRevision: 1,
        updatedAt: DateTime.utc(2026),
        invoiceClassification: const DocumentInvoiceClassification(
          decision: 'uncertain',
          reason: 'prior_invoice',
          pass: 1,
          inputCharacters: 100,
          sourceCharacters: 100,
        ),
      );
      expect(ai.canRetry, isTrue);
      expect(
        invoiceClassificationLabel(ai.invoiceClassification!),
        contains('existing invoice'),
      );
    },
  );
}
