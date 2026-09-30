// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatModel {
  ChatModel({
    required this.name,
  });

  String name;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatModel &&
    other.name == name;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (name.hashCode);

  @override
  String toString() => 'ChatModel[name=$name]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'name'] = this.name;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatModel? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'name'), 'Required key "ChatModel[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "ChatModel[name]" has a null value in JSON.');
        return true;
      }());

      return ChatModel(
        name: mapValueOfType<String>(json, r'name')!,
      );
    }
    return null;
  }

  static List<ChatModel> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatModel>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatModel.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatModel> mapFromJson(dynamic json) {
    final map = <String, ChatModel>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatModel.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatModel>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatModel>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatModel.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'name',
  };
}
