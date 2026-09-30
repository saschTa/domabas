// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentEmailLinks {
  DocumentEmailLinks({
    this.attachments = const [],
    required this.nextCursor,
  });

  List<DocumentEmailAttachment> attachments;

  String? nextCursor;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentEmailLinks &&
    _deepEquality.equals(other.attachments, attachments) &&
    other.nextCursor == nextCursor;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (attachments.hashCode) +
    (nextCursor == null ? 0 : nextCursor!.hashCode);

  @override
  String toString() => 'DocumentEmailLinks[attachments=$attachments, nextCursor=$nextCursor]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'attachments'] = this.attachments;
    if (this.nextCursor != null) {
      json[r'nextCursor'] = this.nextCursor;
    } else {
      json[r'nextCursor'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentEmailLinks? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'attachments'), 'Required key "DocumentEmailLinks[attachments]" is missing from JSON.');
        assert(json[r'attachments'] != null, 'Required key "DocumentEmailLinks[attachments]" has a null value in JSON.');
        assert(json.containsKey(r'nextCursor'), 'Required key "DocumentEmailLinks[nextCursor]" is missing from JSON.');
        return true;
      }());

      return DocumentEmailLinks(
        attachments: DocumentEmailAttachment.listFromJson(json[r'attachments']),
        nextCursor: mapValueOfType<String>(json, r'nextCursor'),
      );
    }
    return null;
  }

  static List<DocumentEmailLinks> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentEmailLinks>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentEmailLinks.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentEmailLinks> mapFromJson(dynamic json) {
    final map = <String, DocumentEmailLinks>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentEmailLinks.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentEmailLinks>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentEmailLinks>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentEmailLinks.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'attachments',
    'nextCursor',
  };
}
