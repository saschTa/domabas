// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class StartPaperlessRun {
  StartPaperlessRun({
    required this.requestId,
    required this.serverUrl,
    required this.token,
  });

  String requestId;

  String serverUrl;

  String token;

  @override
  bool operator ==(Object other) => identical(this, other) || other is StartPaperlessRun &&
    other.requestId == requestId &&
    other.serverUrl == serverUrl &&
    other.token == token;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (requestId.hashCode) +
    (serverUrl.hashCode) +
    (token.hashCode);

  @override
  String toString() => 'StartPaperlessRun[requestId=$requestId, serverUrl=$serverUrl, token=$token]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'requestId'] = this.requestId;
      json[r'serverUrl'] = this.serverUrl;
      json[r'token'] = this.token;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static StartPaperlessRun? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'requestId'), 'Required key "StartPaperlessRun[requestId]" is missing from JSON.');
        assert(json[r'requestId'] != null, 'Required key "StartPaperlessRun[requestId]" has a null value in JSON.');
        assert(json.containsKey(r'serverUrl'), 'Required key "StartPaperlessRun[serverUrl]" is missing from JSON.');
        assert(json[r'serverUrl'] != null, 'Required key "StartPaperlessRun[serverUrl]" has a null value in JSON.');
        assert(json.containsKey(r'token'), 'Required key "StartPaperlessRun[token]" is missing from JSON.');
        assert(json[r'token'] != null, 'Required key "StartPaperlessRun[token]" has a null value in JSON.');
        return true;
      }());

      return StartPaperlessRun(
        requestId: mapValueOfType<String>(json, r'requestId')!,
        serverUrl: mapValueOfType<String>(json, r'serverUrl')!,
        token: mapValueOfType<String>(json, r'token')!,
      );
    }
    return null;
  }

  static List<StartPaperlessRun> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <StartPaperlessRun>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = StartPaperlessRun.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, StartPaperlessRun> mapFromJson(dynamic json) {
    final map = <String, StartPaperlessRun>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = StartPaperlessRun.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<StartPaperlessRun>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<StartPaperlessRun>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = StartPaperlessRun.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'requestId',
    'serverUrl',
    'token',
  };
}
