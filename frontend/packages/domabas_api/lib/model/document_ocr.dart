// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentOCR {
  DocumentOCR({
    required this.status,
    required this.revision,
    required this.text,
    required this.origin,
    required this.reason,
    required this.semanticIndexing,
  });

  DocumentOCRStatusEnum status;

  int revision;

  String? text;

  DocumentOCROriginEnum? origin;

  DocumentOCRReasonEnum? reason;

  DocumentOCRSemanticIndexingEnum semanticIndexing;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentOCR &&
    other.status == status &&
    other.revision == revision &&
    other.text == text &&
    other.origin == origin &&
    other.reason == reason &&
    other.semanticIndexing == semanticIndexing;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (status.hashCode) +
    (revision.hashCode) +
    (text == null ? 0 : text!.hashCode) +
    (origin == null ? 0 : origin!.hashCode) +
    (reason == null ? 0 : reason!.hashCode) +
    (semanticIndexing.hashCode);

  @override
  String toString() => 'DocumentOCR[status=$status, revision=$revision, text=$text, origin=$origin, reason=$reason, semanticIndexing=$semanticIndexing]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'status'] = this.status;
      json[r'revision'] = this.revision;
    if (this.text != null) {
      json[r'text'] = this.text;
    } else {
      json[r'text'] = null;
    }
    if (this.origin != null) {
      json[r'origin'] = this.origin;
    } else {
      json[r'origin'] = null;
    }
    if (this.reason != null) {
      json[r'reason'] = this.reason;
    } else {
      json[r'reason'] = null;
    }
      json[r'semanticIndexing'] = this.semanticIndexing;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentOCR? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'status'), 'Required key "DocumentOCR[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "DocumentOCR[status]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "DocumentOCR[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "DocumentOCR[revision]" has a null value in JSON.');
        assert(json.containsKey(r'text'), 'Required key "DocumentOCR[text]" is missing from JSON.');
        assert(json.containsKey(r'origin'), 'Required key "DocumentOCR[origin]" is missing from JSON.');
        assert(json.containsKey(r'reason'), 'Required key "DocumentOCR[reason]" is missing from JSON.');
        assert(json.containsKey(r'semanticIndexing'), 'Required key "DocumentOCR[semanticIndexing]" is missing from JSON.');
        assert(json[r'semanticIndexing'] != null, 'Required key "DocumentOCR[semanticIndexing]" has a null value in JSON.');
        return true;
      }());

      return DocumentOCR(
        status: DocumentOCRStatusEnum.fromJson(json[r'status'])!,
        revision: mapValueOfType<int>(json, r'revision')!,
        text: mapValueOfType<String>(json, r'text'),
        origin: DocumentOCROriginEnum.fromJson(json[r'origin']),
        reason: DocumentOCRReasonEnum.fromJson(json[r'reason']),
        semanticIndexing: DocumentOCRSemanticIndexingEnum.fromJson(json[r'semanticIndexing'])!,
      );
    }
    return null;
  }

  static List<DocumentOCR> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentOCR>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentOCR.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentOCR> mapFromJson(dynamic json) {
    final map = <String, DocumentOCR>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentOCR.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentOCR>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentOCR>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentOCR.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'status',
    'revision',
    'text',
    'origin',
    'reason',
    'semanticIndexing',
  };
}

enum DocumentOCRStatusEnum {
  available._(r'available'),
  pending._(r'pending'),
  unavailable._(r'unavailable'),
  ;

  const DocumentOCRStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentOCRStatusEnum? fromJson(dynamic value) => DocumentOCRStatusEnumTypeTransformer().decode(value);

