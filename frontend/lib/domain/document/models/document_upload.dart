import 'dart:convert';

import 'document.dart';
import 'document_upload_validation.dart';

final class DocumentUploadCandidate {
  const DocumentUploadCandidate({required this.id, required this.displayName});
  final String id;
  final String displayName;
}

enum DocumentUploadOutcome { accepted, rejected, duplicate, uncertain }

final class DocumentUploadResult {
  const DocumentUploadResult({
    required this.outcome,
    required this.message,
    this.document,
  });
  final DocumentUploadOutcome outcome;
  final String message;
  final Document? document;
}

abstract final class DocumentUploadNames {
  static String filename(String value) {
    final sanitized = String.fromCharCodes(
      value.runes.map(
        (rune) =>
            rune < 32 ||
                rune >= 127 && rune <= 159 ||
                rune >= 0xd800 && rune <= 0xdfff ||
                const {0x2f, 0x5c, 0x22, 0xfffd}.contains(rune)
            ? 0x5f
            : rune,
      ),
    );
    final result = DocumentUploadValidation.trim(
      _bounded(DocumentUploadValidation.trim(sanitized), 255, 255),
    );
    return result.isEmpty || result == '.' || result == '..'
        ? 'document'
        : result;
  }

  static String title(String safeFilename) {
    final match = RegExp(
      r'\.(pdf|png|jpe?g|eml)$',
      caseSensitive: false,
    ).firstMatch(safeFilename);
    final stem = match != null && match.start > 0
        ? safeFilename.substring(0, match.start)
        : safeFilename;
    final result = _bounded(DocumentUploadValidation.trim(stem), 200, 800);
    return result.isEmpty ? 'Uploaded document' : result;
  }

  static DocumentProperties properties(String safeFilename) =>
      DocumentProperties(
        title: title(safeFilename),
        description: '',
        tags: const [],
        kind: 'document',
        sender: '',
        recipients: const [],
        cc: const [],
        bcc: const [],
        documentDate: '',
        subject: '',
        messageId: '',
      );

  static String _bounded(String value, int scalarLimit, int byteLimit) {
    final output = StringBuffer();
    var bytes = 0, scalars = 0;
    for (final rune in value.runes) {
      final part = String.fromCharCode(rune);
      final size = utf8.encode(part).length;
      if (scalars == scalarLimit || bytes + size > byteLimit) break;
      output.write(part);
      bytes += size;
      scalars++;
    }
    return output.toString();
  }
}
