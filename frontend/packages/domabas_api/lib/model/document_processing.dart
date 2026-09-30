// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentProcessing {
  DocumentProcessing({
    this.ai,
    required this.state,
    required this.stage,
    required this.generation,
    required this.configurationRevision,
    required this.updatedAt,
    this.failureCode,
    required this.ocrEngine,
    required this.ocrVersion,
    required this.ocrModel,
    required this.ocrLanguage,
    required this.ocrSegmentation,
    required this.embeddingModel,
    required this.embeddingDigest,
    required this.embeddingDimensions,
    required this.extractionMethod,
  });

  DocumentAIProcessing? ai;

  DocumentProcessingStateEnum state;

  DocumentProcessingStageEnum stage;

  int generation;

  int configurationRevision;

  DateTime updatedAt;

  String? failureCode;

  String ocrEngine;

  String ocrVersion;

  String ocrModel;

  DocumentProcessingOcrLanguageEnum ocrLanguage;

  DocumentProcessingOcrSegmentationEnum ocrSegmentation;

  String embeddingModel;

  String embeddingDigest;

  int embeddingDimensions;

  DocumentProcessingExtractionMethodEnum? extractionMethod;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentProcessing &&
    other.ai == ai &&
    other.state == state &&
    other.stage == stage &&
    other.generation == generation &&
    other.configurationRevision == configurationRevision &&
    other.updatedAt == updatedAt &&
    other.failureCode == failureCode &&
    other.ocrEngine == ocrEngine &&
    other.ocrVersion == ocrVersion &&
    other.ocrModel == ocrModel &&
    other.ocrLanguage == ocrLanguage &&
    other.ocrSegmentation == ocrSegmentation &&
    other.embeddingModel == embeddingModel &&
    other.embeddingDigest == embeddingDigest &&
    other.embeddingDimensions == embeddingDimensions &&
    other.extractionMethod == extractionMethod;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (ai == null ? 0 : ai!.hashCode) +
    (state.hashCode) +
    (stage.hashCode) +
    (generation.hashCode) +
    (configurationRevision.hashCode) +
    (updatedAt.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (ocrEngine.hashCode) +
    (ocrVersion.hashCode) +
    (ocrModel.hashCode) +
    (ocrLanguage.hashCode) +
    (ocrSegmentation.hashCode) +
    (embeddingModel.hashCode) +
    (embeddingDigest.hashCode) +
    (embeddingDimensions.hashCode) +
    (extractionMethod == null ? 0 : extractionMethod!.hashCode);

  @override
  String toString() => 'DocumentProcessing[ai=$ai, state=$state, stage=$stage, generation=$generation, configurationRevision=$configurationRevision, updatedAt=$updatedAt, failureCode=$failureCode, ocrEngine=$ocrEngine, ocrVersion=$ocrVersion, ocrModel=$ocrModel, ocrLanguage=$ocrLanguage, ocrSegmentation=$ocrSegmentation, embeddingModel=$embeddingModel, embeddingDigest=$embeddingDigest, embeddingDimensions=$embeddingDimensions, extractionMethod=$extractionMethod]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.ai != null) {
      json[r'ai'] = this.ai;
    } else {
      json[r'ai'] = null;
    }
      json[r'state'] = this.state;
      json[r'stage'] = this.stage;
      json[r'generation'] = this.generation;
      json[r'configurationRevision'] = this.configurationRevision;
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
      json[r'ocrEngine'] = this.ocrEngine;
      json[r'ocrVersion'] = this.ocrVersion;
      json[r'ocrModel'] = this.ocrModel;
      json[r'ocrLanguage'] = this.ocrLanguage;
      json[r'ocrSegmentation'] = this.ocrSegmentation;
      json[r'embeddingModel'] = this.embeddingModel;
      json[r'embeddingDigest'] = this.embeddingDigest;
      json[r'embeddingDimensions'] = this.embeddingDimensions;
    if (this.extractionMethod != null) {
      json[r'extractionMethod'] = this.extractionMethod;
    } else {
      json[r'extractionMethod'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentProcessing? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'state'), 'Required key "DocumentProcessing[state]" is missing from JSON.');
        assert(json[r'state'] != null, 'Required key "DocumentProcessing[state]" has a null value in JSON.');
        assert(json.containsKey(r'stage'), 'Required key "DocumentProcessing[stage]" is missing from JSON.');
        assert(json[r'stage'] != null, 'Required key "DocumentProcessing[stage]" has a null value in JSON.');
        assert(json.containsKey(r'generation'), 'Required key "DocumentProcessing[generation]" is missing from JSON.');
        assert(json[r'generation'] != null, 'Required key "DocumentProcessing[generation]" has a null value in JSON.');
        assert(json.containsKey(r'configurationRevision'), 'Required key "DocumentProcessing[configurationRevision]" is missing from JSON.');
        assert(json[r'configurationRevision'] != null, 'Required key "DocumentProcessing[configurationRevision]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "DocumentProcessing[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "DocumentProcessing[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'ocrEngine'), 'Required key "DocumentProcessing[ocrEngine]" is missing from JSON.');
        assert(json[r'ocrEngine'] != null, 'Required key "DocumentProcessing[ocrEngine]" has a null value in JSON.');
        assert(json.containsKey(r'ocrVersion'), 'Required key "DocumentProcessing[ocrVersion]" is missing from JSON.');
        assert(json[r'ocrVersion'] != null, 'Required key "DocumentProcessing[ocrVersion]" has a null value in JSON.');
        assert(json.containsKey(r'ocrModel'), 'Required key "DocumentProcessing[ocrModel]" is missing from JSON.');
        assert(json[r'ocrModel'] != null, 'Required key "DocumentProcessing[ocrModel]" has a null value in JSON.');
        assert(json.containsKey(r'ocrLanguage'), 'Required key "DocumentProcessing[ocrLanguage]" is missing from JSON.');
        assert(json[r'ocrLanguage'] != null, 'Required key "DocumentProcessing[ocrLanguage]" has a null value in JSON.');
        assert(json.containsKey(r'ocrSegmentation'), 'Required key "DocumentProcessing[ocrSegmentation]" is missing from JSON.');
        assert(json[r'ocrSegmentation'] != null, 'Required key "DocumentProcessing[ocrSegmentation]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingModel'), 'Required key "DocumentProcessing[embeddingModel]" is missing from JSON.');
        assert(json[r'embeddingModel'] != null, 'Required key "DocumentProcessing[embeddingModel]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingDigest'), 'Required key "DocumentProcessing[embeddingDigest]" is missing from JSON.');
        assert(json[r'embeddingDigest'] != null, 'Required key "DocumentProcessing[embeddingDigest]" has a null value in JSON.');
        assert(json.containsKey(r'embeddingDimensions'), 'Required key "DocumentProcessing[embeddingDimensions]" is missing from JSON.');
        assert(json[r'embeddingDimensions'] != null, 'Required key "DocumentProcessing[embeddingDimensions]" has a null value in JSON.');
        assert(json.containsKey(r'extractionMethod'), 'Required key "DocumentProcessing[extractionMethod]" is missing from JSON.');
        return true;
      }());

      return DocumentProcessing(
        ai: DocumentAIProcessing.fromJson(json[r'ai']),
        state: DocumentProcessingStateEnum.fromJson(json[r'state'])!,
        stage: DocumentProcessingStageEnum.fromJson(json[r'stage'])!,
        generation: mapValueOfType<int>(json, r'generation')!,
        configurationRevision: mapValueOfType<int>(json, r'configurationRevision')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        ocrEngine: mapValueOfType<String>(json, r'ocrEngine')!,
        ocrVersion: mapValueOfType<String>(json, r'ocrVersion')!,
        ocrModel: mapValueOfType<String>(json, r'ocrModel')!,
        ocrLanguage: DocumentProcessingOcrLanguageEnum.fromJson(json[r'ocrLanguage'])!,
        ocrSegmentation: DocumentProcessingOcrSegmentationEnum.fromJson(json[r'ocrSegmentation'])!,
        embeddingModel: mapValueOfType<String>(json, r'embeddingModel')!,
        embeddingDigest: mapValueOfType<String>(json, r'embeddingDigest')!,
        embeddingDimensions: mapValueOfType<int>(json, r'embeddingDimensions')!,
        extractionMethod: DocumentProcessingExtractionMethodEnum.fromJson(json[r'extractionMethod']),
      );
    }
    return null;
  }

  static List<DocumentProcessing> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessing>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessing.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentProcessing> mapFromJson(dynamic json) {
    final map = <String, DocumentProcessing>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentProcessing.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentProcessing>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentProcessing>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentProcessing.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'state',
    'stage',
    'generation',
    'configurationRevision',
    'updatedAt',
    'ocrEngine',
    'ocrVersion',
    'ocrModel',
    'ocrLanguage',
    'ocrSegmentation',
    'embeddingModel',
    'embeddingDigest',
    'embeddingDimensions',
    'extractionMethod',
  };
}

