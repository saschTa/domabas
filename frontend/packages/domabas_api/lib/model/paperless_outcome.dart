// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PaperlessOutcome {
  PaperlessOutcome({
    required this.sourceId,
    required this.title,
    required this.status,
    this.failureCode,
    this.documentId,
  });

  int sourceId;

  String title;

  PaperlessOutcomeStatusEnum status;

  String? failureCode;

  String? documentId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PaperlessOutcome &&
    other.sourceId == sourceId &&
    other.title == title &&
    other.status == status &&
    other.failureCode == failureCode &&
    other.documentId == documentId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (sourceId.hashCode) +
    (title.hashCode) +
    (status.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (documentId == null ? 0 : documentId!.hashCode);

  @override
  String toString() => 'PaperlessOutcome[sourceId=$sourceId, title=$title, status=$status, failureCode=$failureCode, documentId=$documentId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'sourceId'] = this.sourceId;
      json[r'title'] = this.title;
      json[r'status'] = this.status;
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
    if (this.documentId != null) {
      json[r'documentId'] = this.documentId;
    } else {
      json[r'documentId'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static PaperlessOutcome? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'sourceId'), 'Required key "PaperlessOutcome[sourceId]" is missing from JSON.');
        assert(json[r'sourceId'] != null, 'Required key "PaperlessOutcome[sourceId]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "PaperlessOutcome[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "PaperlessOutcome[title]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "PaperlessOutcome[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "PaperlessOutcome[status]" has a null value in JSON.');
        return true;
      }());

      return PaperlessOutcome(
        sourceId: mapValueOfType<int>(json, r'sourceId')!,
        title: mapValueOfType<String>(json, r'title')!,
        status: PaperlessOutcomeStatusEnum.fromJson(json[r'status'])!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        documentId: mapValueOfType<String>(json, r'documentId'),
      );
    }
    return null;
  }

  static List<PaperlessOutcome> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaperlessOutcome>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaperlessOutcome.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PaperlessOutcome> mapFromJson(dynamic json) {
    final map = <String, PaperlessOutcome>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PaperlessOutcome.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<PaperlessOutcome>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PaperlessOutcome>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PaperlessOutcome.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'sourceId',
    'title',
    'status',
  };
}

enum PaperlessOutcomeStatusEnum {
  imported._(r'imported'),
  duplicate._(r'duplicate'),
  failed._(r'failed'),
  ;

  const PaperlessOutcomeStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static PaperlessOutcomeStatusEnum? fromJson(dynamic value) => PaperlessOutcomeStatusEnumTypeTransformer().decode(value);

  static List<PaperlessOutcomeStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaperlessOutcomeStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaperlessOutcomeStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class PaperlessOutcomeStatusEnumTypeTransformer {
  factory PaperlessOutcomeStatusEnumTypeTransformer() => _instance ??= const PaperlessOutcomeStatusEnumTypeTransformer._();

  const PaperlessOutcomeStatusEnumTypeTransformer._();

  String encode(PaperlessOutcomeStatusEnum data) => data._value;

  PaperlessOutcomeStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PaperlessOutcomeStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'imported': return PaperlessOutcomeStatusEnum.imported;
        case r'duplicate': return PaperlessOutcomeStatusEnum.duplicate;
        case r'failed': return PaperlessOutcomeStatusEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static PaperlessOutcomeStatusEnumTypeTransformer? _instance;
}
