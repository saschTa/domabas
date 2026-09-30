// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentJob {
  DocumentJob({
    this.invoiceClassification,
    required this.pipeline,
    this.pipelineVersion,
    this.rendererRevision,
    this.attempt,
    required this.id,
    required this.documentId,
    required this.documentTitle,
    this.generation,
    required this.reason,
    required this.status,
    required this.stage,
    this.configurationRevision,
    this.configurationFingerprint,
    this.configuration,
    this.textSource,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
    required this.updatedAt,
    required this.failureCode,
    required this.isCurrent,
    required this.documentDeleted,
    required this.extractionMethod,
  });

  InvoiceClassification? invoiceClassification;

  DocumentJobPipelineEnum pipeline;

  int? pipelineVersion;

  int? rendererRevision;

  int? attempt;

  String id;

  String documentId;

  String? documentTitle;

  int? generation;

  DocumentJobReasonEnum reason;

  DocumentJobStatusEnum status;

  DocumentJobStageEnum stage;

  int? configurationRevision;

  String? configurationFingerprint;

  DocumentProcessingConfigurationSnapshot? configuration;

  DocumentJobTextSourceEnum? textSource;

  DateTime createdAt;

  DateTime? startedAt;

  DateTime? finishedAt;

  DateTime updatedAt;

  String? failureCode;

  bool isCurrent;

  bool documentDeleted;

  DocumentJobExtractionMethodEnum? extractionMethod;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentJob &&
    other.invoiceClassification == invoiceClassification &&
    other.pipeline == pipeline &&
    other.pipelineVersion == pipelineVersion &&
    other.rendererRevision == rendererRevision &&
    other.attempt == attempt &&
    other.id == id &&
    other.documentId == documentId &&
    other.documentTitle == documentTitle &&
    other.generation == generation &&
    other.reason == reason &&
    other.status == status &&
    other.stage == stage &&
    other.configurationRevision == configurationRevision &&
    other.configurationFingerprint == configurationFingerprint &&
    other.configuration == configuration &&
    other.textSource == textSource &&
    other.createdAt == createdAt &&
    other.startedAt == startedAt &&
    other.finishedAt == finishedAt &&
    other.updatedAt == updatedAt &&
    other.failureCode == failureCode &&
    other.isCurrent == isCurrent &&
    other.documentDeleted == documentDeleted &&
    other.extractionMethod == extractionMethod;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (invoiceClassification == null ? 0 : invoiceClassification!.hashCode) +
    (pipeline.hashCode) +
    (pipelineVersion == null ? 0 : pipelineVersion!.hashCode) +
    (rendererRevision == null ? 0 : rendererRevision!.hashCode) +
    (attempt == null ? 0 : attempt!.hashCode) +
    (id.hashCode) +
    (documentId.hashCode) +
    (documentTitle == null ? 0 : documentTitle!.hashCode) +
    (generation == null ? 0 : generation!.hashCode) +
    (reason.hashCode) +
    (status.hashCode) +
    (stage.hashCode) +
    (configurationRevision == null ? 0 : configurationRevision!.hashCode) +
    (configurationFingerprint == null ? 0 : configurationFingerprint!.hashCode) +
    (configuration == null ? 0 : configuration!.hashCode) +
    (textSource == null ? 0 : textSource!.hashCode) +
    (createdAt.hashCode) +
    (startedAt == null ? 0 : startedAt!.hashCode) +
    (finishedAt == null ? 0 : finishedAt!.hashCode) +
    (updatedAt.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (isCurrent.hashCode) +
    (documentDeleted.hashCode) +
    (extractionMethod == null ? 0 : extractionMethod!.hashCode);

  @override
  String toString() => 'DocumentJob[invoiceClassification=$invoiceClassification, pipeline=$pipeline, pipelineVersion=$pipelineVersion, rendererRevision=$rendererRevision, attempt=$attempt, id=$id, documentId=$documentId, documentTitle=$documentTitle, generation=$generation, reason=$reason, status=$status, stage=$stage, configurationRevision=$configurationRevision, configurationFingerprint=$configurationFingerprint, configuration=$configuration, textSource=$textSource, createdAt=$createdAt, startedAt=$startedAt, finishedAt=$finishedAt, updatedAt=$updatedAt, failureCode=$failureCode, isCurrent=$isCurrent, documentDeleted=$documentDeleted, extractionMethod=$extractionMethod]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.invoiceClassification != null) {
      json[r'invoiceClassification'] = this.invoiceClassification;
    } else {
      json[r'invoiceClassification'] = null;
    }
      json[r'pipeline'] = this.pipeline;
    if (this.pipelineVersion != null) {
      json[r'pipelineVersion'] = this.pipelineVersion;
    } else {
      json[r'pipelineVersion'] = null;
    }
    if (this.rendererRevision != null) {
      json[r'rendererRevision'] = this.rendererRevision;
    } else {
      json[r'rendererRevision'] = null;
    }
    if (this.attempt != null) {
      json[r'attempt'] = this.attempt;
    } else {
      json[r'attempt'] = null;
    }
      json[r'id'] = this.id;
      json[r'documentId'] = this.documentId;
    if (this.documentTitle != null) {
      json[r'documentTitle'] = this.documentTitle;
    } else {
      json[r'documentTitle'] = null;
    }
    if (this.generation != null) {
      json[r'generation'] = this.generation;
    } else {
      json[r'generation'] = null;
    }
      json[r'reason'] = this.reason;
      json[r'status'] = this.status;
      json[r'stage'] = this.stage;
    if (this.configurationRevision != null) {
      json[r'configurationRevision'] = this.configurationRevision;
    } else {
      json[r'configurationRevision'] = null;
    }
    if (this.configurationFingerprint != null) {
      json[r'configurationFingerprint'] = this.configurationFingerprint;
    } else {
      json[r'configurationFingerprint'] = null;
    }
    if (this.configuration != null) {
      json[r'configuration'] = this.configuration;
    } else {
      json[r'configuration'] = null;
    }
    if (this.textSource != null) {
      json[r'textSource'] = this.textSource;
    } else {
      json[r'textSource'] = null;
    }
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    if (this.startedAt != null) {
      json[r'startedAt'] = this.startedAt!.toUtc().toIso8601String();
    } else {
      json[r'startedAt'] = null;
    }
    if (this.finishedAt != null) {
      json[r'finishedAt'] = this.finishedAt!.toUtc().toIso8601String();
    } else {
      json[r'finishedAt'] = null;
    }
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
      json[r'isCurrent'] = this.isCurrent;
      json[r'documentDeleted'] = this.documentDeleted;
    if (this.extractionMethod != null) {
      json[r'extractionMethod'] = this.extractionMethod;
    } else {
      json[r'extractionMethod'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentJob? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'pipeline'), 'Required key "DocumentJob[pipeline]" is missing from JSON.');
        assert(json[r'pipeline'] != null, 'Required key "DocumentJob[pipeline]" has a null value in JSON.');
        assert(json.containsKey(r'id'), 'Required key "DocumentJob[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "DocumentJob[id]" has a null value in JSON.');
        assert(json.containsKey(r'documentId'), 'Required key "DocumentJob[documentId]" is missing from JSON.');
        assert(json[r'documentId'] != null, 'Required key "DocumentJob[documentId]" has a null value in JSON.');
        assert(json.containsKey(r'documentTitle'), 'Required key "DocumentJob[documentTitle]" is missing from JSON.');
        assert(json.containsKey(r'reason'), 'Required key "DocumentJob[reason]" is missing from JSON.');
        assert(json[r'reason'] != null, 'Required key "DocumentJob[reason]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "DocumentJob[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "DocumentJob[status]" has a null value in JSON.');
        assert(json.containsKey(r'stage'), 'Required key "DocumentJob[stage]" is missing from JSON.');
        assert(json[r'stage'] != null, 'Required key "DocumentJob[stage]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "DocumentJob[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "DocumentJob[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'startedAt'), 'Required key "DocumentJob[startedAt]" is missing from JSON.');
        assert(json.containsKey(r'finishedAt'), 'Required key "DocumentJob[finishedAt]" is missing from JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "DocumentJob[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "DocumentJob[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'failureCode'), 'Required key "DocumentJob[failureCode]" is missing from JSON.');
        assert(json.containsKey(r'isCurrent'), 'Required key "DocumentJob[isCurrent]" is missing from JSON.');
        assert(json[r'isCurrent'] != null, 'Required key "DocumentJob[isCurrent]" has a null value in JSON.');
        assert(json.containsKey(r'documentDeleted'), 'Required key "DocumentJob[documentDeleted]" is missing from JSON.');
        assert(json[r'documentDeleted'] != null, 'Required key "DocumentJob[documentDeleted]" has a null value in JSON.');
        assert(json.containsKey(r'extractionMethod'), 'Required key "DocumentJob[extractionMethod]" is missing from JSON.');
        return true;
      }());

      return DocumentJob(
        invoiceClassification: InvoiceClassification.fromJson(json[r'invoiceClassification']),
        pipeline: DocumentJobPipelineEnum.fromJson(json[r'pipeline'])!,
        pipelineVersion: mapValueOfType<int>(json, r'pipelineVersion'),
        rendererRevision: mapValueOfType<int>(json, r'rendererRevision'),
        attempt: mapValueOfType<int>(json, r'attempt'),
        id: mapValueOfType<String>(json, r'id')!,
        documentId: mapValueOfType<String>(json, r'documentId')!,
        documentTitle: mapValueOfType<String>(json, r'documentTitle'),
        generation: mapValueOfType<int>(json, r'generation'),
        reason: DocumentJobReasonEnum.fromJson(json[r'reason'])!,
        status: DocumentJobStatusEnum.fromJson(json[r'status'])!,
        stage: DocumentJobStageEnum.fromJson(json[r'stage'])!,
        configurationRevision: mapValueOfType<int>(json, r'configurationRevision'),
        configurationFingerprint: mapValueOfType<String>(json, r'configurationFingerprint'),
        configuration: DocumentProcessingConfigurationSnapshot.fromJson(json[r'configuration']),
        textSource: DocumentJobTextSourceEnum.fromJson(json[r'textSource']),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        startedAt: mapDateTime(json, r'startedAt', r''),
        finishedAt: mapDateTime(json, r'finishedAt', r''),
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        isCurrent: mapValueOfType<bool>(json, r'isCurrent')!,
        documentDeleted: mapValueOfType<bool>(json, r'documentDeleted')!,
        extractionMethod: DocumentJobExtractionMethodEnum.fromJson(json[r'extractionMethod']),
      );
    }
    return null;
  }

  static List<DocumentJob> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJob>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJob.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentJob> mapFromJson(dynamic json) {
    final map = <String, DocumentJob>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentJob.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentJob>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentJob>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentJob.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'pipeline',
    'id',
    'documentId',
    'documentTitle',
    'reason',
    'status',
    'stage',
    'createdAt',
    'startedAt',
    'finishedAt',
    'updatedAt',
    'failureCode',
    'isCurrent',
    'documentDeleted',
    'extractionMethod',
  };
}

