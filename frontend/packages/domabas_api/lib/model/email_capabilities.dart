// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailCapabilities {
  EmailCapabilities({
    required this.credentialsAvailable,
    required this.unavailableReason,
    required this.transport,
    required this.defaultIntervalMinutes,
    required this.minIntervalMinutes,
    required this.maxIntervalMinutes,
    required this.defaultMaxAgeDays,
    required this.minMaxAgeDays,
    required this.maxMaxAgeDays,
    required this.defaultPageSize,
    required this.minPageSize,
    required this.maxPageSize,
    required this.maxProviders,
  });

  bool credentialsAvailable;

  EmailCapabilitiesUnavailableReasonEnum? unavailableReason;

  EmailCapabilitiesTransportEnum transport;

  int defaultIntervalMinutes;

  int minIntervalMinutes;

  int maxIntervalMinutes;

  int defaultMaxAgeDays;

  int minMaxAgeDays;

  int maxMaxAgeDays;

  int defaultPageSize;

  int minPageSize;

  int maxPageSize;

  int maxProviders;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmailCapabilities &&
    other.credentialsAvailable == credentialsAvailable &&
    other.unavailableReason == unavailableReason &&
    other.transport == transport &&
    other.defaultIntervalMinutes == defaultIntervalMinutes &&
    other.minIntervalMinutes == minIntervalMinutes &&
    other.maxIntervalMinutes == maxIntervalMinutes &&
    other.defaultMaxAgeDays == defaultMaxAgeDays &&
    other.minMaxAgeDays == minMaxAgeDays &&
    other.maxMaxAgeDays == maxMaxAgeDays &&
    other.defaultPageSize == defaultPageSize &&
    other.minPageSize == minPageSize &&
    other.maxPageSize == maxPageSize &&
    other.maxProviders == maxProviders;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (credentialsAvailable.hashCode) +
    (unavailableReason == null ? 0 : unavailableReason!.hashCode) +
    (transport.hashCode) +
    (defaultIntervalMinutes.hashCode) +
    (minIntervalMinutes.hashCode) +
    (maxIntervalMinutes.hashCode) +
    (defaultMaxAgeDays.hashCode) +
    (minMaxAgeDays.hashCode) +
    (maxMaxAgeDays.hashCode) +
    (defaultPageSize.hashCode) +
    (minPageSize.hashCode) +
    (maxPageSize.hashCode) +
    (maxProviders.hashCode);

  @override
  String toString() => 'EmailCapabilities[credentialsAvailable=$credentialsAvailable, unavailableReason=$unavailableReason, transport=$transport, defaultIntervalMinutes=$defaultIntervalMinutes, minIntervalMinutes=$minIntervalMinutes, maxIntervalMinutes=$maxIntervalMinutes, defaultMaxAgeDays=$defaultMaxAgeDays, minMaxAgeDays=$minMaxAgeDays, maxMaxAgeDays=$maxMaxAgeDays, defaultPageSize=$defaultPageSize, minPageSize=$minPageSize, maxPageSize=$maxPageSize, maxProviders=$maxProviders]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'credentialsAvailable'] = this.credentialsAvailable;
    if (this.unavailableReason != null) {
      json[r'unavailableReason'] = this.unavailableReason;
    } else {
      json[r'unavailableReason'] = null;
    }
      json[r'transport'] = this.transport;
      json[r'defaultIntervalMinutes'] = this.defaultIntervalMinutes;
      json[r'minIntervalMinutes'] = this.minIntervalMinutes;
      json[r'maxIntervalMinutes'] = this.maxIntervalMinutes;
      json[r'defaultMaxAgeDays'] = this.defaultMaxAgeDays;
      json[r'minMaxAgeDays'] = this.minMaxAgeDays;
      json[r'maxMaxAgeDays'] = this.maxMaxAgeDays;
      json[r'defaultPageSize'] = this.defaultPageSize;
      json[r'minPageSize'] = this.minPageSize;
      json[r'maxPageSize'] = this.maxPageSize;
      json[r'maxProviders'] = this.maxProviders;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static EmailCapabilities? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'credentialsAvailable'), 'Required key "EmailCapabilities[credentialsAvailable]" is missing from JSON.');
        assert(json[r'credentialsAvailable'] != null, 'Required key "EmailCapabilities[credentialsAvailable]" has a null value in JSON.');
        assert(json.containsKey(r'unavailableReason'), 'Required key "EmailCapabilities[unavailableReason]" is missing from JSON.');
        assert(json.containsKey(r'transport'), 'Required key "EmailCapabilities[transport]" is missing from JSON.');
        assert(json[r'transport'] != null, 'Required key "EmailCapabilities[transport]" has a null value in JSON.');
        assert(json.containsKey(r'defaultIntervalMinutes'), 'Required key "EmailCapabilities[defaultIntervalMinutes]" is missing from JSON.');
        assert(json[r'defaultIntervalMinutes'] != null, 'Required key "EmailCapabilities[defaultIntervalMinutes]" has a null value in JSON.');
        assert(json.containsKey(r'minIntervalMinutes'), 'Required key "EmailCapabilities[minIntervalMinutes]" is missing from JSON.');
        assert(json[r'minIntervalMinutes'] != null, 'Required key "EmailCapabilities[minIntervalMinutes]" has a null value in JSON.');
        assert(json.containsKey(r'maxIntervalMinutes'), 'Required key "EmailCapabilities[maxIntervalMinutes]" is missing from JSON.');
        assert(json[r'maxIntervalMinutes'] != null, 'Required key "EmailCapabilities[maxIntervalMinutes]" has a null value in JSON.');
        assert(json.containsKey(r'defaultMaxAgeDays'), 'Required key "EmailCapabilities[defaultMaxAgeDays]" is missing from JSON.');
        assert(json[r'defaultMaxAgeDays'] != null, 'Required key "EmailCapabilities[defaultMaxAgeDays]" has a null value in JSON.');
        assert(json.containsKey(r'minMaxAgeDays'), 'Required key "EmailCapabilities[minMaxAgeDays]" is missing from JSON.');
        assert(json[r'minMaxAgeDays'] != null, 'Required key "EmailCapabilities[minMaxAgeDays]" has a null value in JSON.');
        assert(json.containsKey(r'maxMaxAgeDays'), 'Required key "EmailCapabilities[maxMaxAgeDays]" is missing from JSON.');
        assert(json[r'maxMaxAgeDays'] != null, 'Required key "EmailCapabilities[maxMaxAgeDays]" has a null value in JSON.');
        assert(json.containsKey(r'defaultPageSize'), 'Required key "EmailCapabilities[defaultPageSize]" is missing from JSON.');
        assert(json[r'defaultPageSize'] != null, 'Required key "EmailCapabilities[defaultPageSize]" has a null value in JSON.');
        assert(json.containsKey(r'minPageSize'), 'Required key "EmailCapabilities[minPageSize]" is missing from JSON.');
        assert(json[r'minPageSize'] != null, 'Required key "EmailCapabilities[minPageSize]" has a null value in JSON.');
        assert(json.containsKey(r'maxPageSize'), 'Required key "EmailCapabilities[maxPageSize]" is missing from JSON.');
        assert(json[r'maxPageSize'] != null, 'Required key "EmailCapabilities[maxPageSize]" has a null value in JSON.');
        assert(json.containsKey(r'maxProviders'), 'Required key "EmailCapabilities[maxProviders]" is missing from JSON.');
        assert(json[r'maxProviders'] != null, 'Required key "EmailCapabilities[maxProviders]" has a null value in JSON.');
        return true;
      }());

      return EmailCapabilities(
        credentialsAvailable: mapValueOfType<bool>(json, r'credentialsAvailable')!,
        unavailableReason: EmailCapabilitiesUnavailableReasonEnum.fromJson(json[r'unavailableReason']),
        transport: EmailCapabilitiesTransportEnum.fromJson(json[r'transport'])!,
        defaultIntervalMinutes: mapValueOfType<int>(json, r'defaultIntervalMinutes')!,
        minIntervalMinutes: mapValueOfType<int>(json, r'minIntervalMinutes')!,
        maxIntervalMinutes: mapValueOfType<int>(json, r'maxIntervalMinutes')!,
        defaultMaxAgeDays: mapValueOfType<int>(json, r'defaultMaxAgeDays')!,
        minMaxAgeDays: mapValueOfType<int>(json, r'minMaxAgeDays')!,
        maxMaxAgeDays: mapValueOfType<int>(json, r'maxMaxAgeDays')!,
        defaultPageSize: mapValueOfType<int>(json, r'defaultPageSize')!,
        minPageSize: mapValueOfType<int>(json, r'minPageSize')!,
        maxPageSize: mapValueOfType<int>(json, r'maxPageSize')!,
        maxProviders: mapValueOfType<int>(json, r'maxProviders')!,
      );
    }
    return null;
  }

  static List<EmailCapabilities> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailCapabilities>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailCapabilities.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailCapabilities> mapFromJson(dynamic json) {
    final map = <String, EmailCapabilities>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailCapabilities.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<EmailCapabilities>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EmailCapabilities>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailCapabilities.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'credentialsAvailable',
    'unavailableReason',
    'transport',
    'defaultIntervalMinutes',
    'minIntervalMinutes',
    'maxIntervalMinutes',
    'defaultMaxAgeDays',
    'minMaxAgeDays',
    'maxMaxAgeDays',
    'defaultPageSize',
    'minPageSize',
    'maxPageSize',
    'maxProviders',
  };
}

