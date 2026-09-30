// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AuthSession {
  AuthSession({
    required this.token,
    required this.expiresAt,
    required this.identity,
  });

  String token;

  DateTime? expiresAt;

  CurrentIdentity identity;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AuthSession &&
    other.token == token &&
    other.expiresAt == expiresAt &&
    other.identity == identity;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (token.hashCode) +
    (expiresAt == null ? 0 : expiresAt!.hashCode) +
    (identity.hashCode);

  @override
  String toString() => 'AuthSession[token=$token, expiresAt=$expiresAt, identity=$identity]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'token'] = this.token;
    if (this.expiresAt != null) {
      json[r'expiresAt'] = this.expiresAt!.toUtc().toIso8601String();
    } else {
      json[r'expiresAt'] = null;
    }
      json[r'identity'] = this.identity;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static AuthSession? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'token'), 'Required key "AuthSession[token]" is missing from JSON.');
        assert(json[r'token'] != null, 'Required key "AuthSession[token]" has a null value in JSON.');
        assert(json.containsKey(r'expiresAt'), 'Required key "AuthSession[expiresAt]" is missing from JSON.');
        assert(json.containsKey(r'identity'), 'Required key "AuthSession[identity]" is missing from JSON.');
        assert(json[r'identity'] != null, 'Required key "AuthSession[identity]" has a null value in JSON.');
        return true;
      }());

      return AuthSession(
        token: mapValueOfType<String>(json, r'token')!,
        expiresAt: mapDateTime(json, r'expiresAt', r''),
        identity: CurrentIdentity.fromJson(json[r'identity'])!,
      );
    }
    return null;
  }

  static List<AuthSession> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AuthSession>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AuthSession.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AuthSession> mapFromJson(dynamic json) {
    final map = <String, AuthSession>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AuthSession.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<AuthSession>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AuthSession>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AuthSession.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'token',
    'expiresAt',
    'identity',
  };
}
