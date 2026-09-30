// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Claim {
  Claim({
    required this.id,
    required this.label,
    required this.scope,
    this.roles = const {},
  });

  String id;

  String label;

  ClaimScopeEnum scope;

  Set<String> roles;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Claim &&
    other.id == id &&
    other.label == label &&
    other.scope == scope &&
    _deepEquality.equals(other.roles, roles);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (label.hashCode) +
    (scope.hashCode) +
    (roles.hashCode);

  @override
  String toString() => 'Claim[id=$id, label=$label, scope=$scope, roles=$roles]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'label'] = this.label;
      json[r'scope'] = this.scope;
      json[r'roles'] = this.roles.toList(growable: false);
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static Claim? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Claim[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Claim[id]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "Claim[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "Claim[label]" has a null value in JSON.');
        assert(json.containsKey(r'scope'), 'Required key "Claim[scope]" is missing from JSON.');
        assert(json[r'scope'] != null, 'Required key "Claim[scope]" has a null value in JSON.');
        assert(json.containsKey(r'roles'), 'Required key "Claim[roles]" is missing from JSON.');
        assert(json[r'roles'] != null, 'Required key "Claim[roles]" has a null value in JSON.');
        return true;
      }());

      return Claim(
        id: mapValueOfType<String>(json, r'id')!,
        label: mapValueOfType<String>(json, r'label')!,
        scope: ClaimScopeEnum.fromJson(json[r'scope'])!,
        roles: json[r'roles'] is Iterable
            ? (json[r'roles'] as Iterable).cast<String>().toSet()
            : const {},
      );
    }
    return null;
  }

  static List<Claim> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Claim>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Claim.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Claim> mapFromJson(dynamic json) {
    final map = <String, Claim>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Claim.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<Claim>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Claim>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Claim.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'label',
    'scope',
    'roles',
  };
}

enum ClaimScopeEnum {
  namespace._(r'namespace'),
  system._(r'system'),
  ;

  const ClaimScopeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static ClaimScopeEnum? fromJson(dynamic value) => ClaimScopeEnumTypeTransformer().decode(value);

  static List<ClaimScopeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ClaimScopeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ClaimScopeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class ClaimScopeEnumTypeTransformer {
  factory ClaimScopeEnumTypeTransformer() => _instance ??= const ClaimScopeEnumTypeTransformer._();

  const ClaimScopeEnumTypeTransformer._();

  String encode(ClaimScopeEnum data) => data._value;

  ClaimScopeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ClaimScopeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'namespace': return ClaimScopeEnum.namespace;
        case r'system': return ClaimScopeEnum.system;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static ClaimScopeEnumTypeTransformer? _instance;
}
