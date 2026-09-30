// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PersonalActivity {
  PersonalActivity({
    this.activeNextCursor,
    this.finishedNextCursor,
    this.active = const [],
    this.finished = const [],
    required this.activeTruncated,
    required this.activeLimit,
    required this.generatedAt,
  });

  String? activeNextCursor;

  String? finishedNextCursor;

  List<PersonalActivityItem> active;

  List<PersonalActivityItem> finished;

  bool activeTruncated;

  PersonalActivityActiveLimitEnum activeLimit;

  DateTime generatedAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PersonalActivity &&
    other.activeNextCursor == activeNextCursor &&
    other.finishedNextCursor == finishedNextCursor &&
    _deepEquality.equals(other.active, active) &&
    _deepEquality.equals(other.finished, finished) &&
    other.activeTruncated == activeTruncated &&
    other.activeLimit == activeLimit &&
    other.generatedAt == generatedAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (activeNextCursor == null ? 0 : activeNextCursor!.hashCode) +
    (finishedNextCursor == null ? 0 : finishedNextCursor!.hashCode) +
    (active.hashCode) +
    (finished.hashCode) +
    (activeTruncated.hashCode) +
    (activeLimit.hashCode) +
    (generatedAt.hashCode);

  @override
  String toString() => 'PersonalActivity[activeNextCursor=$activeNextCursor, finishedNextCursor=$finishedNextCursor, active=$active, finished=$finished, activeTruncated=$activeTruncated, activeLimit=$activeLimit, generatedAt=$generatedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.activeNextCursor != null) {
      json[r'activeNextCursor'] = this.activeNextCursor;
    } else {
      json[r'activeNextCursor'] = null;
    }
    if (this.finishedNextCursor != null) {
      json[r'finishedNextCursor'] = this.finishedNextCursor;
    } else {
      json[r'finishedNextCursor'] = null;
    }
      json[r'active'] = this.active;
      json[r'finished'] = this.finished;
      json[r'activeTruncated'] = this.activeTruncated;
      json[r'activeLimit'] = this.activeLimit;
      json[r'generatedAt'] = this.generatedAt.toUtc().toIso8601String();
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static PersonalActivity? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'active'), 'Required key "PersonalActivity[active]" is missing from JSON.');
        assert(json[r'active'] != null, 'Required key "PersonalActivity[active]" has a null value in JSON.');
        assert(json.containsKey(r'finished'), 'Required key "PersonalActivity[finished]" is missing from JSON.');
        assert(json[r'finished'] != null, 'Required key "PersonalActivity[finished]" has a null value in JSON.');
        assert(json.containsKey(r'activeTruncated'), 'Required key "PersonalActivity[activeTruncated]" is missing from JSON.');
        assert(json[r'activeTruncated'] != null, 'Required key "PersonalActivity[activeTruncated]" has a null value in JSON.');
        assert(json.containsKey(r'activeLimit'), 'Required key "PersonalActivity[activeLimit]" is missing from JSON.');
        assert(json[r'activeLimit'] != null, 'Required key "PersonalActivity[activeLimit]" has a null value in JSON.');
        assert(json.containsKey(r'generatedAt'), 'Required key "PersonalActivity[generatedAt]" is missing from JSON.');
        assert(json[r'generatedAt'] != null, 'Required key "PersonalActivity[generatedAt]" has a null value in JSON.');
        return true;
      }());

      return PersonalActivity(
        activeNextCursor: mapValueOfType<String>(json, r'activeNextCursor'),
        finishedNextCursor: mapValueOfType<String>(json, r'finishedNextCursor'),
        active: PersonalActivityItem.listFromJson(json[r'active']),
        finished: PersonalActivityItem.listFromJson(json[r'finished']),
        activeTruncated: mapValueOfType<bool>(json, r'activeTruncated')!,
        activeLimit: PersonalActivityActiveLimitEnum.fromJson(json[r'activeLimit'])!,
        generatedAt: mapDateTime(json, r'generatedAt', r'')!,
      );
    }
    return null;
  }

  static List<PersonalActivity> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PersonalActivity>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PersonalActivity.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PersonalActivity> mapFromJson(dynamic json) {
    final map = <String, PersonalActivity>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PersonalActivity.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<PersonalActivity>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PersonalActivity>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PersonalActivity.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'active',
    'finished',
    'activeTruncated',
    'activeLimit',
    'generatedAt',
  };
}

enum PersonalActivityActiveLimitEnum {
  number20._(20),
  ;

  const PersonalActivityActiveLimitEnum._(this._value);

  final int _value;

  @override
  String toString() => _value.toString();

  int toJson() => _value;

  static PersonalActivityActiveLimitEnum? fromJson(dynamic value) => PersonalActivityActiveLimitEnumTypeTransformer().decode(value);

  static List<PersonalActivityActiveLimitEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PersonalActivityActiveLimitEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PersonalActivityActiveLimitEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class PersonalActivityActiveLimitEnumTypeTransformer {
  factory PersonalActivityActiveLimitEnumTypeTransformer() => _instance ??= const PersonalActivityActiveLimitEnumTypeTransformer._();

  const PersonalActivityActiveLimitEnumTypeTransformer._();

  int encode(PersonalActivityActiveLimitEnum data) => data._value;

  PersonalActivityActiveLimitEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PersonalActivityActiveLimitEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case 20: return PersonalActivityActiveLimitEnum.number20;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static PersonalActivityActiveLimitEnumTypeTransformer? _instance;
}
