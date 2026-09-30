// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentEmailAttachment {
  DocumentEmailAttachment({
    required this.part_,
    required this.filename,
    required this.status,
    required this.failureCode,
    required this.document,
  });

  String part_;

  String filename;

  DocumentEmailAttachmentStatusEnum status;

  String? failureCode;

  DocumentLink? document;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentEmailAttachment &&
    other.part_ == part_ &&
    other.filename == filename &&
    other.status == status &&
    other.failureCode == failureCode &&
    other.document == document;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (part_.hashCode) +
    (filename.hashCode) +
    (status.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (document == null ? 0 : document!.hashCode);

  @override
  String toString() => 'DocumentEmailAttachment[part_=$part_, filename=$filename, status=$status, failureCode=$failureCode, document=$document]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'part'] = this.part_;
      json[r'filename'] = this.filename;
      json[r'status'] = this.status;
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
    if (this.document != null) {
      json[r'document'] = this.document;
    } else {
      json[r'document'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentEmailAttachment? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'part'), 'Required key "DocumentEmailAttachment[part]" is missing from JSON.');
        assert(json[r'part'] != null, 'Required key "DocumentEmailAttachment[part]" has a null value in JSON.');
        assert(json.containsKey(r'filename'), 'Required key "DocumentEmailAttachment[filename]" is missing from JSON.');
        assert(json[r'filename'] != null, 'Required key "DocumentEmailAttachment[filename]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "DocumentEmailAttachment[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "DocumentEmailAttachment[status]" has a null value in JSON.');
        assert(json.containsKey(r'failureCode'), 'Required key "DocumentEmailAttachment[failureCode]" is missing from JSON.');
        assert(json.containsKey(r'document'), 'Required key "DocumentEmailAttachment[document]" is missing from JSON.');
        return true;
      }());

      return DocumentEmailAttachment(
        part_: mapValueOfType<String>(json, r'part')!,
        filename: mapValueOfType<String>(json, r'filename')!,
        status: DocumentEmailAttachmentStatusEnum.fromJson(json[r'status'])!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        document: DocumentLink.fromJson(json[r'document']),
      );
    }
    return null;
  }

  static List<DocumentEmailAttachment> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentEmailAttachment>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentEmailAttachment.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentEmailAttachment> mapFromJson(dynamic json) {
    final map = <String, DocumentEmailAttachment>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentEmailAttachment.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentEmailAttachment>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentEmailAttachment>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentEmailAttachment.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'part',
    'filename',
    'status',
    'failureCode',
    'document',
  };
}

enum DocumentEmailAttachmentStatusEnum {
  accepted._(r'accepted'),
  reused._(r'reused'),
  skipped._(r'skipped'),
  failed._(r'failed'),
  pending._(r'pending'),
  deleted._(r'deleted'),
  ;

  const DocumentEmailAttachmentStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentEmailAttachmentStatusEnum? fromJson(dynamic value) => DocumentEmailAttachmentStatusEnumTypeTransformer().decode(value);

  static List<DocumentEmailAttachmentStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentEmailAttachmentStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentEmailAttachmentStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentEmailAttachmentStatusEnumTypeTransformer {
  factory DocumentEmailAttachmentStatusEnumTypeTransformer() => _instance ??= const DocumentEmailAttachmentStatusEnumTypeTransformer._();

  const DocumentEmailAttachmentStatusEnumTypeTransformer._();

  String encode(DocumentEmailAttachmentStatusEnum data) => data._value;

  DocumentEmailAttachmentStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentEmailAttachmentStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'accepted': return DocumentEmailAttachmentStatusEnum.accepted;
        case r'reused': return DocumentEmailAttachmentStatusEnum.reused;
        case r'skipped': return DocumentEmailAttachmentStatusEnum.skipped;
        case r'failed': return DocumentEmailAttachmentStatusEnum.failed;
        case r'pending': return DocumentEmailAttachmentStatusEnum.pending;
        case r'deleted': return DocumentEmailAttachmentStatusEnum.deleted;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentEmailAttachmentStatusEnumTypeTransformer? _instance;
}
