// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentFile {
  DocumentFile({
    required this.originalFilename,
    required this.mediaType,
    required this.size,
    required this.sha256,
    required this.ingestedAt,
    required this.uploaderId,
  });

  String originalFilename;

  DocumentFileMediaTypeEnum mediaType;

  int size;

  String sha256;

  DateTime ingestedAt;

  String uploaderId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentFile &&
    other.originalFilename == originalFilename &&
    other.mediaType == mediaType &&
    other.size == size &&
    other.sha256 == sha256 &&
    other.ingestedAt == ingestedAt &&
    other.uploaderId == uploaderId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (originalFilename.hashCode) +
    (mediaType.hashCode) +
    (size.hashCode) +
    (sha256.hashCode) +
    (ingestedAt.hashCode) +
    (uploaderId.hashCode);

  @override
  String toString() => 'DocumentFile[originalFilename=$originalFilename, mediaType=$mediaType, size=$size, sha256=$sha256, ingestedAt=$ingestedAt, uploaderId=$uploaderId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'originalFilename'] = this.originalFilename;
      json[r'mediaType'] = this.mediaType;
      json[r'size'] = this.size;
      json[r'sha256'] = this.sha256;
      json[r'ingestedAt'] = this.ingestedAt.toUtc().toIso8601String();
      json[r'uploaderId'] = this.uploaderId;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentFile? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'originalFilename'), 'Required key "DocumentFile[originalFilename]" is missing from JSON.');
        assert(json[r'originalFilename'] != null, 'Required key "DocumentFile[originalFilename]" has a null value in JSON.');
        assert(json.containsKey(r'mediaType'), 'Required key "DocumentFile[mediaType]" is missing from JSON.');
        assert(json[r'mediaType'] != null, 'Required key "DocumentFile[mediaType]" has a null value in JSON.');
        assert(json.containsKey(r'size'), 'Required key "DocumentFile[size]" is missing from JSON.');
        assert(json[r'size'] != null, 'Required key "DocumentFile[size]" has a null value in JSON.');
        assert(json.containsKey(r'sha256'), 'Required key "DocumentFile[sha256]" is missing from JSON.');
        assert(json[r'sha256'] != null, 'Required key "DocumentFile[sha256]" has a null value in JSON.');
        assert(json.containsKey(r'ingestedAt'), 'Required key "DocumentFile[ingestedAt]" is missing from JSON.');
        assert(json[r'ingestedAt'] != null, 'Required key "DocumentFile[ingestedAt]" has a null value in JSON.');
        assert(json.containsKey(r'uploaderId'), 'Required key "DocumentFile[uploaderId]" is missing from JSON.');
        assert(json[r'uploaderId'] != null, 'Required key "DocumentFile[uploaderId]" has a null value in JSON.');
        return true;
      }());

      return DocumentFile(
        originalFilename: mapValueOfType<String>(json, r'originalFilename')!,
        mediaType: DocumentFileMediaTypeEnum.fromJson(json[r'mediaType'])!,
        size: mapValueOfType<int>(json, r'size')!,
        sha256: mapValueOfType<String>(json, r'sha256')!,
        ingestedAt: mapDateTime(json, r'ingestedAt', r'')!,
        uploaderId: mapValueOfType<String>(json, r'uploaderId')!,
      );
    }
    return null;
  }

  static List<DocumentFile> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentFile>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentFile.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentFile> mapFromJson(dynamic json) {
    final map = <String, DocumentFile>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentFile.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentFile>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentFile>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentFile.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'originalFilename',
    'mediaType',
    'size',
    'sha256',
    'ingestedAt',
    'uploaderId',
  };
}

enum DocumentFileMediaTypeEnum {
  applicationSlashPdf._(r'application/pdf'),
  imageSlashPng._(r'image/png'),
  imageSlashJpeg._(r'image/jpeg'),
  messageSlashRfc822._(r'message/rfc822'),
  ;

  const DocumentFileMediaTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentFileMediaTypeEnum? fromJson(dynamic value) => DocumentFileMediaTypeEnumTypeTransformer().decode(value);

  static List<DocumentFileMediaTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentFileMediaTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentFileMediaTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentFileMediaTypeEnumTypeTransformer {
  factory DocumentFileMediaTypeEnumTypeTransformer() => _instance ??= const DocumentFileMediaTypeEnumTypeTransformer._();

  const DocumentFileMediaTypeEnumTypeTransformer._();

  String encode(DocumentFileMediaTypeEnum data) => data._value;

  DocumentFileMediaTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentFileMediaTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'application/pdf': return DocumentFileMediaTypeEnum.applicationSlashPdf;
        case r'image/png': return DocumentFileMediaTypeEnum.imageSlashPng;
        case r'image/jpeg': return DocumentFileMediaTypeEnum.imageSlashJpeg;
        case r'message/rfc822': return DocumentFileMediaTypeEnum.messageSlashRfc822;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentFileMediaTypeEnumTypeTransformer? _instance;
}
