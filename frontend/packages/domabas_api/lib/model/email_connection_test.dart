// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailConnectionTest {
  EmailConnectionTest({
    required this.success,
    required this.failureCode,
    required this.checkedAt,
  });

  bool success;

  String? failureCode;

  DateTime checkedAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmailConnectionTest &&
    other.success == success &&
    other.failureCode == failureCode &&
    other.checkedAt == checkedAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (success.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (checkedAt.hashCode);

  @override
  String toString() => 'EmailConnectionTest[success=$success, failureCode=$failureCode, checkedAt=$checkedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'success'] = this.success;
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
      json[r'checkedAt'] = this.checkedAt.toUtc().toIso8601String();
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static EmailConnectionTest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'success'), 'Required key "EmailConnectionTest[success]" is missing from JSON.');
        assert(json[r'success'] != null, 'Required key "EmailConnectionTest[success]" has a null value in JSON.');
        assert(json.containsKey(r'failureCode'), 'Required key "EmailConnectionTest[failureCode]" is missing from JSON.');
        assert(json.containsKey(r'checkedAt'), 'Required key "EmailConnectionTest[checkedAt]" is missing from JSON.');
        assert(json[r'checkedAt'] != null, 'Required key "EmailConnectionTest[checkedAt]" has a null value in JSON.');
        return true;
      }());

      return EmailConnectionTest(
        success: mapValueOfType<bool>(json, r'success')!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        checkedAt: mapDateTime(json, r'checkedAt', r'')!,
      );
    }
    return null;
  }

  static List<EmailConnectionTest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailConnectionTest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailConnectionTest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailConnectionTest> mapFromJson(dynamic json) {
    final map = <String, EmailConnectionTest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailConnectionTest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<EmailConnectionTest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EmailConnectionTest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailConnectionTest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'success',
    'failureCode',
    'checkedAt',
  };
}
