// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PaperlessRun {
  PaperlessRun({
    required this.id,
    required this.serverUrl,
    required this.state,
    required this.stage,
    required this.discovered,
    required this.imported,
    required this.duplicates,
    required this.failed,
    required this.cancelRequested,
    this.failureCode,
    required this.createdAt,
    required this.updatedAt,
    this.outcomes = const [],
  });

  String id;

  String serverUrl;

  PaperlessRunStateEnum state;

  PaperlessRunStageEnum stage;

  int discovered;

  int imported;

  int duplicates;

  int failed;

  bool cancelRequested;

  String? failureCode;

  DateTime createdAt;

  DateTime updatedAt;

  List<PaperlessOutcome> outcomes;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PaperlessRun &&
    other.id == id &&
    other.serverUrl == serverUrl &&
    other.state == state &&
    other.stage == stage &&
    other.discovered == discovered &&
    other.imported == imported &&
    other.duplicates == duplicates &&
    other.failed == failed &&
    other.cancelRequested == cancelRequested &&
    other.failureCode == failureCode &&
    other.createdAt == createdAt &&
    other.updatedAt == updatedAt &&
    _deepEquality.equals(other.outcomes, outcomes);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (serverUrl.hashCode) +
    (state.hashCode) +
    (stage.hashCode) +
    (discovered.hashCode) +
    (imported.hashCode) +
    (duplicates.hashCode) +
    (failed.hashCode) +
    (cancelRequested.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (createdAt.hashCode) +
    (updatedAt.hashCode) +
    (outcomes.hashCode);

  @override
  String toString() => 'PaperlessRun[id=$id, serverUrl=$serverUrl, state=$state, stage=$stage, discovered=$discovered, imported=$imported, duplicates=$duplicates, failed=$failed, cancelRequested=$cancelRequested, failureCode=$failureCode, createdAt=$createdAt, updatedAt=$updatedAt, outcomes=$outcomes]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'serverUrl'] = this.serverUrl;
      json[r'state'] = this.state;
      json[r'stage'] = this.stage;
      json[r'discovered'] = this.discovered;
      json[r'imported'] = this.imported;
      json[r'duplicates'] = this.duplicates;
      json[r'failed'] = this.failed;
      json[r'cancelRequested'] = this.cancelRequested;
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
      json[r'outcomes'] = this.outcomes;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static PaperlessRun? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "PaperlessRun[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "PaperlessRun[id]" has a null value in JSON.');
        assert(json.containsKey(r'serverUrl'), 'Required key "PaperlessRun[serverUrl]" is missing from JSON.');
        assert(json[r'serverUrl'] != null, 'Required key "PaperlessRun[serverUrl]" has a null value in JSON.');
        assert(json.containsKey(r'state'), 'Required key "PaperlessRun[state]" is missing from JSON.');
        assert(json[r'state'] != null, 'Required key "PaperlessRun[state]" has a null value in JSON.');
        assert(json.containsKey(r'stage'), 'Required key "PaperlessRun[stage]" is missing from JSON.');
        assert(json[r'stage'] != null, 'Required key "PaperlessRun[stage]" has a null value in JSON.');
        assert(json.containsKey(r'discovered'), 'Required key "PaperlessRun[discovered]" is missing from JSON.');
        assert(json[r'discovered'] != null, 'Required key "PaperlessRun[discovered]" has a null value in JSON.');
        assert(json.containsKey(r'imported'), 'Required key "PaperlessRun[imported]" is missing from JSON.');
        assert(json[r'imported'] != null, 'Required key "PaperlessRun[imported]" has a null value in JSON.');
        assert(json.containsKey(r'duplicates'), 'Required key "PaperlessRun[duplicates]" is missing from JSON.');
        assert(json[r'duplicates'] != null, 'Required key "PaperlessRun[duplicates]" has a null value in JSON.');
        assert(json.containsKey(r'failed'), 'Required key "PaperlessRun[failed]" is missing from JSON.');
        assert(json[r'failed'] != null, 'Required key "PaperlessRun[failed]" has a null value in JSON.');
        assert(json.containsKey(r'cancelRequested'), 'Required key "PaperlessRun[cancelRequested]" is missing from JSON.');
        assert(json[r'cancelRequested'] != null, 'Required key "PaperlessRun[cancelRequested]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "PaperlessRun[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "PaperlessRun[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "PaperlessRun[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "PaperlessRun[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'outcomes'), 'Required key "PaperlessRun[outcomes]" is missing from JSON.');
        assert(json[r'outcomes'] != null, 'Required key "PaperlessRun[outcomes]" has a null value in JSON.');
        return true;
      }());

      return PaperlessRun(
        id: mapValueOfType<String>(json, r'id')!,
        serverUrl: mapValueOfType<String>(json, r'serverUrl')!,
        state: PaperlessRunStateEnum.fromJson(json[r'state'])!,
        stage: PaperlessRunStageEnum.fromJson(json[r'stage'])!,
        discovered: mapValueOfType<int>(json, r'discovered')!,
        imported: mapValueOfType<int>(json, r'imported')!,
        duplicates: mapValueOfType<int>(json, r'duplicates')!,
        failed: mapValueOfType<int>(json, r'failed')!,
        cancelRequested: mapValueOfType<bool>(json, r'cancelRequested')!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        outcomes: PaperlessOutcome.listFromJson(json[r'outcomes']),
      );
    }
    return null;
  }

  static List<PaperlessRun> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaperlessRun>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaperlessRun.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PaperlessRun> mapFromJson(dynamic json) {
    final map = <String, PaperlessRun>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PaperlessRun.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<PaperlessRun>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PaperlessRun>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PaperlessRun.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'serverUrl',
    'state',
    'stage',
    'discovered',
    'imported',
    'duplicates',
    'failed',
    'cancelRequested',
    'createdAt',
    'updatedAt',
    'outcomes',
  };
}

