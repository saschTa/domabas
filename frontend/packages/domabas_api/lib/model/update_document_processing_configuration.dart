// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateDocumentProcessingConfiguration {
  UpdateDocumentProcessingConfiguration({
    this.llm,
    required this.language,
    required this.segmentation,
    this.expectedRevision,
  });

  UpdateLLMConfiguration? llm;

  UpdateDocumentProcessingConfigurationLanguageEnum language;

  UpdateDocumentProcessingConfigurationSegmentationEnum segmentation;

  int? expectedRevision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateDocumentProcessingConfiguration &&
    other.llm == llm &&
    other.language == language &&
    other.segmentation == segmentation &&
    other.expectedRevision == expectedRevision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (llm == null ? 0 : llm!.hashCode) +
    (language.hashCode) +
    (segmentation.hashCode) +
    (expectedRevision == null ? 0 : expectedRevision!.hashCode);

  @override
  String toString() => 'UpdateDocumentProcessingConfiguration[llm=$llm, language=$language, segmentation=$segmentation, expectedRevision=$expectedRevision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.llm != null) {
      json[r'llm'] = this.llm;
    } else {
      json[r'llm'] = null;
    }
      json[r'language'] = this.language;
      json[r'segmentation'] = this.segmentation;
    if (this.expectedRevision != null) {
      json[r'expectedRevision'] = this.expectedRevision;
    } else {
      json[r'expectedRevision'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateDocumentProcessingConfiguration? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'language'), 'Required key "UpdateDocumentProcessingConfiguration[language]" is missing from JSON.');
        assert(json[r'language'] != null, 'Required key "UpdateDocumentProcessingConfiguration[language]" has a null value in JSON.');
        assert(json.containsKey(r'segmentation'), 'Required key "UpdateDocumentProcessingConfiguration[segmentation]" is missing from JSON.');
        assert(json[r'segmentation'] != null, 'Required key "UpdateDocumentProcessingConfiguration[segmentation]" has a null value in JSON.');
        return true;
      }());

      return UpdateDocumentProcessingConfiguration(
        llm: UpdateLLMConfiguration.fromJson(json[r'llm']),
        language: UpdateDocumentProcessingConfigurationLanguageEnum.fromJson(json[r'language'])!,
        segmentation: UpdateDocumentProcessingConfigurationSegmentationEnum.fromJson(json[r'segmentation'])!,
        expectedRevision: mapValueOfType<int>(json, r'expectedRevision'),
      );
    }
    return null;
  }

  static List<UpdateDocumentProcessingConfiguration> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateDocumentProcessingConfiguration>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateDocumentProcessingConfiguration.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateDocumentProcessingConfiguration> mapFromJson(dynamic json) {
    final map = <String, UpdateDocumentProcessingConfiguration>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateDocumentProcessingConfiguration.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateDocumentProcessingConfiguration>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateDocumentProcessingConfiguration>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateDocumentProcessingConfiguration.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'language',
    'segmentation',
  };
}

enum UpdateDocumentProcessingConfigurationLanguageEnum {
  eng._(r'eng'),
  deu._(r'deu'),
  engPlusDeu._(r'eng+deu'),
  ;

  const UpdateDocumentProcessingConfigurationLanguageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static UpdateDocumentProcessingConfigurationLanguageEnum? fromJson(dynamic value) => UpdateDocumentProcessingConfigurationLanguageEnumTypeTransformer().decode(value);

  static List<UpdateDocumentProcessingConfigurationLanguageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateDocumentProcessingConfigurationLanguageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateDocumentProcessingConfigurationLanguageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class UpdateDocumentProcessingConfigurationLanguageEnumTypeTransformer {
  factory UpdateDocumentProcessingConfigurationLanguageEnumTypeTransformer() => _instance ??= const UpdateDocumentProcessingConfigurationLanguageEnumTypeTransformer._();

  const UpdateDocumentProcessingConfigurationLanguageEnumTypeTransformer._();

  String encode(UpdateDocumentProcessingConfigurationLanguageEnum data) => data._value;

  UpdateDocumentProcessingConfigurationLanguageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is UpdateDocumentProcessingConfigurationLanguageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'eng': return UpdateDocumentProcessingConfigurationLanguageEnum.eng;
        case r'deu': return UpdateDocumentProcessingConfigurationLanguageEnum.deu;
        case r'eng+deu': return UpdateDocumentProcessingConfigurationLanguageEnum.engPlusDeu;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static UpdateDocumentProcessingConfigurationLanguageEnumTypeTransformer? _instance;
}

enum UpdateDocumentProcessingConfigurationSegmentationEnum {
  auto._(r'auto'),
  singleBlock._(r'single_block'),
  ;

  const UpdateDocumentProcessingConfigurationSegmentationEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static UpdateDocumentProcessingConfigurationSegmentationEnum? fromJson(dynamic value) => UpdateDocumentProcessingConfigurationSegmentationEnumTypeTransformer().decode(value);

  static List<UpdateDocumentProcessingConfigurationSegmentationEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateDocumentProcessingConfigurationSegmentationEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateDocumentProcessingConfigurationSegmentationEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class UpdateDocumentProcessingConfigurationSegmentationEnumTypeTransformer {
  factory UpdateDocumentProcessingConfigurationSegmentationEnumTypeTransformer() => _instance ??= const UpdateDocumentProcessingConfigurationSegmentationEnumTypeTransformer._();

  const UpdateDocumentProcessingConfigurationSegmentationEnumTypeTransformer._();

  String encode(UpdateDocumentProcessingConfigurationSegmentationEnum data) => data._value;

  UpdateDocumentProcessingConfigurationSegmentationEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is UpdateDocumentProcessingConfigurationSegmentationEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'auto': return UpdateDocumentProcessingConfigurationSegmentationEnum.auto;
        case r'single_block': return UpdateDocumentProcessingConfigurationSegmentationEnum.singleBlock;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static UpdateDocumentProcessingConfigurationSegmentationEnumTypeTransformer? _instance;
}