enum EmailCapabilitiesUnavailableReasonEnum {
  notConfigured._(r'not_configured'),
  keyUnavailable._(r'key_unavailable'),
  ;

  const EmailCapabilitiesUnavailableReasonEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailCapabilitiesUnavailableReasonEnum? fromJson(dynamic value) => EmailCapabilitiesUnavailableReasonEnumTypeTransformer().decode(value);

  static List<EmailCapabilitiesUnavailableReasonEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailCapabilitiesUnavailableReasonEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailCapabilitiesUnavailableReasonEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailCapabilitiesUnavailableReasonEnumTypeTransformer {
  factory EmailCapabilitiesUnavailableReasonEnumTypeTransformer() => _instance ??= const EmailCapabilitiesUnavailableReasonEnumTypeTransformer._();

  const EmailCapabilitiesUnavailableReasonEnumTypeTransformer._();

  String encode(EmailCapabilitiesUnavailableReasonEnum data) => data._value;

  EmailCapabilitiesUnavailableReasonEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailCapabilitiesUnavailableReasonEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'not_configured': return EmailCapabilitiesUnavailableReasonEnum.notConfigured;
        case r'key_unavailable': return EmailCapabilitiesUnavailableReasonEnum.keyUnavailable;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailCapabilitiesUnavailableReasonEnumTypeTransformer? _instance;
}

enum EmailCapabilitiesTransportEnum {
  implicitTls._(r'implicit_tls'),
  ;

  const EmailCapabilitiesTransportEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailCapabilitiesTransportEnum? fromJson(dynamic value) => EmailCapabilitiesTransportEnumTypeTransformer().decode(value);

  static List<EmailCapabilitiesTransportEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailCapabilitiesTransportEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailCapabilitiesTransportEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailCapabilitiesTransportEnumTypeTransformer {
  factory EmailCapabilitiesTransportEnumTypeTransformer() => _instance ??= const EmailCapabilitiesTransportEnumTypeTransformer._();

  const EmailCapabilitiesTransportEnumTypeTransformer._();

  String encode(EmailCapabilitiesTransportEnum data) => data._value;

  EmailCapabilitiesTransportEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailCapabilitiesTransportEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'implicit_tls': return EmailCapabilitiesTransportEnum.implicitTls;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailCapabilitiesTransportEnumTypeTransformer? _instance;
}
