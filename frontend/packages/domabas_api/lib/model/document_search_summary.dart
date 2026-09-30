// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentSearchSummary {
  DocumentSearchSummary({
    required this.id,
    required this.title,
    required this.kind,
    this.tags = const [],
    required this.createdAt,
    this.documentDate,
    this.processingState,
    this.thumbnail,
    this.original,
  });

  String id;

  String title;

  DocumentSearchSummaryKindEnum kind;

  List<String> tags;

  DateTime createdAt;

  String? documentDate;

  DocumentSearchSummaryProcessingStateEnum? processingState;

  DocumentThumbnail? thumbnail;

  DocumentSearchOriginal? original;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentSearchSummary &&
    other.id == id &&
    other.title == title &&
    other.kind == kind &&
    _deepEquality.equals(other.tags, tags) &&
    other.createdAt == createdAt &&
    other.documentDate == documentDate &&
    other.processingState == processingState &&
    other.thumbnail == thumbnail &&
    other.original == original;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (title.hashCode) +
    (kind.hashCode) +
    (tags.hashCode) +
    (createdAt.hashCode) +
    (documentDate == null ? 0 : documentDate!.hashCode) +
    (processingState == null ? 0 : processingState!.hashCode) +
    (thumbnail == null ? 0 : thumbnail!.hashCode) +
    (original == null ? 0 : original!.hashCode);

  @override
  String toString() => 'DocumentSearchSummary[id=$id, title=$title, kind=$kind, tags=$tags, createdAt=$createdAt, documentDate=$documentDate, processingState=$processingState, thumbnail=$thumbnail, original=$original]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'title'] = this.title;
      json[r'kind'] = this.kind;
      json[r'tags'] = this.tags;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    if (this.documentDate != null) {
      json[r'documentDate'] = this.documentDate;
    } else {
      json[r'documentDate'] = null;
    }
    if (this.processingState != null) {
      json[r'processingState'] = this.processingState;
    } else {
      json[r'processingState'] = null;
    }
    if (this.thumbnail != null) {
      json[r'thumbnail'] = this.thumbnail;
    } else {
      json[r'thumbnail'] = null;
    }
    if (this.original != null) {
      json[r'original'] = this.original;
    } else {
      json[r'original'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentSearchSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "DocumentSearchSummary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "DocumentSearchSummary[id]" has a null value in JSON.');
        assert(json.containsKey(r'title'), 'Required key "DocumentSearchSummary[title]" is missing from JSON.');
        assert(json[r'title'] != null, 'Required key "DocumentSearchSummary[title]" has a null value in JSON.');
        assert(json.containsKey(r'kind'), 'Required key "DocumentSearchSummary[kind]" is missing from JSON.');
        assert(json[r'kind'] != null, 'Required key "DocumentSearchSummary[kind]" has a null value in JSON.');
        assert(json.containsKey(r'tags'), 'Required key "DocumentSearchSummary[tags]" is missing from JSON.');
        assert(json[r'tags'] != null, 'Required key "DocumentSearchSummary[tags]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "DocumentSearchSummary[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "DocumentSearchSummary[createdAt]" has a null value in JSON.');
        return true;
      }());

      return DocumentSearchSummary(
        id: mapValueOfType<String>(json, r'id')!,
        title: mapValueOfType<String>(json, r'title')!,
        kind: DocumentSearchSummaryKindEnum.fromJson(json[r'kind'])!,
        tags: json[r'tags'] is Iterable
            ? (json[r'tags'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        documentDate: mapValueOfType<String>(json, r'documentDate'),
        processingState: DocumentSearchSummaryProcessingStateEnum.fromJson(json[r'processingState']),
        thumbnail: DocumentThumbnail.fromJson(json[r'thumbnail']),
        original: DocumentSearchOriginal.fromJson(json[r'original']),
      );
    }
    return null;
  }

  static List<DocumentSearchSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentSearchSummary> mapFromJson(dynamic json) {
    final map = <String, DocumentSearchSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentSearchSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentSearchSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentSearchSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentSearchSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'title',
    'kind',
    'tags',
    'createdAt',
  };
}

enum DocumentSearchSummaryKindEnum {
  document._(r'document'),
  letter._(r'letter'),
  email._(r'email'),
  ;

  const DocumentSearchSummaryKindEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchSummaryKindEnum? fromJson(dynamic value) => DocumentSearchSummaryKindEnumTypeTransformer().decode(value);

  static List<DocumentSearchSummaryKindEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchSummaryKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchSummaryKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchSummaryKindEnumTypeTransformer {
  factory DocumentSearchSummaryKindEnumTypeTransformer() => _instance ??= const DocumentSearchSummaryKindEnumTypeTransformer._();

  const DocumentSearchSummaryKindEnumTypeTransformer._();

  String encode(DocumentSearchSummaryKindEnum data) => data._value;

  DocumentSearchSummaryKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchSummaryKindEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'document': return DocumentSearchSummaryKindEnum.document;
        case r'letter': return DocumentSearchSummaryKindEnum.letter;
        case r'email': return DocumentSearchSummaryKindEnum.email;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchSummaryKindEnumTypeTransformer? _instance;
}

enum DocumentSearchSummaryProcessingStateEnum {
  queued._(r'queued'),
  processing._(r'processing'),
  ready._(r'ready'),
  failed._(r'failed'),
  ;

  const DocumentSearchSummaryProcessingStateEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchSummaryProcessingStateEnum? fromJson(dynamic value) => DocumentSearchSummaryProcessingStateEnumTypeTransformer().decode(value);

  static List<DocumentSearchSummaryProcessingStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchSummaryProcessingStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchSummaryProcessingStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchSummaryProcessingStateEnumTypeTransformer {
  factory DocumentSearchSummaryProcessingStateEnumTypeTransformer() => _instance ??= const DocumentSearchSummaryProcessingStateEnumTypeTransformer._();

  const DocumentSearchSummaryProcessingStateEnumTypeTransformer._();

  String encode(DocumentSearchSummaryProcessingStateEnum data) => data._value;

  DocumentSearchSummaryProcessingStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchSummaryProcessingStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return DocumentSearchSummaryProcessingStateEnum.queued;
        case r'processing': return DocumentSearchSummaryProcessingStateEnum.processing;
        case r'ready': return DocumentSearchSummaryProcessingStateEnum.ready;
        case r'failed': return DocumentSearchSummaryProcessingStateEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchSummaryProcessingStateEnumTypeTransformer? _instance;
}
