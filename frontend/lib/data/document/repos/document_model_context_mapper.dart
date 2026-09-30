import 'package:domabas_api/api.dart' as api;

import '../../../domain/document/models/document_processing.dart';

DocumentModelContext documentModelContextMapper(
  api.OllamaModelContext value,
  String model,
) {
  if (value.model != model || value.maxContextLength < 1) {
    throw const FormatException('Invalid model context');
  }
  return DocumentModelContext(
    model: value.model,
    maxContextLength: value.maxContextLength,
  );
}
