// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RealtimeInvalidation {
  RealtimeInvalidation({
    required this.type,
    required this.version,
    this.topics = const {},
  });

  RealtimeInvalidationTypeEnum type;

  RealtimeInvalidationVersionEnum version;

  Set<RealtimeTopic> topics;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RealtimeInvalidation &&
    other.type == type &&
    other.version == version &&
    _deepEquality.equals(other.topics, topics);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (type.hashCode) +
    (version.hashCode) +
    (topics.hashCode);

  @override
  String toString() => 'RealtimeInvalidation[type=$type, version=$version, topics=$topics]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'type'] = this.type;
      json[r'version'] = this.version;
      json[r'topics'] = this.topics.toList(growable: false);
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static RealtimeInvalidation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'type'), 'Required key "RealtimeInvalidation[type]" is missing from JSON.');
        assert(json[r'type'] != null, 'Required key "RealtimeInvalidation[type]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "RealtimeInvalidation[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "RealtimeInvalidation[version]" has a null value in JSON.');
        assert(json.containsKey(r'topics'), 'Required key "RealtimeInvalidation[topics]" is missing from JSON.');
        assert(json[r'topics'] != null, 'Required key "RealtimeInvalidation[topics]" has a null value in JSON.');
        return true;
      }());

      return RealtimeInvalidation(
        type: RealtimeInvalidationTypeEnum.fromJson(json[r'type'])!,
        version: RealtimeInvalidationVersionEnum.fromJson(json[r'version'])!,
        topics: RealtimeTopic.listFromJson(json[r'topics']).toSet(),
      );
    }
    return null;
  }

  static List<RealtimeInvalidation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeInvalidation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeInvalidation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RealtimeInvalidation> mapFromJson(dynamic json) {
    final map = <String, RealtimeInvalidation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RealtimeInvalidation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<RealtimeInvalidation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RealtimeInvalidation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RealtimeInvalidation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'type',
    'version',
    'topics',
  };
}

enum RealtimeInvalidationTypeEnum {
  invalidate._(r'invalidate'),
  ;

  const RealtimeInvalidationTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static RealtimeInvalidationTypeEnum? fromJson(dynamic value) => RealtimeInvalidationTypeEnumTypeTransformer().decode(value);

  static List<RealtimeInvalidationTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeInvalidationTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeInvalidationTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeInvalidationTypeEnumTypeTransformer {
  factory RealtimeInvalidationTypeEnumTypeTransformer() => _instance ??= const RealtimeInvalidationTypeEnumTypeTransformer._();

  const RealtimeInvalidationTypeEnumTypeTransformer._();

  String encode(RealtimeInvalidationTypeEnum data) => data._value;

  RealtimeInvalidationTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeInvalidationTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'invalidate': return RealtimeInvalidationTypeEnum.invalidate;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeInvalidationTypeEnumTypeTransformer? _instance;
}

enum RealtimeInvalidationVersionEnum {
  number1._(1),
  ;

  const RealtimeInvalidationVersionEnum._(this._value);

  final int _value;

  @override
  String toString() => _value.toString();

  int toJson() => _value;

  static RealtimeInvalidationVersionEnum? fromJson(dynamic value) => RealtimeInvalidationVersionEnumTypeTransformer().decode(value);

  static List<RealtimeInvalidationVersionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeInvalidationVersionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeInvalidationVersionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeInvalidationVersionEnumTypeTransformer {
  factory RealtimeInvalidationVersionEnumTypeTransformer() => _instance ??= const RealtimeInvalidationVersionEnumTypeTransformer._();

  const RealtimeInvalidationVersionEnumTypeTransformer._();

  int encode(RealtimeInvalidationVersionEnum data) => data._value;

  RealtimeInvalidationVersionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeInvalidationVersionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case 1: return RealtimeInvalidationVersionEnum.number1;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeInvalidationVersionEnumTypeTransformer? _instance;
}
