// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentProcessingConfiguration {
  DocumentProcessingConfiguration({
    this.scheduling,
    this.llm,
    required this.revision,
    required this.language,
    required this.segmentation,
    required this.ocrEngine,
    required this.ocrVersion,
    required this.ocrModel,
    required this.embeddingModel,
    required this.embeddingDigest,
    required this.embeddingDimensions,
    required this.ready,
    this.languages = const [],
    this.segmentations = const [],
    this.ocrWeights = const {},
    required this.fingerprint,
    required this.manifestRevision,
    required this.extractionRevision,
    required this.chunkingRevision,
    required this.embeddingInputRevision,
    required this.indexingRevision,
    required this.dashboardUrl,
    required this.automaticBatchId,
  });

  DocumentProcessingScheduling? scheduling;

  LLMConfiguration? llm;

  int revision;

  DocumentProcessingConfigurationLanguageEnum language;

  DocumentProcessingConfigurationSegmentationEnum segmentation;

  String ocrEngine;

  String ocrVersion;

  String ocrModel;

  String embeddingModel;

  String embeddingDigest;

  int embeddingDimensions;

  bool ready;

  List<DocumentProcessingConfigurationLanguagesEnum> languages;

  List<DocumentProcessingConfigurationSegmentationsEnum> segmentations;

  Set<DocumentProcessingWeight> ocrWeights;

  String fingerprint;

  int manifestRevision;

  String extractionRevision;

  String chunkingRevision;

  String embeddingInputRevision;

  String indexingRevision;

  String? dashboardUrl;

  String? automaticBatchId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentProcessingConfiguration &&
    other.scheduling == scheduling &&
    other.llm == llm &&
    other.revision == revision &&
    other.language == language &&
    other.segmentation == segmentation &&
    other.ocrEngine == ocrEngine &&
    other.ocrVersion == ocrVersion &&
    other.ocrModel == ocrModel &&
    other.embeddingModel == embeddingModel &&
    other.embeddingDigest == embeddingDigest &&
    other.embeddingDimensions == embeddingDimensions &&
    other.ready == ready &&
    _deepEquality.equals(other.languages, languages) &&
    _deepEquality.equals(other.segmentations, segmentations) &&
    _deepEquality.equals(other.ocrWeights, ocrWeights) &&
    other.fingerprint == fingerprint &&
    other.manifestRevision == manifestRevision &&
    other.extractionRevision == extractionRevision &&
    other.chunkingRevision == chunkingRevision &&
    other.embeddingInputRevision == embeddingInputRevision &&
    other.indexingRevision == indexingRevision &&
    other.dashboardUrl == dashboardUrl &&
    other.automaticBatchId == automaticBatchId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (scheduling == null ? 0 : scheduling!.hashCode) +
    (llm == null ? 0 : llm!.hashCode) +
    (revision.hashCode) +
    (language.hashCode) +
    (segmentation.hashCode) +
    (ocrEngine.hashCode) +
    (ocrVersion.hashCode) +
    (ocrModel.hashCode) +
    (embeddingModel.hashCode) +
    (embeddingDigest.hashCode) +
    (embeddingDimensions.hashCode) +
    (ready.hashCode) +
    (languages.hashCode) +
    (segmentations.hashCode) +
    (ocrWeights.hashCode) +
    (fingerprint.hashCode) +
    (manifestRevision.hashCode) +
    (extractionRevision.hashCode) +
    (chunkingRevision.hashCode) +
    (embeddingInputRevision.hashCode) +
    (indexingRevision.hashCode) +
    (dashboardUrl == null ? 0 : dashboardUrl!.hashCode) +
    (automaticBatchId == null ? 0 : automaticBatchId!.hashCode);

  @override
  String toString() => 'DocumentProcessingConfiguration[scheduling=$scheduling, llm=$llm, revision=$revision, language=$language, segmentation=$segmentation, ocrEngine=$ocrEngine, ocrVersion=$ocrVersion, ocrModel=$ocrModel, embeddingModel=$embeddingModel, embeddingDigest=$embeddingDigest, embeddingDimensions=$embeddingDimensions, ready=$ready, languages=$languages, segmentations=$segmentations, ocrWeights=$ocrWeights, fingerprint=$fingerprint, manifestRevision=$manifestRevision, extractionRevision=$extractionRevision, chunkingRevision=$chunkingRevision, embeddingInputRevision=$embeddingInputRevision, indexingRevision=$indexingRevision, dashboardUrl=$dashboardUrl, automaticBatchId=$automaticBatchId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.scheduling != null) {
      json[r'scheduling'] = this.scheduling;
    } else {
      json[r'scheduling'] = null;
    }
    if (this.llm != null) {
      json[r'llm'] = this.llm;
    } else {
      json[r'llm'] = null;
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
      json[r'ready'] = this.ready;
      json[r'languages'] = this.languages;
      json[r'segmentations'] = this.segmentations;
      json[r'ocrWeights'] = this.ocrWeights.toList(growable: false);
      json[r'fingerprint'] = this.fingerprint;
      json[r'manifestRevision'] = this.manifestRevision;
      json[r'extractionRevision'] = this.extractionRevision;
      json[r'chunkingRevision'] = this.chunkingRevision;
      json[r'embeddingInputRevision'] = this.embeddingInputRevision;
      json[r'indexingRevision'] = this.indexingRevision;
    if (this.dashboardUrl != null) {
      json[r'dashboardUrl'] = this.dashboardUrl;
    } else {
      json[r'dashboardUrl'] = null;
    }
    if (this.automaticBatchId != null) {
      json[r'automaticBatchId'] = this.automaticBatchId;
    } else {
      json[r'automaticBatchId'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentProcessingConfiguration? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'revision'), 'Required key "DocumentProcessingConfiguration[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "DocumentProcessingConfiguration[revision]" has a null value in JSON.');
        assert(json.containsKey(r'language'), 'Required key "DocumentProcessingConfiguration[language]" is missing from JSON.');
        assert(json[r'language'] != null, 'Required key "DocumentProcessingConfiguration[language]" has a null value in JSON.');
        assert(json.containsKey(r'segmentation'), 'Required key "DocumentProcessingConfiguration[segmentation]" is missing from JSON.');
        assert(json[r'segmentation'] != null, 'Required key "DocumentProcessingConfiguration[segmentation]" has a null value in JSON.');
        assert(json.containsKey(r'ocrEngine'), 'Required key "DocumentProcessingConfiguration[ocrEngine]" is missing from JSON.');
        assert(json[r'ocrEngine'] != null, 'Required key "DocumentProcessingConfiguration[ocrEngine]" has a null value in JSON.');
        assert(json.containsKey(r'ocrVersion'), 'Required key "DocumentProcessingConfiguration[ocrVersion]" is missing from JSON.');
        assert(json[r'ocrVersion'] != null, 'Required key "DocumentProcessingConfiguration[ocrVersion]" has a null value in JSON.');
        assert(json.containsKey(r'ocrModel'), 'Required key "DocumentProcessingConfiguration[ocrModel]" is missing from JSON.');
        assert(json[r'ocrModel'] != null, 'Required key "DocumentProcessingConfiguration[ocrModel]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingModel'), 'Required key "DocumentProcessingConfiguration[embeddingModel]" is missing from JSON.');
        assert(json[r'embeddingModel'] != null, 'Required key "DocumentProcessingConfiguration[embeddingModel]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingDigest'), 'Required key "DocumentProcessingConfiguration[embeddingDigest]" is missing from JSON.');
        assert(json[r'embeddingDigest'] != null, 'Required key "DocumentProcessingConfiguration[embeddingDigest]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingDimensions'), 'Required key "DocumentProcessingConfiguration[embeddingDimensions]" is missing from JSON.');
        assert(json[r'embeddingDimensions'] != null, 'Required key "DocumentProcessingConfiguration[embeddingDimensions]" has a null value in JSON.');
        assert(json.containsKey(r'ready'), 'Required key "DocumentProcessingConfiguration[ready]" is missing from JSON.');
        assert(json[r'ready'] != null, 'Required key "DocumentProcessingConfiguration[ready]" has a null value in JSON.');
        assert(json.containsKey(r'languages'), 'Required key "DocumentProcessingConfiguration[languages]" is missing from JSON.');
        assert(json[r'languages'] != null, 'Required key "DocumentProcessingConfiguration[languages]" has a null value in JSON.');
        assert(json.containsKey(r'segmentations'), 'Required key "DocumentProcessingConfiguration[segmentations]" is missing from JSON.');
        assert(json[r'segmentations'] != null, 'Required key "DocumentProcessingConfiguration[segmentations]" has a null value in JSON.');
        assert(json.containsKey(r'ocrWeights'), 'Required key "DocumentProcessingConfiguration[ocrWeights]" is missing from JSON.');
        assert(json[r'ocrWeights'] != null, 'Required key "DocumentProcessingConfiguration[ocrWeights]" has a null value in JSON.');
        assert(json.containsKey(r'fingerprint'), 'Required key "DocumentProcessingConfiguration[fingerprint]" is missing from JSON.');
        assert(json[r'fingerprint'] != null, 'Required key "DocumentProcessingConfiguration[fingerprint]" has a null value in JSON.');
        assert(json.containsKey(r'manifestRevision'), 'Required key "DocumentProcessingConfiguration[manifestRevision]" is missing from JSON.');
        assert(json[r'manifestRevision'] != null, 'Required key "DocumentProcessingConfiguration[manifestRevision]" has a null value in JSON.');
        assert(json.containsKey(r'extractionRevision'), 'Required key "DocumentProcessingConfiguration[extractionRevision]" is missing from JSON.');
        assert(json[r'extractionRevision'] != null, 'Required key "DocumentProcessingConfiguration[extractionRevision]" has a null value in JSON.');
        assert(json.containsKey(r'chunkingRevision'), 'Required key "DocumentProcessingConfiguration[chunkingRevision]" is missing from JSON.');
        assert(json[r'chunkingRevision'] != null, 'Required key "DocumentProcessingConfiguration[chunkingRevision]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingInputRevision'), 'Required key "DocumentProcessingConfiguration[embeddingInputRevision]" is missing from JSON.');
        assert(json[r'embeddingInputRevision'] != null, 'Required key "DocumentProcessingConfiguration[embeddingInputRevision]" has a null value in JSON.');
        assert(json.containsKey(r'indexingRevision'), 'Required key "DocumentProcessingConfiguration[indexingRevision]" is missing from JSON.');
        assert(json[r'indexingRevision'] != null, 'Required key "DocumentProcessingConfiguration[indexingRevision]" has a null value in JSON.');
        assert(json.containsKey(r'dashboardUrl'), 'Required key "DocumentProcessingConfiguration[dashboardUrl]" is missing from JSON.');
        assert(json.containsKey(r'automaticBatchId'), 'Required key "DocumentProcessingConfiguration[automaticBatchId]" is missing from JSON.');
        return true;
      }());

      return DocumentProcessingConfiguration(
        scheduling: DocumentProcessingScheduling.fromJson(json[r'scheduling']),
        llm: LLMConfiguration.fromJson(json[r'llm']),
        revision: mapValueOfType<int>(json, r'revision')!,
        language: DocumentProcessingConfigurationLanguageEnum.fromJson(json[r'language'])!,
        segmentation: DocumentProcessingConfigurationSegmentationEnum.fromJson(json[r'segmentation'])!,
        ocrEngine: mapValueOfType<String>(json, r'ocrEngine')!,
        ocrVersion: mapValueOfType<String>(json, r'ocrVersion')!,
        ocrModel: mapValueOfType<String>(json, r'ocrModel')!,
        embeddingModel: mapValueOfType<String>(json, r'embeddingModel')!,
        embeddingDigest: mapValueOfType<String>(json, r'embeddingDigest')!,
        embeddingDimensions: mapValueOfType<int>(json, r'embeddingDimensions')!,
        ready: mapValueOfType<bool>(json, r'ready')!,
        languages: DocumentProcessingConfigurationLanguagesEnum.listFromJson(json[r'languages']),
        segmentations: DocumentProcessingConfigurationSegmentationsEnum.listFromJson(json[r'segmentations']),
        ocrWeights: DocumentProcessingWeight.listFromJson(json[r'ocrWeights']).toSet(),
        fingerprint: mapValueOfType<String>(json, r'fingerprint')!,
        manifestRevision: mapValueOfType<int>(json, r'manifestRevision')!,
        extractionRevision: mapValueOfType<String>(json, r'extractionRevision')!,
        chunkingRevision: mapValueOfType<String>(json, r'chunkingRevision')!,
        embeddingInputRevision: mapValueOfType<String>(json, r'embeddingInputRevision')!,
        indexingRevision: mapValueOfType<String>(json, r'indexingRevision')!,
        dashboardUrl: mapValueOfType<String>(json, r'dashboardUrl'),
        automaticBatchId: mapValueOfType<String>(json, r'automaticBatchId'),
      );
    }
    return null;
  }

  static List<DocumentProcessingConfiguration> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfiguration>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfiguration.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentProcessingConfiguration> mapFromJson(dynamic json) {
    final map = <String, DocumentProcessingConfiguration>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentProcessingConfiguration.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentProcessingConfiguration>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentProcessingConfiguration>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentProcessingConfiguration.listFromJson(entry.value, growable: growable,);
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
    'ready',
    'languages',
    'segmentations',
    'ocrWeights',
    'fingerprint',
    'manifestRevision',
    'extractionRevision',
    'chunkingRevision',
    'embeddingInputRevision',
    'indexingRevision',
    'dashboardUrl',
    'automaticBatchId',
  };
}

