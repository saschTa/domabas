// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatConversation {
  ChatConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.activeTurnId,
  });

  String id;

  String title;

  DateTime createdAt;

  DateTime updatedAt;

  String? activeTurnId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatConversation &&
    other.id == id &&
    other.title == title &&
    other.createdAt == createdAt &&
    other.updatedAt == updatedAt &&
    other.activeTurnId == activeTurnId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (title.hashCode) +
    (createdAt.hashCode) +
    (updatedAt.hashCode) +
    (activeTurnId == null ? 0 : activeTurnId!.hashCode);

  @override
  String toString() => 'ChatConversation[id=$id, title=$title, createdAt=$createdAt, updatedAt=$updatedAt, activeTurnId=$activeTurnId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'title'] = this.title;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    if (this.activeTurnId != null) {
      json[r'activeTurnId'] = this.activeTurnId;
    } else {
      json[r'activeTurnId'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatConversation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "ChatConversation[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "ChatConversation[id]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "ChatConversation[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "ChatConversation[title]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "ChatConversation[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "ChatConversation[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "ChatConversation[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "ChatConversation[updatedAt]" has a null value in JSON.');
        return true;
      }());

      return ChatConversation(
        id: mapValueOfType<String>(json, r'id')!,
        title: mapValueOfType<String>(json, r'title')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        activeTurnId: mapValueOfType<String>(json, r'activeTurnId'),
      );
    }
    return null;
  }

  static List<ChatConversation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatConversation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatConversation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatConversation> mapFromJson(dynamic json) {
    final map = <String, ChatConversation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatConversation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatConversation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatConversation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatConversation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'title',
    'createdAt',
    'updatedAt',
  };
}
