import 'package:domabas_api/api.dart' as api;

import '../../../domain/document/models/document_processing.dart';

DocumentInvoiceClassification? documentInvoiceClassificationMapper(
  api.InvoiceClassification? value,
) {
  if (value == null) return null;
  final decision = value.decision.toString();
  if (!{'invoice', 'not_invoice', 'uncertain'}.contains(decision) ||
      value.reason.isEmpty ||
      value.reason.length > 64 ||
      value.pass < 1 ||
      value.pass > 2 ||
      value.inputCharacters < 0 ||
      value.sourceCharacters < value.inputCharacters) {
    throw const FormatException('Invalid invoice classification');
  }
  return DocumentInvoiceClassification(
    decision: decision,
    reason: value.reason,
    pass: value.pass,
    inputCharacters: value.inputCharacters,
    sourceCharacters: value.sourceCharacters,
  );
}
