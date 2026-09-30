// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RealtimeAuthenticate {
  RealtimeAuthenticate({
    required this.type,
    required this.version,
    required this.token,
  });

  RealtimeAuthenticateTypeEnum type;

  RealtimeAuthenticateVersionEnum version;

  String token;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RealtimeAuthenticate &&
    other.type == type &&
    other.version == version &&
    other.token == token;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (type.hashCode) +
    (version.hashCode) +
    (token.hashCode);

  @override
  String toString() => 'RealtimeAuthenticate[type=$type, version=$version, token=$token]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'type'] = this.type;
      json[r'version'] = this.version;
      json[r'token'] = this.token;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static RealtimeAuthenticate? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'type'), 'Required key "RealtimeAuthenticate[type]" is missing from JSON.');
        assert(json[r'type'] != null, 'Required key "RealtimeAuthenticate[type]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "RealtimeAuthenticate[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "RealtimeAuthenticate[version]" has a null value in JSON.');
        assert(json.containsKey(r'token'), 'Required key "RealtimeAuthenticate[token]" is missing from JSON.');
        assert(json[r'token'] != null, 'Required key "RealtimeAuthenticate[token]" has a null value in JSON.');
        return true;
      }());

      return RealtimeAuthenticate(
        type: RealtimeAuthenticateTypeEnum.fromJson(json[r'type'])!,
        version: RealtimeAuthenticateVersionEnum.fromJson(json[r'version'])!,
        token: mapValueOfType<String>(json, r'token')!,
      );
    }
    return null;
  }

  static List<RealtimeAuthenticate> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeAuthenticate>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeAuthenticate.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RealtimeAuthenticate> mapFromJson(dynamic json) {
    final map = <String, RealtimeAuthenticate>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RealtimeAuthenticate.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<RealtimeAuthenticate>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RealtimeAuthenticate>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RealtimeAuthenticate.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'type',
    'version',
    'token',
  };
}

enum RealtimeAuthenticateTypeEnum {
  authenticate._(r'authenticate'),
  ;

  const RealtimeAuthenticateTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static RealtimeAuthenticateTypeEnum? fromJson(dynamic value) => RealtimeAuthenticateTypeEnumTypeTransformer().decode(value);

  static List<RealtimeAuthenticateTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeAuthenticateTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeAuthenticateTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeAuthenticateTypeEnumTypeTransformer {
  factory RealtimeAuthenticateTypeEnumTypeTransformer() => _instance ??= const RealtimeAuthenticateTypeEnumTypeTransformer._();

  const RealtimeAuthenticateTypeEnumTypeTransformer._();

  String encode(RealtimeAuthenticateTypeEnum data) => data._value;

  RealtimeAuthenticateTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeAuthenticateTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'authenticate': return RealtimeAuthenticateTypeEnum.authenticate;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeAuthenticateTypeEnumTypeTransformer? _instance;
}

enum RealtimeAuthenticateVersionEnum {
  number1._(1),
  ;

  const RealtimeAuthenticateVersionEnum._(this._value);

  final int _value;

  @override
  String toString() => _value.toString();

  int toJson() => _value;

  static RealtimeAuthenticateVersionEnum? fromJson(dynamic value) => RealtimeAuthenticateVersionEnumTypeTransformer().decode(value);

  static List<RealtimeAuthenticateVersionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeAuthenticateVersionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeAuthenticateVersionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeAuthenticateVersionEnumTypeTransformer {
  factory RealtimeAuthenticateVersionEnumTypeTransformer() => _instance ??= const RealtimeAuthenticateVersionEnumTypeTransformer._();

  const RealtimeAuthenticateVersionEnumTypeTransformer._();

  int encode(RealtimeAuthenticateVersionEnum data) => data._value;

  RealtimeAuthenticateVersionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeAuthenticateVersionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case 1: return RealtimeAuthenticateVersionEnum.number1;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeAuthenticateVersionEnumTypeTransformer? _instance;
}
