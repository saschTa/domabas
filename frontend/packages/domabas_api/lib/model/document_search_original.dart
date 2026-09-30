// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentSearchOriginal {
  DocumentSearchOriginal({
    required this.sha256,
    required this.mediaType,
    required this.size,
  });

  String sha256;

  DocumentSearchOriginalMediaTypeEnum mediaType;

  int size;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentSearchOriginal &&
    other.sha256 == sha256 &&
    other.mediaType == mediaType &&
    other.size == size;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (sha256.hashCode) +
    (mediaType.hashCode) +
    (size.hashCode);

  @override
  String toString() => 'DocumentSearchOriginal[sha256=$sha256, mediaType=$mediaType, size=$size]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'sha256'] = this.sha256;
      json[r'mediaType'] = this.mediaType;
      json[r'size'] = this.size;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentSearchOriginal? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'sha256'), 'Required key "DocumentSearchOriginal[sha256]" is missing from JSON.');
        assert(json[r'sha256'] != null, 'Required key "DocumentSearchOriginal[sha256]" has a null value in JSON.');
        assert(json.containsKey(r'mediaType'), 'Required key "DocumentSearchOriginal[mediaType]" is missing from JSON.');
        assert(json[r'mediaType'] != null, 'Required key "DocumentSearchOriginal[mediaType]" has a null value in JSON.');
        assert(json.containsKey(r'size'), 'Required key "DocumentSearchOriginal[size]" is missing from JSON.');
        assert(json[r'size'] != null, 'Required key "DocumentSearchOriginal[size]" has a null value in JSON.');
        return true;
      }());

      return DocumentSearchOriginal(
        sha256: mapValueOfType<String>(json, r'sha256')!,
        mediaType: DocumentSearchOriginalMediaTypeEnum.fromJson(json[r'mediaType'])!,
        size: mapValueOfType<int>(json, r'size')!,
      );
    }
    return null;
  }

  static List<DocumentSearchOriginal> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchOriginal>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchOriginal.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentSearchOriginal> mapFromJson(dynamic json) {
    final map = <String, DocumentSearchOriginal>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentSearchOriginal.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentSearchOriginal>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentSearchOriginal>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentSearchOriginal.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'sha256',
    'mediaType',
    'size',
  };
}

enum DocumentSearchOriginalMediaTypeEnum {
  applicationSlashPdf._(r'application/pdf'),
  imageSlashPng._(r'image/png'),
  imageSlashJpeg._(r'image/jpeg'),
  messageSlashRfc822._(r'message/rfc822'),
  ;

  const DocumentSearchOriginalMediaTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchOriginalMediaTypeEnum? fromJson(dynamic value) => DocumentSearchOriginalMediaTypeEnumTypeTransformer().decode(value);

  static List<DocumentSearchOriginalMediaTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchOriginalMediaTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchOriginalMediaTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchOriginalMediaTypeEnumTypeTransformer {
  factory DocumentSearchOriginalMediaTypeEnumTypeTransformer() => _instance ??= const DocumentSearchOriginalMediaTypeEnumTypeTransformer._();

  const DocumentSearchOriginalMediaTypeEnumTypeTransformer._();

  String encode(DocumentSearchOriginalMediaTypeEnum data) => data._value;

  DocumentSearchOriginalMediaTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchOriginalMediaTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'application/pdf': return DocumentSearchOriginalMediaTypeEnum.applicationSlashPdf;
        case r'image/png': return DocumentSearchOriginalMediaTypeEnum.imageSlashPng;
        case r'image/jpeg': return DocumentSearchOriginalMediaTypeEnum.imageSlashJpeg;
        case r'message/rfc822': return DocumentSearchOriginalMediaTypeEnum.messageSlashRfc822;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchOriginalMediaTypeEnumTypeTransformer? _instance;
}
