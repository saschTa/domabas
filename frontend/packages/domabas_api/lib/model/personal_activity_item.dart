// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PersonalActivityItem {
  PersonalActivityItem({
    required this.id,
    required this.kind,
    required this.namespaceId,
    required this.namespaceName,
    required this.status,
    required this.stage,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
    required this.documentId,
    required this.providerId,
    required this.batchId,
    required this.title,
    required this.failureCode,
    required this.canOpen,
  });

  String id;

  PersonalActivityItemKindEnum kind;

  String namespaceId;

  String namespaceName;

  PersonalActivityItemStatusEnum status;

  String? stage;

  DateTime createdAt;

  DateTime? startedAt;

  DateTime? finishedAt;

  String? documentId;

  String? providerId;

  String? batchId;

  String? title;

  String? failureCode;

  bool canOpen;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PersonalActivityItem &&
    other.id == id &&
    other.kind == kind &&
    other.namespaceId == namespaceId &&
    other.namespaceName == namespaceName &&
    other.status == status &&
    other.stage == stage &&
    other.createdAt == createdAt &&
    other.startedAt == startedAt &&
    other.finishedAt == finishedAt &&
    other.documentId == documentId &&
    other.providerId == providerId &&
    other.batchId == batchId &&
    other.title == title &&
    other.failureCode == failureCode &&
    other.canOpen == canOpen;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (kind.hashCode) +
    (namespaceId.hashCode) +
    (namespaceName.hashCode) +
    (status.hashCode) +
    (stage == null ? 0 : stage!.hashCode) +
    (createdAt.hashCode) +
    (startedAt == null ? 0 : startedAt!.hashCode) +
    (finishedAt == null ? 0 : finishedAt!.hashCode) +
    (documentId == null ? 0 : documentId!.hashCode) +
    (providerId == null ? 0 : providerId!.hashCode) +
    (batchId == null ? 0 : batchId!.hashCode) +
    (title == null ? 0 : title!.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (canOpen.hashCode);

  @override
  String toString() => 'PersonalActivityItem[id=$id, kind=$kind, namespaceId=$namespaceId, namespaceName=$namespaceName, status=$status, stage=$stage, createdAt=$createdAt, startedAt=$startedAt, finishedAt=$finishedAt, documentId=$documentId, providerId=$providerId, batchId=$batchId, title=$title, failureCode=$failureCode, canOpen=$canOpen]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'kind'] = this.kind;
      json[r'namespaceId'] = this.namespaceId;
      json[r'namespaceName'] = this.namespaceName;
      json[r'status'] = this.status;
    if (this.stage != null) {
      json[r'stage'] = this.stage;
    } else {
      json[r'stage'] = null;
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
    if (this.documentId != null) {
      json[r'documentId'] = this.documentId;
    } else {
      json[r'documentId'] = null;
    }
    if (this.providerId != null) {
      json[r'providerId'] = this.providerId;
    } else {
      json[r'providerId'] = null;
    }
    if (this.batchId != null) {
      json[r'batchId'] = this.batchId;
    } else {
      json[r'batchId'] = null;
    }
    if (this.title != null) {
      json[r'title'] = this.title;
    } else {
      json[r'title'] = null;
    }
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
      json[r'canOpen'] = this.canOpen;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static PersonalActivityItem? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "PersonalActivityItem[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "PersonalActivityItem[id]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "PersonalActivityItem[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "PersonalActivityItem[kind]" has a null value in JSON.');
        assert(json.containsKey(r'namespaceId'), 'Required key "PersonalActivityItem[namespaceId]" is missing from JSON.');
        assert(json[r'namespaceId'] != null, 'Required key "PersonalActivityItem[namespaceId]" has a null value in JSON.');
        assert(json.containsKey(r'namespaceName'), 'Required key "PersonalActivityItem[namespaceName]" is missing from JSON.');
        assert(json[r'namespaceName'] != null, 'Required key "PersonalActivityItem[namespaceName]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "PersonalActivityItem[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "PersonalActivityItem[status]" has a null value in JSON.');
        assert(json.containsKey(r'stage'), 'Required key "PersonalActivityItem[stage]" is missing from JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "PersonalActivityItem[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "PersonalActivityItem[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'startedAt'), 'Required key "PersonalActivityItem[startedAt]" is missing from JSON.');
        assert(json.containsKey(r'finishedAt'), 'Required key "PersonalActivityItem[finishedAt]" is missing from JSON.');
        assert(json.containsKey(r'documentId'), 'Required key "PersonalActivityItem[documentId]" is missing from JSON.');
        assert(json.containsKey(r'providerId'), 'Required key "PersonalActivityItem[providerId]" is missing from JSON.');
        assert(json.containsKey(r'batchId'), 'Required key "PersonalActivityItem[batchId]" is missing from JSON.');
        assert(json.containsKey(r'title'), 'Required key "PersonalActivityItem[title]" is missing from JSON.');
        assert(json.containsKey(r'failureCode'), 'Required key "PersonalActivityItem[failureCode]" is missing from JSON.');
        assert(json.containsKey(r'canOpen'), 'Required key "PersonalActivityItem[canOpen]" is missing from JSON.');
        assert(json[r'canOpen'] != null, 'Required key "PersonalActivityItem[canOpen]" has a null value in JSON.');
        return true;
      }());

      return PersonalActivityItem(
        id: mapValueOfType<String>(json, r'id')!,
        kind: PersonalActivityItemKindEnum.fromJson(json[r'kind'])!,
        namespaceId: mapValueOfType<String>(json, r'namespaceId')!,
        namespaceName: mapValueOfType<String>(json, r'namespaceName')!,
        status: PersonalActivityItemStatusEnum.fromJson(json[r'status'])!,
        stage: mapValueOfType<String>(json, r'stage'),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        startedAt: mapDateTime(json, r'startedAt', r''),
        finishedAt: mapDateTime(json, r'finishedAt', r''),
        documentId: mapValueOfType<String>(json, r'documentId'),
        providerId: mapValueOfType<String>(json, r'providerId'),
        batchId: mapValueOfType<String>(json, r'batchId'),
        title: mapValueOfType<String>(json, r'title'),
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        canOpen: mapValueOfType<bool>(json, r'canOpen')!,
      );
    }
    return null;
  }

  static List<PersonalActivityItem> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PersonalActivityItem>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PersonalActivityItem.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PersonalActivityItem> mapFromJson(dynamic json) {
    final map = <String, PersonalActivityItem>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PersonalActivityItem.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<PersonalActivityItem>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PersonalActivityItem>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PersonalActivityItem.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'kind',
    'namespaceId',
    'namespaceName',
    'status',
    'stage',
    'createdAt',
    'startedAt',
    'finishedAt',
    'documentId',
    'providerId',
    'batchId',
    'title',
    'failureCode',
    'canOpen',
  };
}

