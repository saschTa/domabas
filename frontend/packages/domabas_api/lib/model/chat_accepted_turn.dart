// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatAcceptedTurn {
  ChatAcceptedTurn({
    required this.userMessage,
    required this.assistantMessage,
  });

  ChatMessage userMessage;

  ChatMessage assistantMessage;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatAcceptedTurn &&
    other.userMessage == userMessage &&
    other.assistantMessage == assistantMessage;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (userMessage.hashCode) +
    (assistantMessage.hashCode);

  @override
  String toString() => 'ChatAcceptedTurn[userMessage=$userMessage, assistantMessage=$assistantMessage]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'userMessage'] = this.userMessage;
      json[r'assistantMessage'] = this.assistantMessage;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatAcceptedTurn? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'userMessage'), 'Required key "ChatAcceptedTurn[userMessage]" is missing from JSON.');
        assert(json[r'userMessage'] != null, 'Required key "ChatAcceptedTurn[userMessage]" has a null value in JSON.');
        assert(json.containsKey(r'assistantMessage'), 'Required key "ChatAcceptedTurn[assistantMessage]" is missing from JSON.');
        assert(json[r'assistantMessage'] != null, 'Required key "ChatAcceptedTurn[assistantMessage]" has a null value in JSON.');
        return true;
      }());

      return ChatAcceptedTurn(
        userMessage: ChatMessage.fromJson(json[r'userMessage'])!,
        assistantMessage: ChatMessage.fromJson(json[r'assistantMessage'])!,
      );
    }
    return null;
  }

  static List<ChatAcceptedTurn> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatAcceptedTurn>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatAcceptedTurn.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatAcceptedTurn> mapFromJson(dynamic json) {
    final map = <String, ChatAcceptedTurn>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatAcceptedTurn.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatAcceptedTurn>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatAcceptedTurn>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatAcceptedTurn.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'userMessage',
    'assistantMessage',
  };
}
