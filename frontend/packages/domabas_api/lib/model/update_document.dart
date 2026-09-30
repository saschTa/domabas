// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateDocument {
  UpdateDocument({
    this.title,
    this.description,
    this.tags = const [],
    this.kind,
    this.sender,
    this.recipients = const [],
    this.cc = const [],
    this.bcc = const [],
    this.documentDate,
    this.subject,
    this.messageId,
  });

  String? title;

  String? description;

  List<String> tags;

  UpdateDocumentKindEnum? kind;

  String? sender;

  List<String> recipients;

  List<String> cc;

  List<String> bcc;

  String? documentDate;

  String? subject;

  String? messageId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateDocument &&
    other.title == title &&
    other.description == description &&
    _deepEquality.equals(other.tags, tags) &&
    other.kind == kind &&
    other.sender == sender &&
    _deepEquality.equals(other.recipients, recipients) &&
    _deepEquality.equals(other.cc, cc) &&
    _deepEquality.equals(other.bcc, bcc) &&
    other.documentDate == documentDate &&
    other.subject == subject &&
    other.messageId == messageId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (title == null ? 0 : title!.hashCode) +
    (description == null ? 0 : description!.hashCode) +
    (tags.hashCode) +
    (kind == null ? 0 : kind!.hashCode) +
    (sender == null ? 0 : sender!.hashCode) +
    (recipients.hashCode) +
    (cc.hashCode) +
    (bcc.hashCode) +
    (documentDate == null ? 0 : documentDate!.hashCode) +
    (subject == null ? 0 : subject!.hashCode) +
    (messageId == null ? 0 : messageId!.hashCode);

  @override
  String toString() => 'UpdateDocument[title=$title, description=$description, tags=$tags, kind=$kind, sender=$sender, recipients=$recipients, cc=$cc, bcc=$bcc, documentDate=$documentDate, subject=$subject, messageId=$messageId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.title != null) {
      json[r'title'] = this.title;
    } else {
      json[r'title'] = null;
    }
    if (this.description != null) {
      json[r'description'] = this.description;
    } else {
      json[r'description'] = null;
    }
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
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateDocument? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        return true;
      }());

      return UpdateDocument(
        title: mapValueOfType<String>(json, r'title'),
        description: mapValueOfType<String>(json, r'description'),
        tags: json[r'tags'] is Iterable
            ? (json[r'tags'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        kind: UpdateDocumentKindEnum.fromJson(json[r'kind']),
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
      );
    }
    return null;
  }

  static List<UpdateDocument> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateDocument>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateDocument.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateDocument> mapFromJson(dynamic json) {
    final map = <String, UpdateDocument>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateDocument.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateDocument>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateDocument>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateDocument.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
  };
}

enum UpdateDocumentKindEnum {
  document._(r'document'),
  letter._(r'letter'),
  email._(r'email'),
  ;

  const UpdateDocumentKindEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static UpdateDocumentKindEnum? fromJson(dynamic value) => UpdateDocumentKindEnumTypeTransformer().decode(value);

  static List<UpdateDocumentKindEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateDocumentKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateDocumentKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class UpdateDocumentKindEnumTypeTransformer {
  factory UpdateDocumentKindEnumTypeTransformer() => _instance ??= const UpdateDocumentKindEnumTypeTransformer._();

  const UpdateDocumentKindEnumTypeTransformer._();

  String encode(UpdateDocumentKindEnum data) => data._value;

  UpdateDocumentKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is UpdateDocumentKindEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'document': return UpdateDocumentKindEnum.document;
        case r'letter': return UpdateDocumentKindEnum.letter;
        case r'email': return UpdateDocumentKindEnum.email;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static UpdateDocumentKindEnumTypeTransformer? _instance;
}
