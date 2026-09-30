// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentAIProcessing {
  DocumentAIProcessing({
    this.invoiceClassification,
    required this.jobId,
    required this.attempt,
    required this.status,
    required this.stage,
    required this.configurationRevision,
    required this.updatedAt,
    this.failureCode,
    this.startedAt,
    this.finishedAt,
  });

  InvoiceClassification? invoiceClassification;

  String jobId;

  int attempt;

  DocumentAIProcessingStatusEnum status;

  DocumentAIProcessingStageEnum stage;

  int configurationRevision;

  DateTime updatedAt;

  String? failureCode;

  DateTime? startedAt;

  DateTime? finishedAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentAIProcessing &&
    other.invoiceClassification == invoiceClassification &&
    other.jobId == jobId &&
    other.attempt == attempt &&
    other.status == status &&
    other.stage == stage &&
    other.configurationRevision == configurationRevision &&
    other.updatedAt == updatedAt &&
    other.failureCode == failureCode &&
    other.startedAt == startedAt &&
    other.finishedAt == finishedAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (invoiceClassification == null ? 0 : invoiceClassification!.hashCode) +
    (jobId.hashCode) +
    (attempt.hashCode) +
    (status.hashCode) +
    (stage.hashCode) +
    (configurationRevision.hashCode) +
    (updatedAt.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (startedAt == null ? 0 : startedAt!.hashCode) +
    (finishedAt == null ? 0 : finishedAt!.hashCode);

  @override
  String toString() => 'DocumentAIProcessing[invoiceClassification=$invoiceClassification, jobId=$jobId, attempt=$attempt, status=$status, stage=$stage, configurationRevision=$configurationRevision, updatedAt=$updatedAt, failureCode=$failureCode, startedAt=$startedAt, finishedAt=$finishedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.invoiceClassification != null) {
      json[r'invoiceClassification'] = this.invoiceClassification;
    } else {
      json[r'invoiceClassification'] = null;
    }
      json[r'jobId'] = this.jobId;
      json[r'attempt'] = this.attempt;
      json[r'status'] = this.status;
      json[r'stage'] = this.stage;
      json[r'configurationRevision'] = this.configurationRevision;
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
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
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentAIProcessing? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'jobId'), 'Required key "DocumentAIProcessing[jobId]" is missing from JSON.');
        assert(json[r'jobId'] != null, 'Required key "DocumentAIProcessing[jobId]" has a null value in JSON.');
        assert(json.containsKey(r'attempt'), 'Required key "DocumentAIProcessing[attempt]" is missing from JSON.');
        assert(json[r'attempt'] != null, 'Required key "DocumentAIProcessing[attempt]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "DocumentAIProcessing[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "DocumentAIProcessing[status]" has a null value in JSON.');
        assert(json.containsKey(r'stage'), 'Required key "DocumentAIProcessing[stage]" is missing from JSON.');
        assert(json[r'stage'] != null, 'Required key "DocumentAIProcessing[stage]" has a null value in JSON.');
        assert(json.containsKey(r'configurationRevision'), 'Required key "DocumentAIProcessing[configurationRevision]" is missing from JSON.');
        assert(json[r'configurationRevision'] != null, 'Required key "DocumentAIProcessing[configurationRevision]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "DocumentAIProcessing[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "DocumentAIProcessing[updatedAt]" has a null value in JSON.');
        return true;
      }());

      return DocumentAIProcessing(
        invoiceClassification: InvoiceClassification.fromJson(json[r'invoiceClassification']),
        jobId: mapValueOfType<String>(json, r'jobId')!,
        attempt: mapValueOfType<int>(json, r'attempt')!,
        status: DocumentAIProcessingStatusEnum.fromJson(json[r'status'])!,
        stage: DocumentAIProcessingStageEnum.fromJson(json[r'stage'])!,
        configurationRevision: mapValueOfType<int>(json, r'configurationRevision')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        startedAt: mapDateTime(json, r'startedAt', r''),
        finishedAt: mapDateTime(json, r'finishedAt', r''),
      );
    }
    return null;
  }

  static List<DocumentAIProcessing> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentAIProcessing>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentAIProcessing.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentAIProcessing> mapFromJson(dynamic json) {
    final map = <String, DocumentAIProcessing>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentAIProcessing.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentAIProcessing>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentAIProcessing>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentAIProcessing.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'jobId',
    'attempt',
    'status',
    'stage',
    'configurationRevision',
    'updatedAt',
  };
}

enum DocumentAIProcessingStatusEnum {
  queued._(r'queued'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  failed._(r'failed'),
  skipped._(r'skipped'),
  cancelled._(r'cancelled'),
  superseded._(r'superseded'),
  ;

  const DocumentAIProcessingStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentAIProcessingStatusEnum? fromJson(dynamic value) => DocumentAIProcessingStatusEnumTypeTransformer().decode(value);

  static List<DocumentAIProcessingStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentAIProcessingStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentAIProcessingStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentAIProcessingStatusEnumTypeTransformer {
  factory DocumentAIProcessingStatusEnumTypeTransformer() => _instance ??= const DocumentAIProcessingStatusEnumTypeTransformer._();

  const DocumentAIProcessingStatusEnumTypeTransformer._();

  String encode(DocumentAIProcessingStatusEnum data) => data._value;

  DocumentAIProcessingStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentAIProcessingStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return DocumentAIProcessingStatusEnum.queued;
        case r'running': return DocumentAIProcessingStatusEnum.running;
        case r'succeeded': return DocumentAIProcessingStatusEnum.succeeded;
        case r'failed': return DocumentAIProcessingStatusEnum.failed;
        case r'skipped': return DocumentAIProcessingStatusEnum.skipped;
        case r'cancelled': return DocumentAIProcessingStatusEnum.cancelled;
        case r'superseded': return DocumentAIProcessingStatusEnum.superseded;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentAIProcessingStatusEnumTypeTransformer? _instance;
}

enum DocumentAIProcessingStageEnum {
  queued._(r'queued'),
  invoicing._(r'invoicing'),
  enriching._(r'enriching'),
  complete._(r'complete'),
  failed._(r'failed'),
  ;

  const DocumentAIProcessingStageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentAIProcessingStageEnum? fromJson(dynamic value) => DocumentAIProcessingStageEnumTypeTransformer().decode(value);

  static List<DocumentAIProcessingStageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentAIProcessingStageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentAIProcessingStageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentAIProcessingStageEnumTypeTransformer {
  factory DocumentAIProcessingStageEnumTypeTransformer() => _instance ??= const DocumentAIProcessingStageEnumTypeTransformer._();

  const DocumentAIProcessingStageEnumTypeTransformer._();

  String encode(DocumentAIProcessingStageEnum data) => data._value;

  DocumentAIProcessingStageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentAIProcessingStageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return DocumentAIProcessingStageEnum.queued;
        case r'invoicing': return DocumentAIProcessingStageEnum.invoicing;
        case r'enriching': return DocumentAIProcessingStageEnum.enriching;
        case r'complete': return DocumentAIProcessingStageEnum.complete;
        case r'failed': return DocumentAIProcessingStageEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentAIProcessingStageEnumTypeTransformer? _instance;
}
