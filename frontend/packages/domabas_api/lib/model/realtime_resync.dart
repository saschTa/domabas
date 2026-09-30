// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RealtimeResync {
  RealtimeResync({
    required this.type,
    required this.version,
    this.topics = const {},
  });

  RealtimeResyncTypeEnum type;

  RealtimeResyncVersionEnum version;

  Set<RealtimeTopic> topics;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RealtimeResync &&
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
  String toString() => 'RealtimeResync[type=$type, version=$version, topics=$topics]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'type'] = this.type;
      json[r'version'] = this.version;
      json[r'topics'] = this.topics.toList(growable: false);
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static RealtimeResync? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'type'), 'Required key "RealtimeResync[type]" is missing from JSON.');
        assert(json[r'type'] != null, 'Required key "RealtimeResync[type]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "RealtimeResync[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "RealtimeResync[version]" has a null value in JSON.');
        assert(json.containsKey(r'topics'), 'Required key "RealtimeResync[topics]" is missing from JSON.');
        assert(json[r'topics'] != null, 'Required key "RealtimeResync[topics]" has a null value in JSON.');
        return true;
      }());

      return RealtimeResync(
        type: RealtimeResyncTypeEnum.fromJson(json[r'type'])!,
        version: RealtimeResyncVersionEnum.fromJson(json[r'version'])!,
        topics: RealtimeTopic.listFromJson(json[r'topics']).toSet(),
      );
    }
    return null;
  }

  static List<RealtimeResync> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeResync>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeResync.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RealtimeResync> mapFromJson(dynamic json) {
    final map = <String, RealtimeResync>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RealtimeResync.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<RealtimeResync>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RealtimeResync>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RealtimeResync.listFromJson(entry.value, growable: growable,);
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

enum RealtimeResyncTypeEnum {
  resync._(r'resync'),
  ;

  const RealtimeResyncTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static RealtimeResyncTypeEnum? fromJson(dynamic value) => RealtimeResyncTypeEnumTypeTransformer().decode(value);

  static List<RealtimeResyncTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeResyncTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeResyncTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeResyncTypeEnumTypeTransformer {
  factory RealtimeResyncTypeEnumTypeTransformer() => _instance ??= const RealtimeResyncTypeEnumTypeTransformer._();

  const RealtimeResyncTypeEnumTypeTransformer._();

  String encode(RealtimeResyncTypeEnum data) => data._value;

  RealtimeResyncTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeResyncTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'resync': return RealtimeResyncTypeEnum.resync;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeResyncTypeEnumTypeTransformer? _instance;
}

enum RealtimeResyncVersionEnum {
  number1._(1),
  ;

  const RealtimeResyncVersionEnum._(this._value);

  final int _value;

  @override
  String toString() => _value.toString();

  int toJson() => _value;

  static RealtimeResyncVersionEnum? fromJson(dynamic value) => RealtimeResyncVersionEnumTypeTransformer().decode(value);

  static List<RealtimeResyncVersionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeResyncVersionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeResyncVersionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeResyncVersionEnumTypeTransformer {
  factory RealtimeResyncVersionEnumTypeTransformer() => _instance ??= const RealtimeResyncVersionEnumTypeTransformer._();

  const RealtimeResyncVersionEnumTypeTransformer._();

  int encode(RealtimeResyncVersionEnum data) => data._value;

  RealtimeResyncVersionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeResyncVersionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case 1: return RealtimeResyncVersionEnum.number1;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeResyncVersionEnumTypeTransformer? _instance;
}
