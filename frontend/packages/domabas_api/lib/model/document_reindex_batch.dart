// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentReindexBatch {
  DocumentReindexBatch({
    required this.id,
    required this.scope,
    required this.reason,
    required this.status,
    required this.configurationRevision,
    required this.configurationFingerprint,
    required this.createdAt,
    required this.finishedAt,
    required this.enumerationComplete,
    required this.discovered,
    required this.waiting,
    required this.running,
    required this.succeeded,
    required this.failed,
    required this.skipped,
    required this.superseded,
  });

  String id;

  DocumentReindexBatchScopeEnum scope;

  DocumentReindexBatchReasonEnum reason;

  DocumentReindexBatchStatusEnum status;

  int configurationRevision;

  String configurationFingerprint;

  DateTime createdAt;

  DateTime? finishedAt;

  bool enumerationComplete;

  int discovered;

  int waiting;

  int running;

  int succeeded;

  int failed;

  int skipped;

  int superseded;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentReindexBatch &&
    other.id == id &&
    other.scope == scope &&
    other.reason == reason &&
    other.status == status &&
    other.configurationRevision == configurationRevision &&
    other.configurationFingerprint == configurationFingerprint &&
    other.createdAt == createdAt &&
    other.finishedAt == finishedAt &&
    other.enumerationComplete == enumerationComplete &&
    other.discovered == discovered &&
    other.waiting == waiting &&
    other.running == running &&
    other.succeeded == succeeded &&
    other.failed == failed &&
    other.skipped == skipped &&
    other.superseded == superseded;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (scope.hashCode) +
    (reason.hashCode) +
    (status.hashCode) +
    (configurationRevision.hashCode) +
    (configurationFingerprint.hashCode) +
    (createdAt.hashCode) +
    (finishedAt == null ? 0 : finishedAt!.hashCode) +
    (enumerationComplete.hashCode) +
    (discovered.hashCode) +
    (waiting.hashCode) +
    (running.hashCode) +
    (succeeded.hashCode) +
    (failed.hashCode) +
    (skipped.hashCode) +
    (superseded.hashCode);

  @override
  String toString() => 'DocumentReindexBatch[id=$id, scope=$scope, reason=$reason, status=$status, configurationRevision=$configurationRevision, configurationFingerprint=$configurationFingerprint, createdAt=$createdAt, finishedAt=$finishedAt, enumerationComplete=$enumerationComplete, discovered=$discovered, waiting=$waiting, running=$running, succeeded=$succeeded, failed=$failed, skipped=$skipped, superseded=$superseded]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'scope'] = this.scope;
      json[r'reason'] = this.reason;
      json[r'status'] = this.status;
      json[r'configurationRevision'] = this.configurationRevision;
      json[r'configurationFingerprint'] = this.configurationFingerprint;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    if (this.finishedAt != null) {
      json[r'finishedAt'] = this.finishedAt!.toUtc().toIso8601String();
    } else {
      json[r'finishedAt'] = null;
    }
      json[r'enumerationComplete'] = this.enumerationComplete;
      json[r'discovered'] = this.discovered;
      json[r'waiting'] = this.waiting;
      json[r'running'] = this.running;
      json[r'succeeded'] = this.succeeded;
      json[r'failed'] = this.failed;
      json[r'skipped'] = this.skipped;
      json[r'superseded'] = this.superseded;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentReindexBatch? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "DocumentReindexBatch[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "DocumentReindexBatch[id]" has a null value in JSON.');
        assert(json.containsKey(r'scope'), 'Required key "DocumentReindexBatch[scope]" is missing from JSON.');
        assert(json[r'scope'] != null, 'Required key "DocumentReindexBatch[scope]" has a null value in JSON.');
        assert(json.containsKey(r'reason'), 'Required key "DocumentReindexBatch[reason]" is missing from JSON.');
        assert(json[r'reason'] != null, 'Required key "DocumentReindexBatch[reason]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "DocumentReindexBatch[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "DocumentReindexBatch[status]" has a null value in JSON.');
        assert(json.containsKey(r'configurationRevision'), 'Required key "DocumentReindexBatch[configurationRevision]" is missing from JSON.');
        assert(json[r'configurationRevision'] != null, 'Required key "DocumentReindexBatch[configurationRevision]" has a null value in JSON.');
        assert(json.containsKey(r'configurationFingerprint'), 'Required key "DocumentReindexBatch[configurationFingerprint]" is missing from JSON.');
        assert(json[r'configurationFingerprint'] != null, 'Required key "DocumentReindexBatch[configurationFingerprint]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "DocumentReindexBatch[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "DocumentReindexBatch[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'finishedAt'), 'Required key "DocumentReindexBatch[finishedAt]" is missing from JSON.');
        assert(json.containsKey(r'enumerationComplete'), 'Required key "DocumentReindexBatch[enumerationComplete]" is missing from JSON.');
        assert(json[r'enumerationComplete'] != null, 'Required key "DocumentReindexBatch[enumerationComplete]" has a null value in JSON.');
        assert(json.containsKey(r'discovered'), 'Required key "DocumentReindexBatch[discovered]" is missing from JSON.');
        assert(json[r'discovered'] != null, 'Required key "DocumentReindexBatch[discovered]" has a null value in JSON.');
        assert(json.containsKey(r'waiting'), 'Required key "DocumentReindexBatch[waiting]" is missing from JSON.');
        assert(json[r'waiting'] != null, 'Required key "DocumentReindexBatch[waiting]" has a null value in JSON.');
        assert(json.containsKey(r'running'), 'Required key "DocumentReindexBatch[running]" is missing from JSON.');
        assert(json[r'running'] != null, 'Required key "DocumentReindexBatch[running]" has a null value in JSON.');
        assert(json.containsKey(r'succeeded'), 'Required key "DocumentReindexBatch[succeeded]" is missing from JSON.');
        assert(json[r'succeeded'] != null, 'Required key "DocumentReindexBatch[succeeded]" has a null value in JSON.');
        assert(json.containsKey(r'failed'), 'Required key "DocumentReindexBatch[failed]" is missing from JSON.');
        assert(json[r'failed'] != null, 'Required key "DocumentReindexBatch[failed]" has a null value in JSON.');
        assert(json.containsKey(r'skipped'), 'Required key "DocumentReindexBatch[skipped]" is missing from JSON.');
        assert(json[r'skipped'] != null, 'Required key "DocumentReindexBatch[skipped]" has a null value in JSON.');
        assert(json.containsKey(r'superseded'), 'Required key "DocumentReindexBatch[superseded]" is missing from JSON.');
        assert(json[r'superseded'] != null, 'Required key "DocumentReindexBatch[superseded]" has a null value in JSON.');
        return true;
      }());

      return DocumentReindexBatch(
        id: mapValueOfType<String>(json, r'id')!,
        scope: DocumentReindexBatchScopeEnum.fromJson(json[r'scope'])!,
        reason: DocumentReindexBatchReasonEnum.fromJson(json[r'reason'])!,
        status: DocumentReindexBatchStatusEnum.fromJson(json[r'status'])!,
        configurationRevision: mapValueOfType<int>(json, r'configurationRevision')!,
        configurationFingerprint: mapValueOfType<String>(json, r'configurationFingerprint')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        finishedAt: mapDateTime(json, r'finishedAt', r''),
        enumerationComplete: mapValueOfType<bool>(json, r'enumerationComplete')!,
        discovered: mapValueOfType<int>(json, r'discovered')!,
        waiting: mapValueOfType<int>(json, r'waiting')!,
        running: mapValueOfType<int>(json, r'running')!,
        succeeded: mapValueOfType<int>(json, r'succeeded')!,
        failed: mapValueOfType<int>(json, r'failed')!,
        skipped: mapValueOfType<int>(json, r'skipped')!,
        superseded: mapValueOfType<int>(json, r'superseded')!,
      );
    }
    return null;
  }

  static List<DocumentReindexBatch> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentReindexBatch>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentReindexBatch.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentReindexBatch> mapFromJson(dynamic json) {
    final map = <String, DocumentReindexBatch>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentReindexBatch.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentReindexBatch>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentReindexBatch>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentReindexBatch.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'scope',
    'reason',
    'status',
    'configurationRevision',
    'configurationFingerprint',
    'createdAt',
    'finishedAt',
    'enumerationComplete',
    'discovered',
    'waiting',
    'running',
    'succeeded',
    'failed',
    'skipped',
    'superseded',
  };
}