enum DocumentProcessingConfigurationLanguageEnum {
  eng._(r'eng'),
  deu._(r'deu'),
  engPlusDeu._(r'eng+deu'),
  ;

  const DocumentProcessingConfigurationLanguageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingConfigurationLanguageEnum? fromJson(dynamic value) => DocumentProcessingConfigurationLanguageEnumTypeTransformer().decode(value);

  static List<DocumentProcessingConfigurationLanguageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfigurationLanguageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfigurationLanguageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingConfigurationLanguageEnumTypeTransformer {
  factory DocumentProcessingConfigurationLanguageEnumTypeTransformer() => _instance ??= const DocumentProcessingConfigurationLanguageEnumTypeTransformer._();

  const DocumentProcessingConfigurationLanguageEnumTypeTransformer._();

  String encode(DocumentProcessingConfigurationLanguageEnum data) => data._value;

  DocumentProcessingConfigurationLanguageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingConfigurationLanguageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'eng': return DocumentProcessingConfigurationLanguageEnum.eng;
        case r'deu': return DocumentProcessingConfigurationLanguageEnum.deu;
        case r'eng+deu': return DocumentProcessingConfigurationLanguageEnum.engPlusDeu;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingConfigurationLanguageEnumTypeTransformer? _instance;
}

enum DocumentProcessingConfigurationSegmentationEnum {
  auto._(r'auto'),
  singleBlock._(r'single_block'),
  ;

  const DocumentProcessingConfigurationSegmentationEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingConfigurationSegmentationEnum? fromJson(dynamic value) => DocumentProcessingConfigurationSegmentationEnumTypeTransformer().decode(value);

  static List<DocumentProcessingConfigurationSegmentationEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfigurationSegmentationEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfigurationSegmentationEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingConfigurationSegmentationEnumTypeTransformer {
  factory DocumentProcessingConfigurationSegmentationEnumTypeTransformer() => _instance ??= const DocumentProcessingConfigurationSegmentationEnumTypeTransformer._();

  const DocumentProcessingConfigurationSegmentationEnumTypeTransformer._();

  String encode(DocumentProcessingConfigurationSegmentationEnum data) => data._value;

  DocumentProcessingConfigurationSegmentationEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingConfigurationSegmentationEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'auto': return DocumentProcessingConfigurationSegmentationEnum.auto;
        case r'single_block': return DocumentProcessingConfigurationSegmentationEnum.singleBlock;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingConfigurationSegmentationEnumTypeTransformer? _instance;
}

enum DocumentProcessingConfigurationLanguagesEnum {
  eng._(r'eng'),
  deu._(r'deu'),
  engPlusDeu._(r'eng+deu'),
  ;

  const DocumentProcessingConfigurationLanguagesEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingConfigurationLanguagesEnum? fromJson(dynamic value) => DocumentProcessingConfigurationLanguagesEnumTypeTransformer().decode(value);

