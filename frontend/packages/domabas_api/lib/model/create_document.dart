// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class CreateDocument {
  CreateDocument({
    required this.title,
    this.description = '',
  });

  String title;

  String description;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateDocument &&
    other.title == title &&
    other.description == description;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (title.hashCode) +
    (description.hashCode);

  @override
  String toString() => 'CreateDocument[title=$title, description=$description]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'title'] = this.title;
      json[r'description'] = this.description;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static CreateDocument? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'title'), 'Required key "CreateDocument[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "CreateDocument[title]" has a null value in JSON.');
        return true;
      }());

      return CreateDocument(
        title: mapValueOfType<String>(json, r'title')!,
        description: mapValueOfType<String>(json, r'description') ?? '',
      );
    }
    return null;
  }

  static List<CreateDocument> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateDocument>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateDocument.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateDocument> mapFromJson(dynamic json) {
    final map = <String, CreateDocument>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateDocument.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<CreateDocument>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateDocument>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateDocument.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'title',
  };
}
