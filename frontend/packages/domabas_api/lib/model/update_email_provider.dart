// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateEmailProvider {
  UpdateEmailProvider({
    required this.expectedRevision,
    required this.label,
    required this.endpoint,
    required this.port,
    required this.mailbox,
    required this.intervalMinutes,
    required this.maxAgeDays,
    required this.pageSize,
    required this.enabled,
    this.username,
    this.password,
    this.renewConsent = false,
  });

  int expectedRevision;

  String label;

  String endpoint;

  int port;

  String mailbox;

  int intervalMinutes;

  int maxAgeDays;

  int pageSize;

  bool enabled;

  String? username;

  String? password;

  bool renewConsent;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateEmailProvider &&
    other.expectedRevision == expectedRevision &&
    other.label == label &&
    other.endpoint == endpoint &&
    other.port == port &&
    other.mailbox == mailbox &&
    other.intervalMinutes == intervalMinutes &&
    other.maxAgeDays == maxAgeDays &&
    other.pageSize == pageSize &&
    other.enabled == enabled &&
    other.username == username &&
    other.password == password &&
    other.renewConsent == renewConsent;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (expectedRevision.hashCode) +
    (label.hashCode) +
    (endpoint.hashCode) +
    (port.hashCode) +
    (mailbox.hashCode) +
    (intervalMinutes.hashCode) +
    (maxAgeDays.hashCode) +
    (pageSize.hashCode) +
    (enabled.hashCode) +
    (username == null ? 0 : username!.hashCode) +
    (password == null ? 0 : password!.hashCode) +
    (renewConsent.hashCode);

  @override
  String toString() => 'UpdateEmailProvider[expectedRevision=$expectedRevision, label=$label, endpoint=$endpoint, port=$port, mailbox=$mailbox, intervalMinutes=$intervalMinutes, maxAgeDays=$maxAgeDays, pageSize=$pageSize, enabled=$enabled, username=$username, password=$password, renewConsent=$renewConsent]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'expectedRevision'] = this.expectedRevision;
      json[r'label'] = this.label;
      json[r'endpoint'] = this.endpoint;
      json[r'port'] = this.port;
      json[r'mailbox'] = this.mailbox;
      json[r'intervalMinutes'] = this.intervalMinutes;
      json[r'maxAgeDays'] = this.maxAgeDays;
      json[r'pageSize'] = this.pageSize;
      json[r'enabled'] = this.enabled;
    if (this.username != null) {
      json[r'username'] = this.username;
    } else {
      json[r'username'] = null;
    }
    if (this.password != null) {
      json[r'password'] = this.password;
    } else {
      json[r'password'] = null;
    }
      json[r'renewConsent'] = this.renewConsent;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateEmailProvider? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'expectedRevision'), 'Required key "UpdateEmailProvider[expectedRevision]" is missing from JSON.');
        assert(json[r'expectedRevision'] != null, 'Required key "UpdateEmailProvider[expectedRevision]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "UpdateEmailProvider[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "UpdateEmailProvider[label]" has a null value in JSON.');
        assert(json.containsKey(r'endpoint'), 'Required key "UpdateEmailProvider[endpoint]" is missing from JSON.');
        assert(json[r'endpoint'] != null, 'Required key "UpdateEmailProvider[endpoint]" has a null value in JSON.');
        assert(json.containsKey(r'port'), 'Required key "UpdateEmailProvider[port]" is missing from JSON.');
        assert(json[r'port'] != null, 'Required key "UpdateEmailProvider[port]" has a null value in JSON.');
        assert(json.containsKey(r'mailbox'), 'Required key "UpdateEmailProvider[mailbox]" is missing from JSON.');
        assert(json[r'mailbox'] != null, 'Required key "UpdateEmailProvider[mailbox]" has a null value in JSON.');
        assert(json.containsKey(r'intervalMinutes'), 'Required key "UpdateEmailProvider[intervalMinutes]" is missing from JSON.');
        assert(json[r'intervalMinutes'] != null, 'Required key "UpdateEmailProvider[intervalMinutes]" has a null value in JSON.');
        assert(json.containsKey(r'maxAgeDays'), 'Required key "UpdateEmailProvider[maxAgeDays]" is missing from JSON.');
        assert(json[r'maxAgeDays'] != null, 'Required key "UpdateEmailProvider[maxAgeDays]" has a null value in JSON.');
        assert(json.containsKey(r'pageSize'), 'Required key "UpdateEmailProvider[pageSize]" is missing from JSON.');
        assert(json[r'pageSize'] != null, 'Required key "UpdateEmailProvider[pageSize]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "UpdateEmailProvider[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "UpdateEmailProvider[enabled]" has a null value in JSON.');
        return true;
      }());

      return UpdateEmailProvider(
        expectedRevision: mapValueOfType<int>(json, r'expectedRevision')!,
        label: mapValueOfType<String>(json, r'label')!,
        endpoint: mapValueOfType<String>(json, r'endpoint')!,
        port: mapValueOfType<int>(json, r'port')!,
        mailbox: mapValueOfType<String>(json, r'mailbox')!,
        intervalMinutes: mapValueOfType<int>(json, r'intervalMinutes')!,
        maxAgeDays: mapValueOfType<int>(json, r'maxAgeDays')!,
        pageSize: mapValueOfType<int>(json, r'pageSize')!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        username: mapValueOfType<String>(json, r'username'),
        password: mapValueOfType<String>(json, r'password'),
        renewConsent: mapValueOfType<bool>(json, r'renewConsent') ?? false,
      );
    }
    return null;
  }

  static List<UpdateEmailProvider> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateEmailProvider>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateEmailProvider.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateEmailProvider> mapFromJson(dynamic json) {
    final map = <String, UpdateEmailProvider>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateEmailProvider.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateEmailProvider>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateEmailProvider>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateEmailProvider.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'expectedRevision',
    'label',
    'endpoint',
    'port',
    'mailbox',
    'intervalMinutes',
    'maxAgeDays',
    'pageSize',
    'enabled',
  };
}
