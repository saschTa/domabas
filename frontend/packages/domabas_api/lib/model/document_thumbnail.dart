// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentThumbnail {
  DocumentThumbnail({
    required this.sourceSha256,
    required this.sha256,
    required this.mediaType,
    required this.size,
    required this.width,
    required this.height,
    required this.rendererRevision,
  });

  String sourceSha256;

  String sha256;

  DocumentThumbnailMediaTypeEnum mediaType;

  int size;

  int width;

  int height;

  int rendererRevision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentThumbnail &&
    other.sourceSha256 == sourceSha256 &&
    other.sha256 == sha256 &&
    other.mediaType == mediaType &&
    other.size == size &&
    other.width == width &&
    other.height == height &&
    other.rendererRevision == rendererRevision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (sourceSha256.hashCode) +
    (sha256.hashCode) +
    (mediaType.hashCode) +
    (size.hashCode) +
    (width.hashCode) +
    (height.hashCode) +
    (rendererRevision.hashCode);

  @override
  String toString() => 'DocumentThumbnail[sourceSha256=$sourceSha256, sha256=$sha256, mediaType=$mediaType, size=$size, width=$width, height=$height, rendererRevision=$rendererRevision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'sourceSha256'] = this.sourceSha256;
      json[r'sha256'] = this.sha256;
      json[r'mediaType'] = this.mediaType;
      json[r'size'] = this.size;
      json[r'width'] = this.width;
      json[r'height'] = this.height;
      json[r'rendererRevision'] = this.rendererRevision;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentThumbnail? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'sourceSha256'), 'Required key "DocumentThumbnail[sourceSha256]" is missing from JSON.');
        assert(json[r'sourceSha256'] != null, 'Required key "DocumentThumbnail[sourceSha256]" has a null value in JSON.');
        assert(json.containsKey(r'sha256'), 'Required key "DocumentThumbnail[sha256]" is missing from JSON.');
        assert(json[r'sha256'] != null, 'Required key "DocumentThumbnail[sha256]" has a null value in JSON.');
        assert(json.containsKey(r'mediaType'), 'Required key "DocumentThumbnail[mediaType]" is missing from JSON.');
        assert(json[r'mediaType'] != null, 'Required key "DocumentThumbnail[mediaType]" has a null value in JSON.');
        assert(json.containsKey(r'size'), 'Required key "DocumentThumbnail[size]" is missing from JSON.');
        assert(json[r'size'] != null, 'Required key "DocumentThumbnail[size]" has a null value in JSON.');
        assert(json.containsKey(r'width'), 'Required key "DocumentThumbnail[width]" is missing from JSON.');
        assert(json[r'width'] != null, 'Required key "DocumentThumbnail[width]" has a null value in JSON.');
        assert(json.containsKey(r'height'), 'Required key "DocumentThumbnail[height]" is missing from JSON.');
        assert(json[r'height'] != null, 'Required key "DocumentThumbnail[height]" has a null value in JSON.');
        assert(json.containsKey(r'rendererRevision'), 'Required key "DocumentThumbnail[rendererRevision]" is missing from JSON.');
        assert(json[r'rendererRevision'] != null, 'Required key "DocumentThumbnail[rendererRevision]" has a null value in JSON.');
        return true;
      }());

      return DocumentThumbnail(
        sourceSha256: mapValueOfType<String>(json, r'sourceSha256')!,
        sha256: mapValueOfType<String>(json, r'sha256')!,
        mediaType: DocumentThumbnailMediaTypeEnum.fromJson(json[r'mediaType'])!,
        size: mapValueOfType<int>(json, r'size')!,
        width: mapValueOfType<int>(json, r'width')!,
        height: mapValueOfType<int>(json, r'height')!,
        rendererRevision: mapValueOfType<int>(json, r'rendererRevision')!,
      );
    }
    return null;
  }

  static List<DocumentThumbnail> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentThumbnail>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentThumbnail.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentThumbnail> mapFromJson(dynamic json) {
    final map = <String, DocumentThumbnail>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentThumbnail.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentThumbnail>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentThumbnail>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentThumbnail.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'sourceSha256',
    'sha256',
    'mediaType',
    'size',
    'width',
    'height',
    'rendererRevision',
  };
}

enum DocumentThumbnailMediaTypeEnum {
  imageSlashJpeg._(r'image/jpeg'),
  ;

  const DocumentThumbnailMediaTypeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentThumbnailMediaTypeEnum? fromJson(dynamic value) => DocumentThumbnailMediaTypeEnumTypeTransformer().decode(value);

  static List<DocumentThumbnailMediaTypeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentThumbnailMediaTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentThumbnailMediaTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentThumbnailMediaTypeEnumTypeTransformer {
  factory DocumentThumbnailMediaTypeEnumTypeTransformer() => _instance ??= const DocumentThumbnailMediaTypeEnumTypeTransformer._();

  const DocumentThumbnailMediaTypeEnumTypeTransformer._();

  String encode(DocumentThumbnailMediaTypeEnum data) => data._value;

  DocumentThumbnailMediaTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentThumbnailMediaTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'image/jpeg': return DocumentThumbnailMediaTypeEnum.imageSlashJpeg;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentThumbnailMediaTypeEnumTypeTransformer? _instance;
}
