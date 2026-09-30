// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RealtimeHeartbeat {
  RealtimeHeartbeat({
    required this.type,
    required this.version,
  });

  RealtimeHeartbeatTypeEnum type;

  RealtimeHeartbeatVersionEnum version;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RealtimeHeartbeat &&
    other.type == type &&
    other.version == version;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (type.hashCode) +
    (version.hashCode);

  @override
  String toString() => 'RealtimeHeartbeat[type=$type, version=$version]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'type'] = this.type;
      json[r'version'] = this.version;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static RealtimeHeartbeat? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'type'), 'Required key "RealtimeHeartbeat[type]" is missing from JSON.');
        assert(json[r'type'] != null, 'Required key "RealtimeHeartbeat[type]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "RealtimeHeartbeat[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "RealtimeHeartbeat[version]" has a null value in JSON.');
        return true;
      }());

      return RealtimeHeartbeat(
        type: RealtimeHeartbeatTypeEnum.fromJson(json[r'type'])!,
        version: RealtimeHeartbeatVersionEnum.fromJson(json[r'version'])!,
      );
    }
    return null;
  }

  static List<RealtimeHeartbeat> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeHeartbeat>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeHeartbeat.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RealtimeHeartbeat> mapFromJson(dynamic json) {
    final map = <String, RealtimeHeartbeat>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RealtimeHeartbeat.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<RealtimeHeartbeat>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RealtimeHeartbeat>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RealtimeHeartbeat.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'type',
    'version',
  };
}

enum RealtimeHeartbeatTypeEnum {
  heartbeat._(r'heartbeat'),
  ;

  const RealtimeHeartbeatTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static RealtimeHeartbeatTypeEnum? fromJson(dynamic value) => RealtimeHeartbeatTypeEnumTypeTransformer().decode(value);

  static List<RealtimeHeartbeatTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeHeartbeatTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeHeartbeatTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeHeartbeatTypeEnumTypeTransformer {
  factory RealtimeHeartbeatTypeEnumTypeTransformer() => _instance ??= const RealtimeHeartbeatTypeEnumTypeTransformer._();

  const RealtimeHeartbeatTypeEnumTypeTransformer._();

  String encode(RealtimeHeartbeatTypeEnum data) => data._value;

  RealtimeHeartbeatTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeHeartbeatTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'heartbeat': return RealtimeHeartbeatTypeEnum.heartbeat;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeHeartbeatTypeEnumTypeTransformer? _instance;
}

enum RealtimeHeartbeatVersionEnum {
  number1._(1),
  ;

  const RealtimeHeartbeatVersionEnum._(this._value);

  final int _value;

  @override
  String toString() => _value.toString();

  int toJson() => _value;

  static RealtimeHeartbeatVersionEnum? fromJson(dynamic value) => RealtimeHeartbeatVersionEnumTypeTransformer().decode(value);

  static List<RealtimeHeartbeatVersionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeHeartbeatVersionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeHeartbeatVersionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeHeartbeatVersionEnumTypeTransformer {
  factory RealtimeHeartbeatVersionEnumTypeTransformer() => _instance ??= const RealtimeHeartbeatVersionEnumTypeTransformer._();

  const RealtimeHeartbeatVersionEnumTypeTransformer._();

  int encode(RealtimeHeartbeatVersionEnum data) => data._value;

  RealtimeHeartbeatVersionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeHeartbeatVersionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case 1: return RealtimeHeartbeatVersionEnum.number1;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeHeartbeatVersionEnumTypeTransformer? _instance;
}
