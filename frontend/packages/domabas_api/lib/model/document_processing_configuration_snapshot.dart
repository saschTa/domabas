// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentProcessingConfigurationSnapshot {
  DocumentProcessingConfigurationSnapshot({
    this.propertyExtractionEnabled,
    this.propertyExtractionModel,
    this.invoiceExtractionEnabled,
    this.invoiceExtractionModel,
    required this.revision,
    required this.language,
    required this.segmentation,
    required this.ocrEngine,
    required this.ocrVersion,
    required this.ocrModel,
    required this.embeddingModel,
    required this.embeddingDigest,
    required this.embeddingDimensions,
    this.ocrWeights = const {},
    required this.fingerprint,
    required this.manifestRevision,
    required this.extractionRevision,
    required this.chunkingRevision,
    required this.embeddingInputRevision,
    required this.indexingRevision,
  });

  bool? propertyExtractionEnabled;

  String? propertyExtractionModel;

  bool? invoiceExtractionEnabled;

  String? invoiceExtractionModel;

  int revision;

  DocumentProcessingConfigurationSnapshotLanguageEnum language;

  DocumentProcessingConfigurationSnapshotSegmentationEnum segmentation;

  String ocrEngine;

  String ocrVersion;

  String ocrModel;

  String embeddingModel;

  String embeddingDigest;

  int embeddingDimensions;

  Set<DocumentProcessingWeight> ocrWeights;

  String fingerprint;

  int manifestRevision;

  String extractionRevision;

  String chunkingRevision;

  String embeddingInputRevision;

  String indexingRevision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentProcessingConfigurationSnapshot &&
    other.propertyExtractionEnabled == propertyExtractionEnabled &&
    other.propertyExtractionModel == propertyExtractionModel &&
    other.invoiceExtractionEnabled == invoiceExtractionEnabled &&
    other.invoiceExtractionModel == invoiceExtractionModel &&
    other.revision == revision &&
    other.language == language &&
    other.segmentation == segmentation &&
    other.ocrEngine == ocrEngine &&
    other.ocrVersion == ocrVersion &&
    other.ocrModel == ocrModel &&
    other.embeddingModel == embeddingModel &&
    other.embeddingDigest == embeddingDigest &&
    other.embeddingDimensions == embeddingDimensions &&
    _deepEquality.equals(other.ocrWeights, ocrWeights) &&
    other.fingerprint == fingerprint &&
    other.manifestRevision == manifestRevision &&
    other.extractionRevision == extractionRevision &&
    other.chunkingRevision == chunkingRevision &&
    other.embeddingInputRevision == embeddingInputRevision &&
    other.indexingRevision == indexingRevision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (propertyExtractionEnabled == null ? 0 : propertyExtractionEnabled!.hashCode) +
    (propertyExtractionModel == null ? 0 : propertyExtractionModel!.hashCode) +
    (invoiceExtractionEnabled == null ? 0 : invoiceExtractionEnabled!.hashCode) +
    (invoiceExtractionModel == null ? 0 : invoiceExtractionModel!.hashCode) +
    (revision.hashCode) +
    (language.hashCode) +
    (segmentation.hashCode) +
    (ocrEngine.hashCode) +
    (ocrVersion.hashCode) +
    (ocrModel.hashCode) +
    (embeddingModel.hashCode) +
    (embeddingDigest.hashCode) +
    (embeddingDimensions.hashCode) +
    (ocrWeights.hashCode) +
    (fingerprint.hashCode) +
    (manifestRevision.hashCode) +
    (extractionRevision.hashCode) +
    (chunkingRevision.hashCode) +
    (embeddingInputRevision.hashCode) +
    (indexingRevision.hashCode);

  @override
  String toString() => 'DocumentProcessingConfigurationSnapshot[propertyExtractionEnabled=$propertyExtractionEnabled, propertyExtractionModel=$propertyExtractionModel, invoiceExtractionEnabled=$invoiceExtractionEnabled, invoiceExtractionModel=$invoiceExtractionModel, revision=$revision, language=$language, segmentation=$segmentation, ocrEngine=$ocrEngine, ocrVersion=$ocrVersion, ocrModel=$ocrModel, embeddingModel=$embeddingModel, embeddingDigest=$embeddingDigest, embeddingDimensions=$embeddingDimensions, ocrWeights=$ocrWeights, fingerprint=$fingerprint, manifestRevision=$manifestRevision, extractionRevision=$extractionRevision, chunkingRevision=$chunkingRevision, embeddingInputRevision=$embeddingInputRevision, indexingRevision=$indexingRevision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.propertyExtractionEnabled != null) {
      json[r'propertyExtractionEnabled'] = this.propertyExtractionEnabled;
    } else {
      json[r'propertyExtractionEnabled'] = null;
    }
    if (this.propertyExtractionModel != null) {
      json[r'propertyExtractionModel'] = this.propertyExtractionModel;
    } else {
      json[r'propertyExtractionModel'] = null;
    }
    if (this.invoiceExtractionEnabled != null) {
      json[r'invoiceExtractionEnabled'] = this.invoiceExtractionEnabled;
    } else {
      json[r'invoiceExtractionEnabled'] = null;
    }
    if (this.invoiceExtractionModel != null) {
      json[r'invoiceExtractionModel'] = this.invoiceExtractionModel;
    } else {
      json[r'invoiceExtractionModel'] = null;
    }
      json[r'revision'] = this.revision;
      json[r'language'] = this.language;
      json[r'segmentation'] = this.segmentation;
      json[r'ocrEngine'] = this.ocrEngine;
      json[r'ocrVersion'] = this.ocrVersion;
      json[r'ocrModel'] = this.ocrModel;
      json[r'embeddingModel'] = this.embeddingModel;
      json[r'embeddingDigest'] = this.embeddingDigest;
      json[r'embeddingDimensions'] = this.embeddingDimensions;
      json[r'ocrWeights'] = this.ocrWeights.toList(growable: false);
      json[r'fingerprint'] = this.fingerprint;
      json[r'manifestRevision'] = this.manifestRevision;
      json[r'extractionRevision'] = this.extractionRevision;
      json[r'chunkingRevision'] = this.chunkingRevision;
      json[r'embeddingInputRevision'] = this.embeddingInputRevision;
      json[r'indexingRevision'] = this.indexingRevision;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentProcessingConfigurationSnapshot? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'revision'), 'Required key "DocumentProcessingConfigurationSnapshot[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[revision]" has a null value in JSON.');
        assert(json.containsKey(r'language'), 'Required key "DocumentProcessingConfigurationSnapshot[language]" is missing from JSON.');
        assert(json[r'language'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[language]" has a null value in JSON.');
        assert(json.containsKey(r'segmentation'), 'Required key "DocumentProcessingConfigurationSnapshot[segmentation]" is missing from JSON.');
        assert(json[r'segmentation'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[segmentation]" has a null value in JSON.');
        assert(json.containsKey(r'ocrEngine'), 'Required key "DocumentProcessingConfigurationSnapshot[ocrEngine]" is missing from JSON.');
        assert(json[r'ocrEngine'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[ocrEngine]" has a null value in JSON.');
        assert(json.containsKey(r'ocrVersion'), 'Required key "DocumentProcessingConfigurationSnapshot[ocrVersion]" is missing from JSON.');
        assert(json[r'ocrVersion'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[ocrVersion]" has a null value in JSON.');
        assert(json.containsKey(r'ocrModel'), 'Required key "DocumentProcessingConfigurationSnapshot[ocrModel]" is missing from JSON.');
        assert(json[r'ocrModel'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[ocrModel]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingModel'), 'Required key "DocumentProcessingConfigurationSnapshot[embeddingModel]" is missing from JSON.');
        assert(json[r'embeddingModel'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[embeddingModel]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingDigest'), 'Required key "DocumentProcessingConfigurationSnapshot[embeddingDigest]" is missing from JSON.');
        assert(json[r'embeddingDigest'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[embeddingDigest]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingDimensions'), 'Required key "DocumentProcessingConfigurationSnapshot[embeddingDimensions]" is missing from JSON.');
        assert(json[r'embeddingDimensions'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[embeddingDimensions]" has a null value in JSON.');
        assert(json.containsKey(r'ocrWeights'), 'Required key "DocumentProcessingConfigurationSnapshot[ocrWeights]" is missing from JSON.');
        assert(json[r'ocrWeights'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[ocrWeights]" has a null value in JSON.');
        assert(json.containsKey(r'fingerprint'), 'Required key "DocumentProcessingConfigurationSnapshot[fingerprint]" is missing from JSON.');
        assert(json[r'fingerprint'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[fingerprint]" has a null value in JSON.');
        assert(json.containsKey(r'manifestRevision'), 'Required key "DocumentProcessingConfigurationSnapshot[manifestRevision]" is missing from JSON.');
        assert(json[r'manifestRevision'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[manifestRevision]" has a null value in JSON.');
        assert(json.containsKey(r'extractionRevision'), 'Required key "DocumentProcessingConfigurationSnapshot[extractionRevision]" is missing from JSON.');
        assert(json[r'extractionRevision'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[extractionRevision]" has a null value in JSON.');
        assert(json.containsKey(r'chunkingRevision'), 'Required key "DocumentProcessingConfigurationSnapshot[chunkingRevision]" is missing from JSON.');
        assert(json[r'chunkingRevision'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[chunkingRevision]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingInputRevision'), 'Required key "DocumentProcessingConfigurationSnapshot[embeddingInputRevision]" is missing from JSON.');
        assert(json[r'embeddingInputRevision'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[embeddingInputRevision]" has a null value in JSON.');
        assert(json.containsKey(r'indexingRevision'), 'Required key "DocumentProcessingConfigurationSnapshot[indexingRevision]" is missing from JSON.');
        assert(json[r'indexingRevision'] != null, 'Required key "DocumentProcessingConfigurationSnapshot[indexingRevision]" has a null value in JSON.');
        return true;
      }());

      return DocumentProcessingConfigurationSnapshot(
        propertyExtractionEnabled: mapValueOfType<bool>(json, r'propertyExtractionEnabled'),
        propertyExtractionModel: mapValueOfType<String>(json, r'propertyExtractionModel'),
        invoiceExtractionEnabled: mapValueOfType<bool>(json, r'invoiceExtractionEnabled'),
        invoiceExtractionModel: mapValueOfType<String>(json, r'invoiceExtractionModel'),
        revision: mapValueOfType<int>(json, r'revision')!,
        language: DocumentProcessingConfigurationSnapshotLanguageEnum.fromJson(json[r'language'])!,
        segmentation: DocumentProcessingConfigurationSnapshotSegmentationEnum.fromJson(json[r'segmentation'])!,
        ocrEngine: mapValueOfType<String>(json, r'ocrEngine')!,
        ocrVersion: mapValueOfType<String>(json, r'ocrVersion')!,
        ocrModel: mapValueOfType<String>(json, r'ocrModel')!,
        embeddingModel: mapValueOfType<String>(json, r'embeddingModel')!,
        embeddingDigest: mapValueOfType<String>(json, r'embeddingDigest')!,
        embeddingDimensions: mapValueOfType<int>(json, r'embeddingDimensions')!,
        ocrWeights: DocumentProcessingWeight.listFromJson(json[r'ocrWeights']).toSet(),
        fingerprint: mapValueOfType<String>(json, r'fingerprint')!,
        manifestRevision: mapValueOfType<int>(json, r'manifestRevision')!,
        extractionRevision: mapValueOfType<String>(json, r'extractionRevision')!,
        chunkingRevision: mapValueOfType<String>(json, r'chunkingRevision')!,
        embeddingInputRevision: mapValueOfType<String>(json, r'embeddingInputRevision')!,
        indexingRevision: mapValueOfType<String>(json, r'indexingRevision')!,
      );
    }
    return null;
  }

  static List<DocumentProcessingConfigurationSnapshot> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfigurationSnapshot>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfigurationSnapshot.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentProcessingConfigurationSnapshot> mapFromJson(dynamic json) {
    final map = <String, DocumentProcessingConfigurationSnapshot>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentProcessingConfigurationSnapshot.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentProcessingConfigurationSnapshot>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentProcessingConfigurationSnapshot>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentProcessingConfigurationSnapshot.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'revision',
    'language',
    'segmentation',
    'ocrEngine',
    'ocrVersion',
    'ocrModel',
    'embeddingModel',
    'embeddingDigest',
    'embeddingDimensions',
    'ocrWeights',
    'fingerprint',
    'manifestRevision',
    'extractionRevision',
    'chunkingRevision',
    'embeddingInputRevision',
    'indexingRevision',
  };
}

enum DocumentProcessingConfigurationSnapshotLanguageEnum {
  eng._(r'eng'),
  deu._(r'deu'),
  engPlusDeu._(r'eng+deu'),
  ;

  const DocumentProcessingConfigurationSnapshotLanguageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingConfigurationSnapshotLanguageEnum? fromJson(dynamic value) => DocumentProcessingConfigurationSnapshotLanguageEnumTypeTransformer().decode(value);

  static List<DocumentProcessingConfigurationSnapshotLanguageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfigurationSnapshotLanguageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfigurationSnapshotLanguageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingConfigurationSnapshotLanguageEnumTypeTransformer {
  factory DocumentProcessingConfigurationSnapshotLanguageEnumTypeTransformer() => _instance ??= const DocumentProcessingConfigurationSnapshotLanguageEnumTypeTransformer._();

  const DocumentProcessingConfigurationSnapshotLanguageEnumTypeTransformer._();

  String encode(DocumentProcessingConfigurationSnapshotLanguageEnum data) => data._value;

  DocumentProcessingConfigurationSnapshotLanguageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingConfigurationSnapshotLanguageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'eng': return DocumentProcessingConfigurationSnapshotLanguageEnum.eng;
        case r'deu': return DocumentProcessingConfigurationSnapshotLanguageEnum.deu;
        case r'eng+deu': return DocumentProcessingConfigurationSnapshotLanguageEnum.engPlusDeu;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingConfigurationSnapshotLanguageEnumTypeTransformer? _instance;
}

enum DocumentProcessingConfigurationSnapshotSegmentationEnum {
  auto._(r'auto'),
  singleBlock._(r'single_block'),
  ;

  const DocumentProcessingConfigurationSnapshotSegmentationEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingConfigurationSnapshotSegmentationEnum? fromJson(dynamic value) => DocumentProcessingConfigurationSnapshotSegmentationEnumTypeTransformer().decode(value);

  static List<DocumentProcessingConfigurationSnapshotSegmentationEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfigurationSnapshotSegmentationEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfigurationSnapshotSegmentationEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingConfigurationSnapshotSegmentationEnumTypeTransformer {
  factory DocumentProcessingConfigurationSnapshotSegmentationEnumTypeTransformer() => _instance ??= const DocumentProcessingConfigurationSnapshotSegmentationEnumTypeTransformer._();

  const DocumentProcessingConfigurationSnapshotSegmentationEnumTypeTransformer._();

  String encode(DocumentProcessingConfigurationSnapshotSegmentationEnum data) => data._value;

  DocumentProcessingConfigurationSnapshotSegmentationEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingConfigurationSnapshotSegmentationEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'auto': return DocumentProcessingConfigurationSnapshotSegmentationEnum.auto;
        case r'single_block': return DocumentProcessingConfigurationSnapshotSegmentationEnum.singleBlock;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingConfigurationSnapshotSegmentationEnumTypeTransformer? _instance;
}
