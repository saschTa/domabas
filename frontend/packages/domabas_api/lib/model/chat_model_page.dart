// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatModelPage {
  ChatModelPage({
    this.items = const [],
    this.nextOffset,
  });

  List<ChatModel> items;

  int? nextOffset;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatModelPage &&
    _deepEquality.equals(other.items, items) &&
    other.nextOffset == nextOffset;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (nextOffset == null ? 0 : nextOffset!.hashCode);

  @override
  String toString() => 'ChatModelPage[items=$items, nextOffset=$nextOffset]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
    if (this.nextOffset != null) {
      json[r'nextOffset'] = this.nextOffset;
    } else {
      json[r'nextOffset'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatModelPage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "ChatModelPage[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "ChatModelPage[items]" has a null value in JSON.');
        return true;
      }());

      return ChatModelPage(
        items: ChatModel.listFromJson(json[r'items']),
        nextOffset: mapValueOfType<int>(json, r'nextOffset'),
      );
    }
    return null;
  }

  static List<ChatModelPage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatModelPage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatModelPage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatModelPage> mapFromJson(dynamic json) {
    final map = <String, ChatModelPage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatModelPage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatModelPage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatModelPage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatModelPage.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
  };
}
