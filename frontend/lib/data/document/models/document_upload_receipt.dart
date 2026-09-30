import 'dart:convert';
import 'dart:typed_data';

import 'package:domabas_api/api.dart' as api;

import '../../../domain/document/models/document_limits.dart';
import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_upload_validation.dart';
import 'document_ai_processing_mapper.dart';

abstract final class DocumentUploadReceipt {
  static Document decode(
    Uint8List bytes, {
    required int size,
    required String hash,
    required String filename,
    required String title,
    required String mediaType,
  }) {
    if (bytes.length > 128 * 1024) _invalid();
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map<String, dynamic>) _invalid();
    _known(raw, const {
      'id',
      'title',
      'description',
      'createdAt',
      'tags',
      'kind',
      'sender',
      'recipients',
      'cc',
      'bcc',
      'documentDate',
      'subject',
      'messageId',
      'file',
      'processing',
    });
    _uuid(raw['id']);
    _timestamp(raw['createdAt']);
    _text(raw['title'], 200, 800);
    _text(raw['description'], 4000, 16000, allowControls: true);
    for (final entry in const {
      'kind': (8, 8),
      'sender': (320, 1280),
      'documentDate': (10, 10),
      'subject': (200, 800),
      'messageId': (512, 2048),
    }.entries) {
      if (raw.containsKey(entry.key)) {
        _text(raw[entry.key], entry.value.$1, entry.value.$2);
      }
    }
    final properties = DocumentProperties(
      title: raw['title'] as String,
      description: raw['description'] as String,
      tags: _list(raw, 'tags'),
      kind: raw['kind'] as String? ?? 'document',
      sender: raw['sender'] as String? ?? '',
      recipients: _list(raw, 'recipients'),
      cc: _list(raw, 'cc'),
      bcc: _list(raw, 'bcc'),
      documentDate: raw['documentDate'] as String? ?? '',
      subject: raw['subject'] as String? ?? '',
      messageId: raw['messageId'] as String? ?? '',
    );
    if (properties.title != title ||
        DocumentUploadValidation.validate(properties).isNotEmpty) {
      _invalid();
    }
    final file = raw['file'];
    if (file is! Map<String, dynamic>) _invalid();
    _known(file, const {
      'originalFilename',
      'mediaType',
      'size',
      'sha256',
      'ingestedAt',
      'uploaderId',
    });
    if (file['originalFilename'] is! String ||
        file['originalFilename'] != filename ||
        !DocumentUploadValidation.validScalars(filename) ||
        utf8.encode(filename).length > 255 ||
        file['mediaType'] is! String ||
        file['mediaType'] != mediaType ||
        !const {
          'application/pdf',
          'image/png',
          'image/jpeg',
          'message/rfc822',
        }.contains(mediaType) ||
        file['size'] is! int ||
        file['size'] != size ||
        size < 1 ||
        size > documentOriginalByteLimit ||
        file['sha256'] is! String ||
        file['sha256'] != hash ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(file['sha256'] as String)) {
      _invalid();
    }
    _uuid(file['uploaderId']);
    _timestamp(file['ingestedAt']);
    if (raw.containsKey('processing')) _processing(raw['processing']);
    final value = api.Document.fromJson(raw);
    if (value == null || value.file == null) _invalid();
    final original = value.file!;
    final processing = value.processing;
    return Document(
      id: value.id,
      title: value.title,
      description: value.description,
      createdAt: value.createdAt.toUtc(),
      tags: value.tags,
      kind: value.kind?.toString() ?? 'document',
      sender: value.sender ?? '',
      recipients: value.recipients,
      cc: value.cc,
      bcc: value.bcc,
      documentDate: value.documentDate ?? '',
      subject: value.subject ?? '',
      messageId: value.messageId ?? '',
      file: DocumentFile(
        originalFilename: original.originalFilename,
        mediaType: original.mediaType.toString(),
        size: original.size,
        sha256: original.sha256,
        ingestedAt: original.ingestedAt.toUtc(),
        uploaderId: original.uploaderId,
      ),
      processing: processing == null
          ? null
          : DocumentProcessing(
              state: processing.state.toString(),
              stage: processing.stage.toString(),
              generation: processing.generation,
              configurationRevision: processing.configurationRevision,
              updatedAt: processing.updatedAt.toUtc(),
              failureCode: processing.failureCode,
              extractionMethod: processing.extractionMethod?.toString(),
              ocrEngine: processing.ocrEngine,
              ocrVersion: processing.ocrVersion,
              ocrModel: processing.ocrModel,
              ocrLanguage: processing.ocrLanguage.toString(),
              ocrSegmentation: processing.ocrSegmentation.toString(),
              embeddingModel: processing.embeddingModel,
              embeddingDigest: processing.embeddingDigest,
              embeddingDimensions: processing.embeddingDimensions,
              ai: processing.ai == null
                  ? null
                  : documentAIProcessingMapper(processing.ai!),
            ),
    );
  }

  static List<String> _list(Map<String, dynamic> raw, String field) {
    if (!raw.containsKey(field)) return const [];
    final value = raw[field];
    if (value is! List ||
        value.length > 20 ||
        value.any((Object? item) => item is! String)) {
      _invalid();
    }
    for (final item in value) {
      _text(item, field == 'tags' ? 64 : 320, field == 'tags' ? 256 : 1280);
    }
    return value.cast<String>();
  }

  static void _text(
    Object? value,
    int scalars,
    int bytes, {
    bool allowControls = false,
  }) {
    if (value is! String ||
        !DocumentUploadValidation.validScalars(value) ||
        value.runes.length > scalars ||
        utf8.encode(value).length > bytes ||
        value.runes.any(
          (rune) =>
              rune == 0 ||
              !allowControls && (rune < 32 || rune >= 127 && rune <= 159),
        )) {
      _invalid();
    }
  }

  static void _known(Map<String, dynamic> value, Set<String> fields) {
    if (value.keys.any((key) => !fields.contains(key))) _invalid();
  }

  static void _uuid(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(value)) {
      _invalid();
    }
  }

  static void _timestamp(Object? value) {
    if (value is! String || value.length > 35) _invalid();
    final matched = RegExp(
      r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,9})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$',
    ).firstMatch(value);
    if (matched == null || DateTime.tryParse(value) == null) _invalid();
    final year = int.parse(matched.group(1)!);
    final month = int.parse(matched.group(2)!);
    final day = int.parse(matched.group(3)!);
    final date = DateTime.utc(year, month, day);
    if (year < 1 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      _invalid();
    }
  }

  static void _processing(Object? value) {
    if (value is! Map<String, dynamic>) _invalid();
    _known(value, const {
      'state',
      'stage',
      'generation',
      'configurationRevision',
      'updatedAt',
      'failureCode',
      'ocrEngine',
      'ocrVersion',
      'ocrModel',
      'ocrLanguage',
      'ocrSegmentation',
      'embeddingModel',
      'embeddingDigest',
      'embeddingDimensions',
      'extractionMethod',
      'ai',
    });
    for (final entry in {
      'ocrEngine': 64,
      'ocrVersion': 64,
      'ocrModel': 128,
      'embeddingModel': 128,
      'embeddingDigest': 64,
    }.entries) {
      final text = value[entry.key];
      if (text is! String ||
          !DocumentUploadValidation.validScalars(text) ||
          text.runes.length > entry.value) {
        _invalid();
      }
    }
    for (final field in ['generation', 'configurationRevision']) {
      final integer = value[field];
      if (integer is! int || integer < 1) _invalid();
    }
    if (!const {
          'queued',
          'processing',
          'ready',
          'failed',
        }.contains(value['state']) ||
        !const {
          'queued',
          'extracting',
          'enriching',
          'invoicing',
          'embedding',
          'finalizing',
          'complete',
          'failed',
        }.contains(value['stage']) ||
        !const {'eng', 'deu', 'eng+deu'}.contains(value['ocrLanguage']) ||
        !const {'auto', 'single_block'}.contains(value['ocrSegmentation']) ||
        value['embeddingDimensions'] is! int ||
        value['embeddingDimensions'] != 768 ||
        !RegExp(r'^[0-9a-f]{64}$')
            .hasMatch(value['embeddingDigest'] as String) ||
        !value.containsKey('extractionMethod') ||
        value['extractionMethod'] != null &&
            !const {'ocr', 'mime'}.contains(value['extractionMethod'])) {
      _invalid();
    }
    if (value.containsKey('failureCode')) {
      final code = value['failureCode'];
      if (code is! String ||
          !DocumentUploadValidation.validScalars(code) ||
          code.runes.length > 64) {
        _invalid();
      }
    }
    _timestamp(value['updatedAt']);
    if (value.containsKey('ai')) _aiProcessing(value['ai']);
  }

  static void _invoiceClassification(Object? value) {
    if (value is! Map<String, dynamic>) _invalid();
    _known(value, const {
      'decision',
      'reason',
      'pass',
      'inputCharacters',
      'sourceCharacters',
    });
    if (!const {
          'invoice',
          'not_invoice',
          'uncertain',
        }.contains(value['decision']) ||
        value['reason'] is! String ||
        (value['reason'] as String).isEmpty ||
        (value['reason'] as String).length > 64) {
      _invalid();
    }
    for (final field in ['pass', 'inputCharacters', 'sourceCharacters']) {
      if (value[field] is! int || (value[field] as int) < 0) _invalid();
    }
    if ((value['pass'] as int) < 1 ||
        (value['pass'] as int) > 2 ||
        (value['inputCharacters'] as int) >
            (value['sourceCharacters'] as int)) {
      _invalid();
    }
  }

  static void _aiProcessing(Object? value) {
    if (value is! Map<String, dynamic>) _invalid();
    _known(value, const {
      'jobId',
      'invoiceClassification',
      'attempt',
      'status',
      'stage',
      'configurationRevision',
      'updatedAt',
      'startedAt',
      'finishedAt',
      'failureCode',
    });
    if (value.containsKey('invoiceClassification')) {
      _invoiceClassification(value['invoiceClassification']);
    }
    _uuid(value['jobId']);
    for (final field in ['attempt', 'configurationRevision']) {
      if (value[field] is! int || (value[field] as int) < 1) _invalid();
    }
    if (!const {
          'queued',
          'running',
          'succeeded',
          'failed',
          'skipped',
          'cancelled',
          'superseded',
        }.contains(value['status']) ||
        !const {
          'queued',
          'invoicing',
          'enriching',
          'complete',
          'failed',
        }.contains(value['stage'])) {
      _invalid();
    }
    _timestamp(value['updatedAt']);
    for (final field in ['startedAt', 'finishedAt']) {
      if (value[field] != null) _timestamp(value[field]);
    }
    if (value['failureCode'] != null) {
      final code = value['failureCode'];
      if (code is! String ||
          !DocumentUploadValidation.validScalars(code) ||
          code.length > 64) {
        _invalid();
      }
    }
  }

  static Never _invalid() =>
      throw const FormatException('Invalid upload acceptance');
}