enum PaperlessRunStateEnum {
  queued._(r'queued'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  failed._(r'failed'),
  cancelled._(r'cancelled'),
  ;

  const PaperlessRunStateEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static PaperlessRunStateEnum? fromJson(dynamic value) => PaperlessRunStateEnumTypeTransformer().decode(value);

  static List<PaperlessRunStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaperlessRunStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaperlessRunStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class PaperlessRunStateEnumTypeTransformer {
  factory PaperlessRunStateEnumTypeTransformer() => _instance ??= const PaperlessRunStateEnumTypeTransformer._();

  const PaperlessRunStateEnumTypeTransformer._();

  String encode(PaperlessRunStateEnum data) => data._value;

  PaperlessRunStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PaperlessRunStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return PaperlessRunStateEnum.queued;
        case r'running': return PaperlessRunStateEnum.running;
        case r'succeeded': return PaperlessRunStateEnum.succeeded;
        case r'failed': return PaperlessRunStateEnum.failed;
        case r'cancelled': return PaperlessRunStateEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static PaperlessRunStateEnumTypeTransformer? _instance;
}

enum PaperlessRunStageEnum {
  queued._(r'queued'),
  discovering._(r'discovering'),
  importing._(r'importing'),
  complete._(r'complete'),
  ;

  const PaperlessRunStageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static PaperlessRunStageEnum? fromJson(dynamic value) => PaperlessRunStageEnumTypeTransformer().decode(value);

  static List<PaperlessRunStageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaperlessRunStageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaperlessRunStageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class PaperlessRunStageEnumTypeTransformer {
  factory PaperlessRunStageEnumTypeTransformer() => _instance ??= const PaperlessRunStageEnumTypeTransformer._();

  const PaperlessRunStageEnumTypeTransformer._();

  String encode(PaperlessRunStageEnum data) => data._value;

  PaperlessRunStageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PaperlessRunStageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return PaperlessRunStageEnum.queued;
        case r'discovering': return PaperlessRunStageEnum.discovering;
        case r'importing': return PaperlessRunStageEnum.importing;
        case r'complete': return PaperlessRunStageEnum.complete;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static PaperlessRunStageEnumTypeTransformer? _instance;
}
