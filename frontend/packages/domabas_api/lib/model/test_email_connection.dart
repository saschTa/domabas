// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class TestEmailConnection {
  TestEmailConnection({
    this.providerId,
    this.expectedRevision,
    required this.endpoint,
    required this.port,
    required this.mailbox,
    this.username,
    this.password,
  });

  String? providerId;

  int? expectedRevision;

  String endpoint;

  int port;

  String mailbox;

  String? username;

  String? password;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TestEmailConnection &&
    other.providerId == providerId &&
    other.expectedRevision == expectedRevision &&
    other.endpoint == endpoint &&
    other.port == port &&
    other.mailbox == mailbox &&
    other.username == username &&
    other.password == password;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (providerId == null ? 0 : providerId!.hashCode) +
    (expectedRevision == null ? 0 : expectedRevision!.hashCode) +
    (endpoint.hashCode) +
    (port.hashCode) +
    (mailbox.hashCode) +
    (username == null ? 0 : username!.hashCode) +
    (password == null ? 0 : password!.hashCode);

  @override
  String toString() => 'TestEmailConnection[providerId=$providerId, expectedRevision=$expectedRevision, endpoint=$endpoint, port=$port, mailbox=$mailbox, username=$username, password=$password]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.providerId != null) {
      json[r'providerId'] = this.providerId;
    } else {
      json[r'providerId'] = null;
    }
    if (this.expectedRevision != null) {
      json[r'expectedRevision'] = this.expectedRevision;
    } else {
      json[r'expectedRevision'] = null;
    }
      json[r'endpoint'] = this.endpoint;
      json[r'port'] = this.port;
      json[r'mailbox'] = this.mailbox;
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
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static TestEmailConnection? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'endpoint'), 'Required key "TestEmailConnection[endpoint]" is missing from JSON.');
        assert(json[r'endpoint'] != null, 'Required key "TestEmailConnection[endpoint]" has a null value in JSON.');
        assert(json.containsKey(r'port'), 'Required key "TestEmailConnection[port]" is missing from JSON.');
        assert(json[r'port'] != null, 'Required key "TestEmailConnection[port]" has a null value in JSON.');
        assert(json.containsKey(r'mailbox'), 'Required key "TestEmailConnection[mailbox]" is missing from JSON.');
        assert(json[r'mailbox'] != null, 'Required key "TestEmailConnection[mailbox]" has a null value in JSON.');
        return true;
      }());

      return TestEmailConnection(
        providerId: mapValueOfType<String>(json, r'providerId'),
        expectedRevision: mapValueOfType<int>(json, r'expectedRevision'),
        endpoint: mapValueOfType<String>(json, r'endpoint')!,
        port: mapValueOfType<int>(json, r'port')!,
        mailbox: mapValueOfType<String>(json, r'mailbox')!,
        username: mapValueOfType<String>(json, r'username'),
        password: mapValueOfType<String>(json, r'password'),
      );
    }
    return null;
  }

  static List<TestEmailConnection> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TestEmailConnection>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TestEmailConnection.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TestEmailConnection> mapFromJson(dynamic json) {
    final map = <String, TestEmailConnection>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TestEmailConnection.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<TestEmailConnection>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TestEmailConnection>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TestEmailConnection.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'endpoint',
    'port',
    'mailbox',
  };
}
