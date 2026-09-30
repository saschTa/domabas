// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

enum SystemRole {
  admin._(r'admin'),
  user._(r'user'),
  ;

  const SystemRole._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static SystemRole? fromJson(dynamic value) => SystemRoleTypeTransformer().decode(value);

  static List<SystemRole> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SystemRole>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SystemRole.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class SystemRoleTypeTransformer {
  factory SystemRoleTypeTransformer() => _instance ??= const SystemRoleTypeTransformer._();

  const SystemRoleTypeTransformer._();

  String encode(SystemRole data) => data._value;

  SystemRole? decode(dynamic data, {bool allowNull = true}) {
    if (data is SystemRole) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'admin': return SystemRole.admin;
        case r'user': return SystemRole.user;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static SystemRoleTypeTransformer? _instance;
}
