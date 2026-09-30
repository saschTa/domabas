// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Invitation {
  Invitation({
    required this.id,
    required this.email,
    required this.role,
    this.claims = const {},
    required this.createdAt,
    required this.expiresAt,
    required this.status,
  });

  String id;

  String email;

  AccountRole role;

  Set<String> claims;

  DateTime createdAt;

  DateTime expiresAt;

  InvitationStatusEnum status;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Invitation &&
    other.id == id &&
    other.email == email &&
    other.role == role &&
    _deepEquality.equals(other.claims, claims) &&
    other.createdAt == createdAt &&
    other.expiresAt == expiresAt &&
    other.status == status;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (email.hashCode) +
    (role.hashCode) +
    (claims.hashCode) +
    (createdAt.hashCode) +
    (expiresAt.hashCode) +
    (status.hashCode);

  @override
  String toString() => 'Invitation[id=$id, email=$email, role=$role, claims=$claims, createdAt=$createdAt, expiresAt=$expiresAt, status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'email'] = this.email;
      json[r'role'] = this.role;
      json[r'claims'] = this.claims.toList(growable: false);
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'expiresAt'] = this.expiresAt.toUtc().toIso8601String();
      json[r'status'] = this.status;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static Invitation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Invitation[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Invitation[id]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "Invitation[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "Invitation[email]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "Invitation[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "Invitation[role]" has a null value in JSON.');
        assert(json.containsKey(r'claims'), 'Required key "Invitation[claims]" is missing from JSON.');
        assert(json[r'claims'] != null, 'Required key "Invitation[claims]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "Invitation[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "Invitation[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'expiresAt'), 'Required key "Invitation[expiresAt]" is missing from JSON.');
        assert(json[r'expiresAt'] != null, 'Required key "Invitation[expiresAt]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "Invitation[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "Invitation[status]" has a null value in JSON.');
        return true;
      }());

      return Invitation(
        id: mapValueOfType<String>(json, r'id')!,
        email: mapValueOfType<String>(json, r'email')!,
        role: AccountRole.fromJson(json[r'role'])!,
        claims: json[r'claims'] is Iterable
            ? (json[r'claims'] as Iterable).cast<String>().toSet()
            : const {},
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        expiresAt: mapDateTime(json, r'expiresAt', r'')!,
        status: InvitationStatusEnum.fromJson(json[r'status'])!,
      );
    }
    return null;
  }

  static List<Invitation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Invitation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Invitation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Invitation> mapFromJson(dynamic json) {
    final map = <String, Invitation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Invitation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<Invitation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Invitation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Invitation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'email',
    'role',
    'claims',
    'createdAt',
    'expiresAt',
    'status',
  };
}

enum InvitationStatusEnum {
  pending._(r'pending'),
  accepted._(r'accepted'),
  revoked._(r'revoked'),
  expired._(r'expired'),
  ;

  const InvitationStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static InvitationStatusEnum? fromJson(dynamic value) => InvitationStatusEnumTypeTransformer().decode(value);

  static List<InvitationStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvitationStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvitationStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class InvitationStatusEnumTypeTransformer {
  factory InvitationStatusEnumTypeTransformer() => _instance ??= const InvitationStatusEnumTypeTransformer._();

  const InvitationStatusEnumTypeTransformer._();

  String encode(InvitationStatusEnum data) => data._value;

  InvitationStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is InvitationStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'pending': return InvitationStatusEnum.pending;
        case r'accepted': return InvitationStatusEnum.accepted;
        case r'revoked': return InvitationStatusEnum.revoked;
        case r'expired': return InvitationStatusEnum.expired;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static InvitationStatusEnumTypeTransformer? _instance;
}
