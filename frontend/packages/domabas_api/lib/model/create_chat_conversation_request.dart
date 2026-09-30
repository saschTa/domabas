// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CreateChatConversationRequest {
  CreateChatConversationRequest({
    required this.requestId,
  });

  String requestId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateChatConversationRequest &&
    other.requestId == requestId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (requestId.hashCode);

  @override
  String toString() => 'CreateChatConversationRequest[requestId=$requestId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'requestId'] = this.requestId;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static CreateChatConversationRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'requestId'), 'Required key "CreateChatConversationRequest[requestId]" is missing from JSON.');
        assert(json[r'requestId'] != null, 'Required key "CreateChatConversationRequest[requestId]" has a null value in JSON.');
        return true;
      }());

      return CreateChatConversationRequest(
        requestId: mapValueOfType<String>(json, r'requestId')!,
      );
    }
    return null;
  }

  static List<CreateChatConversationRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateChatConversationRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateChatConversationRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateChatConversationRequest> mapFromJson(dynamic json) {
    final map = <String, CreateChatConversationRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateChatConversationRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<CreateChatConversationRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateChatConversationRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateChatConversationRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'requestId',
  };
}