enum DocumentJobPipelineEnum {
  ingestion._(r'ingestion'),
  ai._(r'ai'),
  thumbnail._(r'thumbnail'),
  ;

  const DocumentJobPipelineEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentJobPipelineEnum? fromJson(dynamic value) => DocumentJobPipelineEnumTypeTransformer().decode(value);

  static List<DocumentJobPipelineEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobPipelineEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobPipelineEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentJobPipelineEnumTypeTransformer {
  factory DocumentJobPipelineEnumTypeTransformer() => _instance ??= const DocumentJobPipelineEnumTypeTransformer._();

  const DocumentJobPipelineEnumTypeTransformer._();

  String encode(DocumentJobPipelineEnum data) => data._value;

  DocumentJobPipelineEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentJobPipelineEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ingestion': return DocumentJobPipelineEnum.ingestion;
        case r'ai': return DocumentJobPipelineEnum.ai;
        case r'thumbnail': return DocumentJobPipelineEnum.thumbnail;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentJobPipelineEnumTypeTransformer? _instance;
}

enum DocumentJobReasonEnum {
  automatic._(r'automatic'),
  upload._(r'upload'),
  retry._(r'retry'),
  ocrCorrection._(r'ocr_correction'),
  reindex._(r'reindex'),
  legacy._(r'legacy'),
  configurationChange._(r'configuration_change'),
  ;

