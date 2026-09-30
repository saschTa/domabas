import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final class PreparedDocumentUploadMetadata {
  PreparedDocumentUploadMetadata({
    required this.version,
    required Uint8List bytes,
    required this.sha256Hex,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (version != 1 ||
        bytes.isEmpty ||
        bytes.length > 32768 ||
        sha256.convert(bytes).toString() != sha256Hex ||
        jsonDecode(utf8.decode(bytes)) is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved upload metadata');
    }
  }
  final int version;
  final Uint8List bytes;
  final String sha256Hex;
}

enum DocumentUploadDisposition { rejected, duplicate, uncertain }

final class DocumentUploadException implements Exception {
  const DocumentUploadException(this.disposition, this.message);
  final DocumentUploadDisposition disposition;
  final String message;
}
