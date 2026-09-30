// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentProcessingPipeline {
  DocumentProcessingPipeline({
    this.scheduling,
    required this.configuration,
    required this.ready,
    this.languages = const [],
    this.segmentations = const [],
  });

  DocumentProcessingScheduling? scheduling;

  DocumentProcessingConfigurationSnapshot configuration;

  bool ready;

  List<DocumentProcessingPipelineLanguagesEnum> languages;

  List<DocumentProcessingPipelineSegmentationsEnum> segmentations;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentProcessingPipeline &&
    other.scheduling == scheduling &&
    other.configuration == configuration &&
    other.ready == ready &&
    _deepEquality.equals(other.languages, languages) &&
    _deepEquality.equals(other.segmentations, segmentations);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (scheduling == null ? 0 : scheduling!.hashCode) +
    (configuration.hashCode) +
    (ready.hashCode) +
    (languages.hashCode) +
    (segmentations.hashCode);

  @override
  String toString() => 'DocumentProcessingPipeline[scheduling=$scheduling, configuration=$configuration, ready=$ready, languages=$languages, segmentations=$segmentations]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.scheduling != null) {
      json[r'scheduling'] = this.scheduling;
    } else {
      json[r'scheduling'] = null;
    }
      json[r'configuration'] = this.configuration;
      json[r'ready'] = this.ready;
      json[r'languages'] = this.languages;
      json[r'segmentations'] = this.segmentations;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentProcessingPipeline? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'configuration'), 'Required key "DocumentProcessingPipeline[configuration]" is missing from JSON.');
        assert(json[r'configuration'] != null, 'Required key "DocumentProcessingPipeline[configuration]" has a null value in JSON.');
        assert(json.containsKey(r'ready'), 'Required key "DocumentProcessingPipeline[ready]" is missing from JSON.');
        assert(json[r'ready'] != null, 'Required key "DocumentProcessingPipeline[ready]" has a null value in JSON.');
        assert(json.containsKey(r'languages'), 'Required key "DocumentProcessingPipeline[languages]" is missing from JSON.');
        assert(json[r'languages'] != null, 'Required key "DocumentProcessingPipeline[languages]" has a null value in JSON.');
        assert(json.containsKey(r'segmentations'), 'Required key "DocumentProcessingPipeline[segmentations]" is missing from JSON.');
        assert(json[r'segmentations'] != null, 'Required key "DocumentProcessingPipeline[segmentations]" has a null value in JSON.');
        return true;
      }());

      return DocumentProcessingPipeline(
        scheduling: DocumentProcessingScheduling.fromJson(json[r'scheduling']),
        configuration: DocumentProcessingConfigurationSnapshot.fromJson(json[r'configuration'])!,
        ready: mapValueOfType<bool>(json, r'ready')!,
        languages: DocumentProcessingPipelineLanguagesEnum.listFromJson(json[r'languages']),
        segmentations: DocumentProcessingPipelineSegmentationsEnum.listFromJson(json[r'segmentations']),
      );
    }
    return null;
  }

  static List<DocumentProcessingPipeline> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingPipeline>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingPipeline.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentProcessingPipeline> mapFromJson(dynamic json) {
    final map = <String, DocumentProcessingPipeline>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentProcessingPipeline.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentProcessingPipeline>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentProcessingPipeline>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentProcessingPipeline.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'configuration',
    'ready',
    'languages',
    'segmentations',
  };
}

enum DocumentProcessingPipelineLanguagesEnum {
  eng._(r'eng'),
  deu._(r'deu'),
  engPlusDeu._(r'eng+deu'),
  ;

  const DocumentProcessingPipelineLanguagesEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingPipelineLanguagesEnum? fromJson(dynamic value) => DocumentProcessingPipelineLanguagesEnumTypeTransformer().decode(value);

  static List<DocumentProcessingPipelineLanguagesEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingPipelineLanguagesEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingPipelineLanguagesEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingPipelineLanguagesEnumTypeTransformer {
  factory DocumentProcessingPipelineLanguagesEnumTypeTransformer() => _instance ??= const DocumentProcessingPipelineLanguagesEnumTypeTransformer._();

  const DocumentProcessingPipelineLanguagesEnumTypeTransformer._();

  String encode(DocumentProcessingPipelineLanguagesEnum data) => data._value;

  DocumentProcessingPipelineLanguagesEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingPipelineLanguagesEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'eng': return DocumentProcessingPipelineLanguagesEnum.eng;
        case r'deu': return DocumentProcessingPipelineLanguagesEnum.deu;
        case r'eng+deu': return DocumentProcessingPipelineLanguagesEnum.engPlusDeu;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingPipelineLanguagesEnumTypeTransformer? _instance;
}

enum DocumentProcessingPipelineSegmentationsEnum {
  auto._(r'auto'),
  singleBlock._(r'single_block'),
  ;

  const DocumentProcessingPipelineSegmentationsEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingPipelineSegmentationsEnum? fromJson(dynamic value) => DocumentProcessingPipelineSegmentationsEnumTypeTransformer().decode(value);

  static List<DocumentProcessingPipelineSegmentationsEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingPipelineSegmentationsEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingPipelineSegmentationsEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingPipelineSegmentationsEnumTypeTransformer {
  factory DocumentProcessingPipelineSegmentationsEnumTypeTransformer() => _instance ??= const DocumentProcessingPipelineSegmentationsEnumTypeTransformer._();

  const DocumentProcessingPipelineSegmentationsEnumTypeTransformer._();

  String encode(DocumentProcessingPipelineSegmentationsEnum data) => data._value;

  DocumentProcessingPipelineSegmentationsEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingPipelineSegmentationsEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'auto': return DocumentProcessingPipelineSegmentationsEnum.auto;
        case r'single_block': return DocumentProcessingPipelineSegmentationsEnum.singleBlock;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingPipelineSegmentationsEnumTypeTransformer? _instance;
}