  const DocumentJobReasonEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentJobReasonEnum? fromJson(dynamic value) => DocumentJobReasonEnumTypeTransformer().decode(value);

  static List<DocumentJobReasonEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobReasonEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobReasonEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentJobReasonEnumTypeTransformer {
  factory DocumentJobReasonEnumTypeTransformer() => _instance ??= const DocumentJobReasonEnumTypeTransformer._();

  const DocumentJobReasonEnumTypeTransformer._();

  String encode(DocumentJobReasonEnum data) => data._value;

  DocumentJobReasonEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentJobReasonEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'automatic': return DocumentJobReasonEnum.automatic;
        case r'upload': return DocumentJobReasonEnum.upload;
        case r'retry': return DocumentJobReasonEnum.retry;
        case r'ocr_correction': return DocumentJobReasonEnum.ocrCorrection;
        case r'reindex': return DocumentJobReasonEnum.reindex;
        case r'legacy': return DocumentJobReasonEnum.legacy;
        case r'configuration_change': return DocumentJobReasonEnum.configurationChange;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentJobReasonEnumTypeTransformer? _instance;
}

enum DocumentJobStatusEnum {
  queued._(r'queued'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  skipped._(r'skipped'),
  failed._(r'failed'),
  superseded._(r'superseded'),
  cancelled._(r'cancelled'),
  ;

  const DocumentJobStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentJobStatusEnum? fromJson(dynamic value) => DocumentJobStatusEnumTypeTransformer().decode(value);

  static List<DocumentJobStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentJobStatusEnumTypeTransformer {
  factory DocumentJobStatusEnumTypeTransformer() => _instance ??= const DocumentJobStatusEnumTypeTransformer._();

  const DocumentJobStatusEnumTypeTransformer._();

  String encode(DocumentJobStatusEnum data) => data._value;

  DocumentJobStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentJobStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return DocumentJobStatusEnum.queued;
        case r'running': return DocumentJobStatusEnum.running;
        case r'succeeded': return DocumentJobStatusEnum.succeeded;
        case r'skipped': return DocumentJobStatusEnum.skipped;
        case r'failed': return DocumentJobStatusEnum.failed;
        case r'superseded': return DocumentJobStatusEnum.superseded;
        case r'cancelled': return DocumentJobStatusEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentJobStatusEnumTypeTransformer? _instance;
}

enum DocumentJobStageEnum {
  queued._(r'queued'),
  rendering._(r'rendering'),
  extracting._(r'extracting'),
  enriching._(r'enriching'),
  invoicing._(r'invoicing'),
  embedding._(r'embedding'),
  finalizing._(r'finalizing'),
  complete._(r'complete'),
  failed._(r'failed'),
  ;

  const DocumentJobStageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentJobStageEnum? fromJson(dynamic value) => DocumentJobStageEnumTypeTransformer().decode(value);

  static List<DocumentJobStageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobStageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobStageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentJobStageEnumTypeTransformer {
  factory DocumentJobStageEnumTypeTransformer() => _instance ??= const DocumentJobStageEnumTypeTransformer._();

  const DocumentJobStageEnumTypeTransformer._();

  String encode(DocumentJobStageEnum data) => data._value;

  DocumentJobStageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentJobStageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return DocumentJobStageEnum.queued;
        case r'rendering': return DocumentJobStageEnum.rendering;
        case r'extracting': return DocumentJobStageEnum.extracting;
        case r'enriching': return DocumentJobStageEnum.enriching;
        case r'invoicing': return DocumentJobStageEnum.invoicing;
        case r'embedding': return DocumentJobStageEnum.embedding;
        case r'finalizing': return DocumentJobStageEnum.finalizing;
        case r'complete': return DocumentJobStageEnum.complete;
        case r'failed': return DocumentJobStageEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentJobStageEnumTypeTransformer? _instance;
}

enum DocumentJobTextSourceEnum {
  machine._(r'machine'),
  manual._(r'manual'),
  ;

  const DocumentJobTextSourceEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentJobTextSourceEnum? fromJson(dynamic value) => DocumentJobTextSourceEnumTypeTransformer().decode(value);

  static List<DocumentJobTextSourceEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobTextSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobTextSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentJobTextSourceEnumTypeTransformer {
  factory DocumentJobTextSourceEnumTypeTransformer() => _instance ??= const DocumentJobTextSourceEnumTypeTransformer._();

  const DocumentJobTextSourceEnumTypeTransformer._();

  String encode(DocumentJobTextSourceEnum data) => data._value;

  DocumentJobTextSourceEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentJobTextSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'machine': return DocumentJobTextSourceEnum.machine;
        case r'manual': return DocumentJobTextSourceEnum.manual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentJobTextSourceEnumTypeTransformer? _instance;
}

enum DocumentJobExtractionMethodEnum {
  ocr._(r'ocr'),
  mime._(r'mime'),
  ;

  const DocumentJobExtractionMethodEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentJobExtractionMethodEnum? fromJson(dynamic value) => DocumentJobExtractionMethodEnumTypeTransformer().decode(value);

  static List<DocumentJobExtractionMethodEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobExtractionMethodEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobExtractionMethodEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentJobExtractionMethodEnumTypeTransformer {
  factory DocumentJobExtractionMethodEnumTypeTransformer() => _instance ??= const DocumentJobExtractionMethodEnumTypeTransformer._();

  const DocumentJobExtractionMethodEnumTypeTransformer._();

  String encode(DocumentJobExtractionMethodEnum data) => data._value;

  DocumentJobExtractionMethodEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentJobExtractionMethodEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ocr': return DocumentJobExtractionMethodEnum.ocr;
        case r'mime': return DocumentJobExtractionMethodEnum.mime;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentJobExtractionMethodEnumTypeTransformer? _instance;
}
