// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatSource {
  ChatSource({
    required this.documentId,
    required this.title,
    required this.excerpt,
  });

  String documentId;

  String title;

  String excerpt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatSource &&
    other.documentId == documentId &&
    other.title == title &&
    other.excerpt == excerpt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (documentId.hashCode) +
    (title.hashCode) +
    (excerpt.hashCode);

  @override
  String toString() => 'ChatSource[documentId=$documentId, title=$title, excerpt=$excerpt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'documentId'] = this.documentId;
      json[r'title'] = this.title;
      json[r'excerpt'] = this.excerpt;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatSource? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'documentId'), 'Required key "ChatSource[documentId]" is missing from JSON.');
        assert(json[r'documentId'] != null, 'Required key "ChatSource[documentId]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "ChatSource[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "ChatSource[title]" has a null value in JSON.');
        assert(json.containsKey(r'excerpt'), 'Required key "ChatSource[excerpt]" is missing from JSON.');
        assert(json[r'excerpt'] != null, 'Required key "ChatSource[excerpt]" has a null value in JSON.');
        return true;
      }());

      return ChatSource(
        documentId: mapValueOfType<String>(json, r'documentId')!,
        title: mapValueOfType<String>(json, r'title')!,
        excerpt: mapValueOfType<String>(json, r'excerpt')!,
      );
    }
    return null;
  }

  static List<ChatSource> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatSource>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatSource.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatSource> mapFromJson(dynamic json) {
    final map = <String, ChatSource>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatSource.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatSource>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatSource>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatSource.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'documentId',
    'title',
    'excerpt',
  };
}