enum DocumentProcessingStateEnum {
  queued._(r'queued'),
  processing._(r'processing'),
  ready._(r'ready'),
  failed._(r'failed'),
  ;

  const DocumentProcessingStateEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingStateEnum? fromJson(dynamic value) => DocumentProcessingStateEnumTypeTransformer().decode(value);

  static List<DocumentProcessingStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingStateEnumTypeTransformer {
  factory DocumentProcessingStateEnumTypeTransformer() => _instance ??= const DocumentProcessingStateEnumTypeTransformer._();

  const DocumentProcessingStateEnumTypeTransformer._();

  String encode(DocumentProcessingStateEnum data) => data._value;

  DocumentProcessingStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return DocumentProcessingStateEnum.queued;
        case r'processing': return DocumentProcessingStateEnum.processing;
        case r'ready': return DocumentProcessingStateEnum.ready;
        case r'failed': return DocumentProcessingStateEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingStateEnumTypeTransformer? _instance;
}

enum DocumentProcessingStageEnum {
  queued._(r'queued'),
  extracting._(r'extracting'),
  enriching._(r'enriching'),
  invoicing._(r'invoicing'),
  embedding._(r'embedding'),
  finalizing._(r'finalizing'),
  complete._(r'complete'),
  failed._(r'failed'),
  ;

