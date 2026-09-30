// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Health {
  Health({
    required this.status,
  });

  HealthStatusEnum status;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Health &&
    other.status == status;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (status.hashCode);

  @override
  String toString() => 'Health[status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'status'] = this.status;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static Health? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'status'), 'Required key "Health[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "Health[status]" has a null value in JSON.');
        return true;
      }());

      return Health(
        status: HealthStatusEnum.fromJson(json[r'status'])!,
      );
    }
    return null;
  }

  static List<Health> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Health>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Health.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Health> mapFromJson(dynamic json) {
    final map = <String, Health>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Health.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<Health>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Health>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Health.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'status',
  };
}

enum HealthStatusEnum {
  ok._(r'ok'),
  ;

  const HealthStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static HealthStatusEnum? fromJson(dynamic value) => HealthStatusEnumTypeTransformer().decode(value);

  static List<HealthStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <HealthStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = HealthStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class HealthStatusEnumTypeTransformer {
  factory HealthStatusEnumTypeTransformer() => _instance ??= const HealthStatusEnumTypeTransformer._();

  const HealthStatusEnumTypeTransformer._();

  String encode(HealthStatusEnum data) => data._value;

  HealthStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is HealthStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok': return HealthStatusEnum.ok;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static HealthStatusEnumTypeTransformer? _instance;
}
