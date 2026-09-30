// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CreateEmailProvider {
  CreateEmailProvider({
    required this.id,
    required this.label,
    required this.endpoint,
    required this.port,
    required this.mailbox,
    required this.intervalMinutes,
    required this.maxAgeDays,
    required this.pageSize,
    required this.enabled,
    required this.username,
    required this.password,
  });

  String id;

  String label;

  String endpoint;

  int port;

  String mailbox;

  int intervalMinutes;

  int maxAgeDays;

  int pageSize;

  bool enabled;

  String username;

  String password;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateEmailProvider &&
    other.id == id &&
    other.label == label &&
    other.endpoint == endpoint &&
    other.port == port &&
    other.mailbox == mailbox &&
    other.intervalMinutes == intervalMinutes &&
    other.maxAgeDays == maxAgeDays &&
    other.pageSize == pageSize &&
    other.enabled == enabled &&
    other.username == username &&
    other.password == password;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (label.hashCode) +
    (endpoint.hashCode) +
    (port.hashCode) +
    (mailbox.hashCode) +
    (intervalMinutes.hashCode) +
    (maxAgeDays.hashCode) +
    (pageSize.hashCode) +
    (enabled.hashCode) +
    (username.hashCode) +
    (password.hashCode);

  @override
  String toString() => 'CreateEmailProvider[id=$id, label=$label, endpoint=$endpoint, port=$port, mailbox=$mailbox, intervalMinutes=$intervalMinutes, maxAgeDays=$maxAgeDays, pageSize=$pageSize, enabled=$enabled, username=$username, password=$password]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'label'] = this.label;
      json[r'endpoint'] = this.endpoint;
      json[r'port'] = this.port;
      json[r'mailbox'] = this.mailbox;
      json[r'intervalMinutes'] = this.intervalMinutes;
      json[r'maxAgeDays'] = this.maxAgeDays;
      json[r'pageSize'] = this.pageSize;
      json[r'enabled'] = this.enabled;
      json[r'username'] = this.username;
      json[r'password'] = this.password;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static CreateEmailProvider? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "CreateEmailProvider[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "CreateEmailProvider[id]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "CreateEmailProvider[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "CreateEmailProvider[label]" has a null value in JSON.');
        assert(json.containsKey(r'endpoint'), 'Required key "CreateEmailProvider[endpoint]" is missing from JSON.');
        assert(json[r'endpoint'] != null, 'Required key "CreateEmailProvider[endpoint]" has a null value in JSON.');
        assert(json.containsKey(r'port'), 'Required key "CreateEmailProvider[port]" is missing from JSON.');
        assert(json[r'port'] != null, 'Required key "CreateEmailProvider[port]" has a null value in JSON.');
        assert(json.containsKey(r'mailbox'), 'Required key "CreateEmailProvider[mailbox]" is missing from JSON.');
        assert(json[r'mailbox'] != null, 'Required key "CreateEmailProvider[mailbox]" has a null value in JSON.');
        assert(json.containsKey(r'intervalMinutes'), 'Required key "CreateEmailProvider[intervalMinutes]" is missing from JSON.');
        assert(json[r'intervalMinutes'] != null, 'Required key "CreateEmailProvider[intervalMinutes]" has a null value in JSON.');
        assert(json.containsKey(r'maxAgeDays'), 'Required key "CreateEmailProvider[maxAgeDays]" is missing from JSON.');
        assert(json[r'maxAgeDays'] != null, 'Required key "CreateEmailProvider[maxAgeDays]" has a null value in JSON.');
        assert(json.containsKey(r'pageSize'), 'Required key "CreateEmailProvider[pageSize]" is missing from JSON.');
        assert(json[r'pageSize'] != null, 'Required key "CreateEmailProvider[pageSize]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "CreateEmailProvider[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "CreateEmailProvider[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'username'), 'Required key "CreateEmailProvider[username]" is missing from JSON.');
        assert(json[r'username'] != null, 'Required key "CreateEmailProvider[username]" has a null value in JSON.');
        assert(json.containsKey(r'password'), 'Required key "CreateEmailProvider[password]" is missing from JSON.');
        assert(json[r'password'] != null, 'Required key "CreateEmailProvider[password]" has a null value in JSON.');
        return true;
      }());

      return CreateEmailProvider(
        id: mapValueOfType<String>(json, r'id')!,
        label: mapValueOfType<String>(json, r'label')!,
        endpoint: mapValueOfType<String>(json, r'endpoint')!,
        port: mapValueOfType<int>(json, r'port')!,
        mailbox: mapValueOfType<String>(json, r'mailbox')!,
        intervalMinutes: mapValueOfType<int>(json, r'intervalMinutes')!,
        maxAgeDays: mapValueOfType<int>(json, r'maxAgeDays')!,
        pageSize: mapValueOfType<int>(json, r'pageSize')!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        username: mapValueOfType<String>(json, r'username')!,
        password: mapValueOfType<String>(json, r'password')!,
      );
    }
    return null;
  }

  static List<CreateEmailProvider> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateEmailProvider>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateEmailProvider.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateEmailProvider> mapFromJson(dynamic json) {
    final map = <String, CreateEmailProvider>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateEmailProvider.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<CreateEmailProvider>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateEmailProvider>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateEmailProvider.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'label',
    'endpoint',
    'port',
    'mailbox',
    'intervalMinutes',
    'maxAgeDays',
    'pageSize',
    'enabled',
    'username',
    'password',
  };
}