  const DocumentProcessingStageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingStageEnum? fromJson(dynamic value) => DocumentProcessingStageEnumTypeTransformer().decode(value);

  static List<DocumentProcessingStageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingStageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingStageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingStageEnumTypeTransformer {
  factory DocumentProcessingStageEnumTypeTransformer() => _instance ??= const DocumentProcessingStageEnumTypeTransformer._();

  const DocumentProcessingStageEnumTypeTransformer._();

  String encode(DocumentProcessingStageEnum data) => data._value;

  DocumentProcessingStageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingStageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return DocumentProcessingStageEnum.queued;
        case r'extracting': return DocumentProcessingStageEnum.extracting;
        case r'enriching': return DocumentProcessingStageEnum.enriching;
        case r'invoicing': return DocumentProcessingStageEnum.invoicing;
        case r'embedding': return DocumentProcessingStageEnum.embedding;
        case r'finalizing': return DocumentProcessingStageEnum.finalizing;
        case r'complete': return DocumentProcessingStageEnum.complete;
        case r'failed': return DocumentProcessingStageEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingStageEnumTypeTransformer? _instance;
}

enum DocumentProcessingOcrLanguageEnum {
  eng._(r'eng'),
  deu._(r'deu'),
  engPlusDeu._(r'eng+deu'),
  ;

  const DocumentProcessingOcrLanguageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingOcrLanguageEnum? fromJson(dynamic value) => DocumentProcessingOcrLanguageEnumTypeTransformer().decode(value);

  static List<DocumentProcessingOcrLanguageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingOcrLanguageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingOcrLanguageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingOcrLanguageEnumTypeTransformer {
  factory DocumentProcessingOcrLanguageEnumTypeTransformer() => _instance ??= const DocumentProcessingOcrLanguageEnumTypeTransformer._();

  const DocumentProcessingOcrLanguageEnumTypeTransformer._();

  String encode(DocumentProcessingOcrLanguageEnum data) => data._value;

  DocumentProcessingOcrLanguageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingOcrLanguageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'eng': return DocumentProcessingOcrLanguageEnum.eng;
        case r'deu': return DocumentProcessingOcrLanguageEnum.deu;
        case r'eng+deu': return DocumentProcessingOcrLanguageEnum.engPlusDeu;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingOcrLanguageEnumTypeTransformer? _instance;
}

enum DocumentProcessingOcrSegmentationEnum {
  auto._(r'auto'),
  singleBlock._(r'single_block'),
  ;

  const DocumentProcessingOcrSegmentationEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingOcrSegmentationEnum? fromJson(dynamic value) => DocumentProcessingOcrSegmentationEnumTypeTransformer().decode(value);

  static List<DocumentProcessingOcrSegmentationEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingOcrSegmentationEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingOcrSegmentationEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingOcrSegmentationEnumTypeTransformer {
  factory DocumentProcessingOcrSegmentationEnumTypeTransformer() => _instance ??= const DocumentProcessingOcrSegmentationEnumTypeTransformer._();

  const DocumentProcessingOcrSegmentationEnumTypeTransformer._();

  String encode(DocumentProcessingOcrSegmentationEnum data) => data._value;

  DocumentProcessingOcrSegmentationEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingOcrSegmentationEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'auto': return DocumentProcessingOcrSegmentationEnum.auto;
        case r'single_block': return DocumentProcessingOcrSegmentationEnum.singleBlock;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingOcrSegmentationEnumTypeTransformer? _instance;
}

enum DocumentProcessingExtractionMethodEnum {
  ocr._(r'ocr'),
  mime._(r'mime'),
  ;

  const DocumentProcessingExtractionMethodEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingExtractionMethodEnum? fromJson(dynamic value) => DocumentProcessingExtractionMethodEnumTypeTransformer().decode(value);

  static List<DocumentProcessingExtractionMethodEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingExtractionMethodEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingExtractionMethodEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingExtractionMethodEnumTypeTransformer {
  factory DocumentProcessingExtractionMethodEnumTypeTransformer() => _instance ??= const DocumentProcessingExtractionMethodEnumTypeTransformer._();

  const DocumentProcessingExtractionMethodEnumTypeTransformer._();

  String encode(DocumentProcessingExtractionMethodEnum data) => data._value;

  DocumentProcessingExtractionMethodEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingExtractionMethodEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ocr': return DocumentProcessingExtractionMethodEnum.ocr;
        case r'mime': return DocumentProcessingExtractionMethodEnum.mime;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingExtractionMethodEnumTypeTransformer? _instance;
}