enum PersonalActivityItemKindEnum {
  emailRetrieval._(r'email_retrieval'),
  documentProcessing._(r'document_processing'),
  documentAi._(r'document_ai'),
  reindexBatch._(r'reindex_batch'),
  ;

  const PersonalActivityItemKindEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static PersonalActivityItemKindEnum? fromJson(dynamic value) => PersonalActivityItemKindEnumTypeTransformer().decode(value);

  static List<PersonalActivityItemKindEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PersonalActivityItemKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PersonalActivityItemKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class PersonalActivityItemKindEnumTypeTransformer {
  factory PersonalActivityItemKindEnumTypeTransformer() => _instance ??= const PersonalActivityItemKindEnumTypeTransformer._();

  const PersonalActivityItemKindEnumTypeTransformer._();

  String encode(PersonalActivityItemKindEnum data) => data._value;

  PersonalActivityItemKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PersonalActivityItemKindEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'email_retrieval': return PersonalActivityItemKindEnum.emailRetrieval;
        case r'document_processing': return PersonalActivityItemKindEnum.documentProcessing;
        case r'document_ai': return PersonalActivityItemKindEnum.documentAi;
        case r'reindex_batch': return PersonalActivityItemKindEnum.reindexBatch;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static PersonalActivityItemKindEnumTypeTransformer? _instance;
}

enum PersonalActivityItemStatusEnum {
  queued._(r'queued'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  skipped._(r'skipped'),
  partial._(r'partial'),
  failed._(r'failed'),
  cancelled._(r'cancelled'),
  superseded._(r'superseded'),
  ;

  const PersonalActivityItemStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static PersonalActivityItemStatusEnum? fromJson(dynamic value) => PersonalActivityItemStatusEnumTypeTransformer().decode(value);

  static List<PersonalActivityItemStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PersonalActivityItemStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PersonalActivityItemStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class PersonalActivityItemStatusEnumTypeTransformer {
  factory PersonalActivityItemStatusEnumTypeTransformer() => _instance ??= const PersonalActivityItemStatusEnumTypeTransformer._();

  const PersonalActivityItemStatusEnumTypeTransformer._();

  String encode(PersonalActivityItemStatusEnum data) => data._value;

  PersonalActivityItemStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PersonalActivityItemStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return PersonalActivityItemStatusEnum.queued;
        case r'running': return PersonalActivityItemStatusEnum.running;
        case r'succeeded': return PersonalActivityItemStatusEnum.succeeded;
        case r'skipped': return PersonalActivityItemStatusEnum.skipped;
        case r'partial': return PersonalActivityItemStatusEnum.partial;
        case r'failed': return PersonalActivityItemStatusEnum.failed;
        case r'cancelled': return PersonalActivityItemStatusEnum.cancelled;
        case r'superseded': return PersonalActivityItemStatusEnum.superseded;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static PersonalActivityItemStatusEnumTypeTransformer? _instance;
}
