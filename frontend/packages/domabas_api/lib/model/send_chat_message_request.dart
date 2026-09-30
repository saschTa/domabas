// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SendChatMessageRequest {
  SendChatMessageRequest({
    required this.requestId,
    required this.content,
  });

  String requestId;

  String content;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SendChatMessageRequest &&
    other.requestId == requestId &&
    other.content == content;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (requestId.hashCode) +
    (content.hashCode);

  @override
  String toString() => 'SendChatMessageRequest[requestId=$requestId, content=$content]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'requestId'] = this.requestId;
      json[r'content'] = this.content;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static SendChatMessageRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'requestId'), 'Required key "SendChatMessageRequest[requestId]" is missing from JSON.');
        assert(json[r'requestId'] != null, 'Required key "SendChatMessageRequest[requestId]" has a null value in JSON.');
        assert(json.containsKey(r'content'), 'Required key "SendChatMessageRequest[content]" is missing from JSON.');
        assert(json[r'content'] != null, 'Required key "SendChatMessageRequest[content]" has a null value in JSON.');
        return true;
      }());

      return SendChatMessageRequest(
        requestId: mapValueOfType<String>(json, r'requestId')!,
        content: mapValueOfType<String>(json, r'content')!,
      );
    }
    return null;
  }

  static List<SendChatMessageRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SendChatMessageRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SendChatMessageRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SendChatMessageRequest> mapFromJson(dynamic json) {
    final map = <String, SendChatMessageRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SendChatMessageRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<SendChatMessageRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SendChatMessageRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SendChatMessageRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'requestId',
    'content',
  };
}