  static List<DocumentProcessingConfigurationLanguagesEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfigurationLanguagesEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfigurationLanguagesEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingConfigurationLanguagesEnumTypeTransformer {
  factory DocumentProcessingConfigurationLanguagesEnumTypeTransformer() => _instance ??= const DocumentProcessingConfigurationLanguagesEnumTypeTransformer._();

  const DocumentProcessingConfigurationLanguagesEnumTypeTransformer._();

  String encode(DocumentProcessingConfigurationLanguagesEnum data) => data._value;

  DocumentProcessingConfigurationLanguagesEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingConfigurationLanguagesEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'eng': return DocumentProcessingConfigurationLanguagesEnum.eng;
        case r'deu': return DocumentProcessingConfigurationLanguagesEnum.deu;
        case r'eng+deu': return DocumentProcessingConfigurationLanguagesEnum.engPlusDeu;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingConfigurationLanguagesEnumTypeTransformer? _instance;
}

enum DocumentProcessingConfigurationSegmentationsEnum {
  auto._(r'auto'),
  singleBlock._(r'single_block'),
  ;

  const DocumentProcessingConfigurationSegmentationsEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingConfigurationSegmentationsEnum? fromJson(dynamic value) => DocumentProcessingConfigurationSegmentationsEnumTypeTransformer().decode(value);

  static List<DocumentProcessingConfigurationSegmentationsEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingConfigurationSegmentationsEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingConfigurationSegmentationsEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingConfigurationSegmentationsEnumTypeTransformer {
  factory DocumentProcessingConfigurationSegmentationsEnumTypeTransformer() => _instance ??= const DocumentProcessingConfigurationSegmentationsEnumTypeTransformer._();

  const DocumentProcessingConfigurationSegmentationsEnumTypeTransformer._();

  String encode(DocumentProcessingConfigurationSegmentationsEnum data) => data._value;

  DocumentProcessingConfigurationSegmentationsEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingConfigurationSegmentationsEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'auto': return DocumentProcessingConfigurationSegmentationsEnum.auto;
        case r'single_block': return DocumentProcessingConfigurationSegmentationsEnum.singleBlock;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingConfigurationSegmentationsEnumTypeTransformer? _instance;
}