  static List<DocumentOCRStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentOCRStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentOCRStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentOCRStatusEnumTypeTransformer {
  factory DocumentOCRStatusEnumTypeTransformer() => _instance ??= const DocumentOCRStatusEnumTypeTransformer._();

  const DocumentOCRStatusEnumTypeTransformer._();

  String encode(DocumentOCRStatusEnum data) => data._value;

  DocumentOCRStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentOCRStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'available': return DocumentOCRStatusEnum.available;
        case r'pending': return DocumentOCRStatusEnum.pending;
        case r'unavailable': return DocumentOCRStatusEnum.unavailable;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentOCRStatusEnumTypeTransformer? _instance;
}

enum DocumentOCROriginEnum {
  machine._(r'machine'),
  manual._(r'manual'),
  ;

  const DocumentOCROriginEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentOCROriginEnum? fromJson(dynamic value) => DocumentOCROriginEnumTypeTransformer().decode(value);

  static List<DocumentOCROriginEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentOCROriginEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentOCROriginEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentOCROriginEnumTypeTransformer {
  factory DocumentOCROriginEnumTypeTransformer() => _instance ??= const DocumentOCROriginEnumTypeTransformer._();

  const DocumentOCROriginEnumTypeTransformer._();

  String encode(DocumentOCROriginEnum data) => data._value;

  DocumentOCROriginEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentOCROriginEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'machine': return DocumentOCROriginEnum.machine;
        case r'manual': return DocumentOCROriginEnum.manual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentOCROriginEnumTypeTransformer? _instance;
}

enum DocumentOCRReasonEnum {
  noOriginal._(r'no_original'),
  processing._(r'processing'),
  processingFailed._(r'processing_failed'),
  legacyTextMissing._(r'legacy_text_missing'),
  ;

  const DocumentOCRReasonEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentOCRReasonEnum? fromJson(dynamic value) => DocumentOCRReasonEnumTypeTransformer().decode(value);

  static List<DocumentOCRReasonEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentOCRReasonEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentOCRReasonEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentOCRReasonEnumTypeTransformer {
  factory DocumentOCRReasonEnumTypeTransformer() => _instance ??= const DocumentOCRReasonEnumTypeTransformer._();

  const DocumentOCRReasonEnumTypeTransformer._();

  String encode(DocumentOCRReasonEnum data) => data._value;

  DocumentOCRReasonEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentOCRReasonEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'no_original': return DocumentOCRReasonEnum.noOriginal;
        case r'processing': return DocumentOCRReasonEnum.processing;
        case r'processing_failed': return DocumentOCRReasonEnum.processingFailed;
        case r'legacy_text_missing': return DocumentOCRReasonEnum.legacyTextMissing;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentOCRReasonEnumTypeTransformer? _instance;
}

enum DocumentOCRSemanticIndexingEnum {
  unavailable._(r'unavailable'),
  pending._(r'pending'),
  ready._(r'ready'),
  failed._(r'failed'),
  notRequired._(r'not_required'),
  ;

  const DocumentOCRSemanticIndexingEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentOCRSemanticIndexingEnum? fromJson(dynamic value) => DocumentOCRSemanticIndexingEnumTypeTransformer().decode(value);

  static List<DocumentOCRSemanticIndexingEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentOCRSemanticIndexingEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentOCRSemanticIndexingEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentOCRSemanticIndexingEnumTypeTransformer {
  factory DocumentOCRSemanticIndexingEnumTypeTransformer() => _instance ??= const DocumentOCRSemanticIndexingEnumTypeTransformer._();

  const DocumentOCRSemanticIndexingEnumTypeTransformer._();

  String encode(DocumentOCRSemanticIndexingEnum data) => data._value;

  DocumentOCRSemanticIndexingEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentOCRSemanticIndexingEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'unavailable': return DocumentOCRSemanticIndexingEnum.unavailable;
        case r'pending': return DocumentOCRSemanticIndexingEnum.pending;
        case r'ready': return DocumentOCRSemanticIndexingEnum.ready;
        case r'failed': return DocumentOCRSemanticIndexingEnum.failed;
        case r'not_required': return DocumentOCRSemanticIndexingEnum.notRequired;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentOCRSemanticIndexingEnumTypeTransformer? _instance;
}
