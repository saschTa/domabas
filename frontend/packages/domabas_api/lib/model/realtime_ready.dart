// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RealtimeReady {
  RealtimeReady({
    required this.type,
    required this.version,
    this.topics = const {},
  });

  RealtimeReadyTypeEnum type;

  RealtimeReadyVersionEnum version;

  Set<RealtimeTopic> topics;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RealtimeReady &&
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
  String toString() => 'RealtimeReady[type=$type, version=$version, topics=$topics]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'type'] = this.type;
      json[r'version'] = this.version;
      json[r'topics'] = this.topics.toList(growable: false);
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static RealtimeReady? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'type'), 'Required key "RealtimeReady[type]" is missing from JSON.');
        assert(json[r'type'] != null, 'Required key "RealtimeReady[type]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "RealtimeReady[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "RealtimeReady[version]" has a null value in JSON.');
        assert(json.containsKey(r'topics'), 'Required key "RealtimeReady[topics]" is missing from JSON.');
        assert(json[r'topics'] != null, 'Required key "RealtimeReady[topics]" has a null value in JSON.');
        return true;
      }());

      return RealtimeReady(
        type: RealtimeReadyTypeEnum.fromJson(json[r'type'])!,
        version: RealtimeReadyVersionEnum.fromJson(json[r'version'])!,
        topics: RealtimeTopic.listFromJson(json[r'topics']).toSet(),
      );
    }
    return null;
  }

  static List<RealtimeReady> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeReady>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeReady.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RealtimeReady> mapFromJson(dynamic json) {
    final map = <String, RealtimeReady>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RealtimeReady.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<RealtimeReady>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RealtimeReady>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RealtimeReady.listFromJson(entry.value, growable: growable,);
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

enum RealtimeReadyTypeEnum {
  ready._(r'ready'),
  ;

  const RealtimeReadyTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static RealtimeReadyTypeEnum? fromJson(dynamic value) => RealtimeReadyTypeEnumTypeTransformer().decode(value);

  static List<RealtimeReadyTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeReadyTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeReadyTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeReadyTypeEnumTypeTransformer {
  factory RealtimeReadyTypeEnumTypeTransformer() => _instance ??= const RealtimeReadyTypeEnumTypeTransformer._();

  const RealtimeReadyTypeEnumTypeTransformer._();

  String encode(RealtimeReadyTypeEnum data) => data._value;

  RealtimeReadyTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeReadyTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ready': return RealtimeReadyTypeEnum.ready;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeReadyTypeEnumTypeTransformer? _instance;
}

enum RealtimeReadyVersionEnum {
  number1._(1),
  ;

  const RealtimeReadyVersionEnum._(this._value);

  final int _value;

  @override
  String toString() => _value.toString();

  int toJson() => _value;

  static RealtimeReadyVersionEnum? fromJson(dynamic value) => RealtimeReadyVersionEnumTypeTransformer().decode(value);

  static List<RealtimeReadyVersionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeReadyVersionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeReadyVersionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeReadyVersionEnumTypeTransformer {
  factory RealtimeReadyVersionEnumTypeTransformer() => _instance ??= const RealtimeReadyVersionEnumTypeTransformer._();

  const RealtimeReadyVersionEnumTypeTransformer._();

  int encode(RealtimeReadyVersionEnum data) => data._value;

  RealtimeReadyVersionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeReadyVersionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case 1: return RealtimeReadyVersionEnum.number1;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeReadyVersionEnumTypeTransformer? _instance;
}
