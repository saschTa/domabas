import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_processing.dart';

Document documentWithAI({
  DocumentInvoiceClassification? classification,
  String status = 'failed',
  String stage = 'invoicing',
}) => Document(
  id: '11111111-1111-4111-8111-111111111111',
  title: 'Searchable document',
  description: '',
  createdAt: DateTime.utc(2026, 9, 21),
  processing: DocumentProcessing(
    state: 'ready',
    stage: 'complete',
    generation: 7,
    configurationRevision: 3,
    updatedAt: DateTime.utc(2026, 9, 21),
    ocrEngine: 'tesseract',
    ocrVersion: '5.5.3',
    ocrModel: 'tessdata_fast',
    ocrLanguage: 'eng',
    ocrSegmentation: 'auto',
    embeddingModel: 'nomic-embed-text:v1.5',
    embeddingDigest: 'a' * 64,
    embeddingDimensions: 768,
    extractionMethod: 'ocr',
    ai: DocumentAIProcessing(
      invoiceClassification: classification,
      jobId: '22222222-2222-4222-8222-222222222222',
      attempt: 2,
      status: status,
      stage: stage,
      configurationRevision: 3,
      failureCode: status == 'failed' ? 'inference_unavailable' : null,
      updatedAt: DateTime.utc(2026, 9, 21),
    ),
  ),
);
