// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Document {
  Document({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.tags = const [],
    this.kind,
    this.sender,
    this.recipients = const [],
    this.cc = const [],
    this.bcc = const [],
    this.documentDate,
    this.subject,
    this.messageId,
    this.thumbnail,
    this.file,
    this.processing,
  });

  String id;

  String title;

  String description;

  DateTime createdAt;

  List<String> tags;

  DocumentKindEnum? kind;

  String? sender;

  List<String> recipients;

  List<String> cc;

  List<String> bcc;

  String? documentDate;

  String? subject;

  String? messageId;

  DocumentThumbnail? thumbnail;

  DocumentFile? file;

  DocumentProcessing? processing;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Document &&
    other.id == id &&
    other.title == title &&
    other.description == description &&
    other.createdAt == createdAt &&
    _deepEquality.equals(other.tags, tags) &&
    other.kind == kind &&
    other.sender == sender &&
    _deepEquality.equals(other.recipients, recipients) &&
    _deepEquality.equals(other.cc, cc) &&
    _deepEquality.equals(other.bcc, bcc) &&
    other.documentDate == documentDate &&
    other.subject == subject &&
    other.messageId == messageId &&
    other.thumbnail == thumbnail &&
    other.file == file &&
    other.processing == processing;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (title.hashCode) +
    (description.hashCode) +
    (createdAt.hashCode) +
    (tags.hashCode) +
    (kind == null ? 0 : kind!.hashCode) +
    (sender == null ? 0 : sender!.hashCode) +
    (recipients.hashCode) +
    (cc.hashCode) +
    (bcc.hashCode) +
    (documentDate == null ? 0 : documentDate!.hashCode) +
    (subject == null ? 0 : subject!.hashCode) +
    (messageId == null ? 0 : messageId!.hashCode) +
    (thumbnail == null ? 0 : thumbnail!.hashCode) +
    (file == null ? 0 : file!.hashCode) +
    (processing == null ? 0 : processing!.hashCode);

  @override
  String toString() => 'Document[id=$id, title=$title, description=$description, createdAt=$createdAt, tags=$tags, kind=$kind, sender=$sender, recipients=$recipients, cc=$cc, bcc=$bcc, documentDate=$documentDate, subject=$subject, messageId=$messageId, thumbnail=$thumbnail, file=$file, processing=$processing]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'title'] = this.title;
      json[r'description'] = this.description;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'tags'] = this.tags;
    if (this.kind != null) {
      json[r'kind'] = this.kind;
    } else {
      json[r'kind'] = null;
    }
    if (this.sender != null) {
      json[r'sender'] = this.sender;
    } else {
      json[r'sender'] = null;
    }
      json[r'recipients'] = this.recipients;
      json[r'cc'] = this.cc;
      json[r'bcc'] = this.bcc;
    if (this.documentDate != null) {
      json[r'documentDate'] = this.documentDate;
    } else {
      json[r'documentDate'] = null;
    }
    if (this.subject != null) {
      json[r'subject'] = this.subject;
    } else {
      json[r'subject'] = null;
    }
    if (this.messageId != null) {
      json[r'messageId'] = this.messageId;
    } else {
      json[r'messageId'] = null;
    }
    if (this.thumbnail != null) {
      json[r'thumbnail'] = this.thumbnail;
    } else {
      json[r'thumbnail'] = null;
    }
    if (this.file != null) {
      json[r'file'] = this.file;
    } else {
      json[r'file'] = null;
    }
    if (this.processing != null) {
      json[r'processing'] = this.processing;
    } else {
      json[r'processing'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static Document? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Document[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Document[id]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "Document[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "Document[title]" has a null value in JSON.');
        assert(json.containsKey(r'description'), 'Required key "Document[description]" is missing from JSON.');
        assert(json[r'description'] != null, 'Required key "Document[description]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "Document[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "Document[createdAt]" has a null value in JSON.');
        return true;
      }());

      return Document(
        id: mapValueOfType<String>(json, r'id')!,
        title: mapValueOfType<String>(json, r'title')!,
        description: mapValueOfType<String>(json, r'description')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        tags: json[r'tags'] is Iterable
            ? (json[r'tags'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        kind: DocumentKindEnum.fromJson(json[r'kind']),
        sender: mapValueOfType<String>(json, r'sender'),
        recipients: json[r'recipients'] is Iterable
            ? (json[r'recipients'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        cc: json[r'cc'] is Iterable
            ? (json[r'cc'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        bcc: json[r'bcc'] is Iterable
            ? (json[r'bcc'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        documentDate: mapValueOfType<String>(json, r'documentDate'),
        subject: mapValueOfType<String>(json, r'subject'),
        messageId: mapValueOfType<String>(json, r'messageId'),
        thumbnail: DocumentThumbnail.fromJson(json[r'thumbnail']),
        file: DocumentFile.fromJson(json[r'file']),
        processing: DocumentProcessing.fromJson(json[r'processing']),
      );
    }
    return null;
  }

  static List<Document> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Document>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Document.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Document> mapFromJson(dynamic json) {
    final map = <String, Document>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Document.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<Document>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Document>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Document.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'title',
    'description',
    'createdAt',
  };
}

enum DocumentKindEnum {
  document._(r'document'),
  letter._(r'letter'),
  email._(r'email'),
  ;

  const DocumentKindEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentKindEnum? fromJson(dynamic value) => DocumentKindEnumTypeTransformer().decode(value);

  static List<DocumentKindEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentKindEnumTypeTransformer {
  factory DocumentKindEnumTypeTransformer() => _instance ??= const DocumentKindEnumTypeTransformer._();

  const DocumentKindEnumTypeTransformer._();

  String encode(DocumentKindEnum data) => data._value;

  DocumentKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentKindEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'document': return DocumentKindEnum.document;
        case r'letter': return DocumentKindEnum.letter;
        case r'email': return DocumentKindEnum.email;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentKindEnumTypeTransformer? _instance;
}
