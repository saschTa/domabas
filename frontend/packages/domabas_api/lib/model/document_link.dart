// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentLink {
  DocumentLink({
    required this.documentId,
    required this.title,
    required this.mediaType,
  });

  String documentId;

  String title;

  DocumentLinkMediaTypeEnum mediaType;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentLink &&
    other.documentId == documentId &&
    other.title == title &&
    other.mediaType == mediaType;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (documentId.hashCode) +
    (title.hashCode) +
    (mediaType.hashCode);

  @override
  String toString() => 'DocumentLink[documentId=$documentId, title=$title, mediaType=$mediaType]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'documentId'] = this.documentId;
      json[r'title'] = this.title;
      json[r'mediaType'] = this.mediaType;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentLink? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'documentId'), 'Required key "DocumentLink[documentId]" is missing from JSON.');
        assert(json[r'documentId'] != null, 'Required key "DocumentLink[documentId]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "DocumentLink[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "DocumentLink[title]" has a null value in JSON.');
        assert(json.containsKey(r'mediaType'), 'Required key "DocumentLink[mediaType]" is missing from JSON.');
        assert(json[r'mediaType'] != null, 'Required key "DocumentLink[mediaType]" has a null value in JSON.');
        return true;
      }());

      return DocumentLink(
        documentId: mapValueOfType<String>(json, r'documentId')!,
        title: mapValueOfType<String>(json, r'title')!,
        mediaType: DocumentLinkMediaTypeEnum.fromJson(json[r'mediaType'])!,
      );
    }
    return null;
  }

  static List<DocumentLink> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentLink>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentLink.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentLink> mapFromJson(dynamic json) {
    final map = <String, DocumentLink>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentLink.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentLink>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentLink>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentLink.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'documentId',
    'title',
    'mediaType',
  };
}

enum DocumentLinkMediaTypeEnum {
  applicationSlashPdf._(r'application/pdf'),
  imageSlashPng._(r'image/png'),
  imageSlashJpeg._(r'image/jpeg'),
  messageSlashRfc822._(r'message/rfc822'),
  ;

  const DocumentLinkMediaTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentLinkMediaTypeEnum? fromJson(dynamic value) => DocumentLinkMediaTypeEnumTypeTransformer().decode(value);

  static List<DocumentLinkMediaTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentLinkMediaTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentLinkMediaTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentLinkMediaTypeEnumTypeTransformer {
  factory DocumentLinkMediaTypeEnumTypeTransformer() => _instance ??= const DocumentLinkMediaTypeEnumTypeTransformer._();

  const DocumentLinkMediaTypeEnumTypeTransformer._();

  String encode(DocumentLinkMediaTypeEnum data) => data._value;

  DocumentLinkMediaTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentLinkMediaTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'application/pdf': return DocumentLinkMediaTypeEnum.applicationSlashPdf;
        case r'image/png': return DocumentLinkMediaTypeEnum.imageSlashPng;
        case r'image/jpeg': return DocumentLinkMediaTypeEnum.imageSlashJpeg;
        case r'message/rfc822': return DocumentLinkMediaTypeEnum.messageSlashRfc822;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentLinkMediaTypeEnumTypeTransformer? _instance;
}
