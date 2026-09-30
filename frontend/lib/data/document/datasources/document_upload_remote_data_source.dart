import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../domain/document/models/document_limits.dart';
import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_upload_validation.dart';
import '../models/document_upload_receipt.dart';
import '../models/prepared_document_upload_metadata.dart';

final class DocumentUploadRemoteDataSource {
  DocumentUploadRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 150),
  });
  final api.ApiClient _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;

  PreparedDocumentUploadMetadata prepare(DocumentProperties raw) {
    final value = DocumentUploadValidation.normalize(raw);
    final fields = <String, Object>{'title': value.title, 'kind': value.kind};
    for (final entry in {
      'description': value.description,
      'sender': value.sender,
      'documentDate': value.documentDate,
      'subject': value.subject,
      'messageId': value.messageId,
    }.entries) {
      if (entry.value.isNotEmpty) fields[entry.key] = entry.value;
    }
    for (final entry in {
      'tags': value.tags,
      'recipients': value.recipients,
      'cc': value.cc,
      'bcc': value.bcc,
    }.entries) {
      if (entry.value.isNotEmpty) fields[entry.key] = entry.value;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(fields)));
    if (bytes.length > 32768) {
      throw ArgumentError('Document properties exceed 32 KiB.');
    }
    return PreparedDocumentUploadMetadata(
      version: 1,
      bytes: bytes,
      sha256Hex: sha256.convert(bytes).toString(),
    );
  }

  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<Document> send(
    Uint8List pdf,
    PreparedDocumentUploadMetadata metadata,
    String filename,
    Future<void> cancel,
  ) async {
    if (pdf.isEmpty ||
        pdf.length > documentOriginalByteLimit ||
        !RegExp(r'^[A-Za-z0-9_-]+\.pdf$').hasMatch(filename)) {
      throw const DocumentUploadException(
        DocumentUploadDisposition.rejected,
        'The PDF exceeds the upload limit.',
      );
    }
    return _send(pdf, metadata, filename, cancel, mediaType: 'application/pdf');
  }

  Future<Document> sendOriginal(
    Uint8List bytes,
    PreparedDocumentUploadMetadata metadata,
    String filename,
    Future<void> cancel, {
    void Function()? onSending,
  }) async {
    if (bytes.isEmpty ||
        bytes.length > documentOriginalByteLimit ||
        filename.isEmpty ||
        utf8.encode(filename).length > 255 ||
        !DocumentUploadValidation.validScalars(filename) ||
        filename.runes.any(
          (rune) =>
              rune < 32 ||
              rune >= 127 && rune <= 159 ||
              const {0x2f, 0x5c, 0x22, 0xfffd}.contains(rune),
        )) {
      throw const DocumentUploadException(
        DocumentUploadDisposition.rejected,
        'This file is not valid for upload.',
      );
    }
    return _send(
      bytes,
      metadata,
      filename,
      cancel,
      mediaType: _mediaType(bytes),
      onSending: onSending,
    );
  }

  static String _mediaType(Uint8List bytes) {
    bool starts(List<int> prefix) {
      if (bytes.length < prefix.length) return false;
      for (var index = 0; index < prefix.length; index++) {
        if (bytes[index] != prefix[index]) return false;
      }
      return true;
    }

    if (starts(const [137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (starts(const [255, 216, 255])) return 'image/jpeg';
    if (starts(const [37, 80, 68, 70, 45])) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<Document> _send(
    Uint8List bytes,
    PreparedDocumentUploadMetadata metadata,
    String filename,
    Future<void> cancel, {
    required String mediaType,
    void Function()? onSending,
  }) async {
    if (_cancelled) {
      throw const DocumentUploadException(
        DocumentUploadDisposition.rejected,
        'This session has ended.',
      );
    }
    final rawMetadata =
        jsonDecode(utf8.decode(metadata.bytes)) as Map<String, dynamic>;
    final title = rawMetadata['title'];
    if (title is! String) {
      throw const DocumentUploadException(
        DocumentUploadDisposition.rejected,
        'The upload properties are invalid.',
      );
    }
    final hash = sha256.convert(bytes).toString();
    final abort = Completer<void>();
    _requests.add(abort);
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    unawaited(cancel.then((_) => stop()));
    final timer = Timer(timeout, stop);
    try {
      await Future<void>.value();
      if (abort.isCompleted || _cancelled) {
        throw const DocumentUploadException(
          DocumentUploadDisposition.rejected,
          'Upload cancelled before sending.',
        );
      }
      final multipart =
          http.MultipartRequest('POST', Uri.parse('/api/v1/documents/upload'))
            ..files.add(
              http.MultipartFile.fromBytes(
                'metadata',
                metadata.bytes,
                contentType: MediaType('application', 'json'),
              ),
            )
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: filename,
                contentType: MediaType.parse(mediaType),
              ),
            );
      onSending?.call();
      final response = await _api.invokeAPI(
        '/api/v1/documents/upload',
        'POST',
        [],
        multipart,
        {},
        {},
        'multipart/form-data',
        abortTrigger: abort.future,
      );
      if (response.statusCode == 202) {
        return DocumentUploadReceipt.decode(
          response.bodyBytes,
          size: bytes.length,
          hash: hash,
          filename: filename,
          title: title,
          mediaType: mediaType == 'application/octet-stream'
              ? 'message/rfc822'
              : mediaType,
        );
      }
      if (response.statusCode == 409) {
        throw const DocumentUploadException(
          DocumentUploadDisposition.duplicate,
          'This document is already in the library. Check the library before selecting it again or discarding a scan draft.',
        );
      }
      if (const {400, 401, 403, 413, 415, 429}.contains(response.statusCode)) {
        throw DocumentUploadException(
          DocumentUploadDisposition.rejected,
          switch (response.statusCode) {
            401 => 'Sign in again before uploading.',
            403 => 'You do not have permission to upload.',
            413 => 'This file is too large to upload.',
            415 => 'This file type is unsupported. Upload a PDF, PNG, JPEG or EML original.',
            429 => 'The server is busy. Try uploading later.',
            _ => 'The server rejected this document. Review its properties.',
          },
        );
      }
      throw const DocumentUploadException(
        DocumentUploadDisposition.uncertain,
        'Upload outcome is unknown. Check the library before retrying this exact upload.',
      );
    } on DocumentUploadException {
      rethrow;
    } catch (_) {
      throw const DocumentUploadException(
        DocumentUploadDisposition.uncertain,
        'Upload outcome is unknown. Check the library before retrying this exact upload.',
      );
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