enum DocumentReindexBatchScopeEnum {
  namespace._(r'namespace'),
  system._(r'system'),
  ;

  const DocumentReindexBatchScopeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentReindexBatchScopeEnum? fromJson(dynamic value) => DocumentReindexBatchScopeEnumTypeTransformer().decode(value);

  static List<DocumentReindexBatchScopeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentReindexBatchScopeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentReindexBatchScopeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentReindexBatchScopeEnumTypeTransformer {
  factory DocumentReindexBatchScopeEnumTypeTransformer() => _instance ??= const DocumentReindexBatchScopeEnumTypeTransformer._();

  const DocumentReindexBatchScopeEnumTypeTransformer._();

  String encode(DocumentReindexBatchScopeEnum data) => data._value;

  DocumentReindexBatchScopeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentReindexBatchScopeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'namespace': return DocumentReindexBatchScopeEnum.namespace;
        case r'system': return DocumentReindexBatchScopeEnum.system;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentReindexBatchScopeEnumTypeTransformer? _instance;
}

enum DocumentReindexBatchReasonEnum {
  manual._(r'manual'),
  configurationChange._(r'configuration_change'),
  adoption._(r'adoption'),
  ;

  const DocumentReindexBatchReasonEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentReindexBatchReasonEnum? fromJson(dynamic value) => DocumentReindexBatchReasonEnumTypeTransformer().decode(value);

  static List<DocumentReindexBatchReasonEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentReindexBatchReasonEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentReindexBatchReasonEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentReindexBatchReasonEnumTypeTransformer {
  factory DocumentReindexBatchReasonEnumTypeTransformer() => _instance ??= const DocumentReindexBatchReasonEnumTypeTransformer._();

  const DocumentReindexBatchReasonEnumTypeTransformer._();

  String encode(DocumentReindexBatchReasonEnum data) => data._value;

  DocumentReindexBatchReasonEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentReindexBatchReasonEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'manual': return DocumentReindexBatchReasonEnum.manual;
        case r'configuration_change': return DocumentReindexBatchReasonEnum.configurationChange;
        case r'adoption': return DocumentReindexBatchReasonEnum.adoption;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentReindexBatchReasonEnumTypeTransformer? _instance;
}

enum DocumentReindexBatchStatusEnum {
  enumerating._(r'enumerating'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  completedWithFailures._(r'completed_with_failures'),
  superseded._(r'superseded'),
  ;

  const DocumentReindexBatchStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentReindexBatchStatusEnum? fromJson(dynamic value) => DocumentReindexBatchStatusEnumTypeTransformer().decode(value);

  static List<DocumentReindexBatchStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentReindexBatchStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentReindexBatchStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentReindexBatchStatusEnumTypeTransformer {
  factory DocumentReindexBatchStatusEnumTypeTransformer() => _instance ??= const DocumentReindexBatchStatusEnumTypeTransformer._();

  const DocumentReindexBatchStatusEnumTypeTransformer._();

  String encode(DocumentReindexBatchStatusEnum data) => data._value;

  DocumentReindexBatchStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentReindexBatchStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'enumerating': return DocumentReindexBatchStatusEnum.enumerating;
        case r'running': return DocumentReindexBatchStatusEnum.running;
        case r'succeeded': return DocumentReindexBatchStatusEnum.succeeded;
        case r'completed_with_failures': return DocumentReindexBatchStatusEnum.completedWithFailures;
        case r'superseded': return DocumentReindexBatchStatusEnum.superseded;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentReindexBatchStatusEnumTypeTransformer? _instance;
}
