// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentProcessingScheduling {
  DocumentProcessingScheduling({
    required this.ingestionConcurrency,
    required this.aiConcurrency,
    required this.ollamaQueueSize,
    required this.ingestionConcurrencyMode,
    required this.aiConcurrencyMode,
    required this.providerStepRetries,
    required this.priorityPolicy,
  });

  int ingestionConcurrency;

  int aiConcurrency;

  int ollamaQueueSize;

  DocumentProcessingSchedulingIngestionConcurrencyModeEnum ingestionConcurrencyMode;

  DocumentProcessingSchedulingAiConcurrencyModeEnum aiConcurrencyMode;

  int providerStepRetries;

  DocumentProcessingSchedulingPriorityPolicyEnum priorityPolicy;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentProcessingScheduling &&
    other.ingestionConcurrency == ingestionConcurrency &&
    other.aiConcurrency == aiConcurrency &&
    other.ollamaQueueSize == ollamaQueueSize &&
    other.ingestionConcurrencyMode == ingestionConcurrencyMode &&
    other.aiConcurrencyMode == aiConcurrencyMode &&
    other.providerStepRetries == providerStepRetries &&
    other.priorityPolicy == priorityPolicy;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (ingestionConcurrency.hashCode) +
    (aiConcurrency.hashCode) +
    (ollamaQueueSize.hashCode) +
    (ingestionConcurrencyMode.hashCode) +
    (aiConcurrencyMode.hashCode) +
    (providerStepRetries.hashCode) +
    (priorityPolicy.hashCode);

  @override
  String toString() => 'DocumentProcessingScheduling[ingestionConcurrency=$ingestionConcurrency, aiConcurrency=$aiConcurrency, ollamaQueueSize=$ollamaQueueSize, ingestionConcurrencyMode=$ingestionConcurrencyMode, aiConcurrencyMode=$aiConcurrencyMode, providerStepRetries=$providerStepRetries, priorityPolicy=$priorityPolicy]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'ingestionConcurrency'] = this.ingestionConcurrency;
      json[r'aiConcurrency'] = this.aiConcurrency;
      json[r'ollamaQueueSize'] = this.ollamaQueueSize;
      json[r'ingestionConcurrencyMode'] = this.ingestionConcurrencyMode;
      json[r'aiConcurrencyMode'] = this.aiConcurrencyMode;
      json[r'providerStepRetries'] = this.providerStepRetries;
      json[r'priorityPolicy'] = this.priorityPolicy;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentProcessingScheduling? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'ingestionConcurrency'), 'Required key "DocumentProcessingScheduling[ingestionConcurrency]" is missing from JSON.');
        assert(json[r'ingestionConcurrency'] != null, 'Required key "DocumentProcessingScheduling[ingestionConcurrency]" has a null value in JSON.');
        assert(json.containsKey(r'aiConcurrency'), 'Required key "DocumentProcessingScheduling[aiConcurrency]" is missing from JSON.');
        assert(json[r'aiConcurrency'] != null, 'Required key "DocumentProcessingScheduling[aiConcurrency]" has a null value in JSON.');
        assert(json.containsKey(r'ollamaQueueSize'), 'Required key "DocumentProcessingScheduling[ollamaQueueSize]" is missing from JSON.');
        assert(json[r'ollamaQueueSize'] != null, 'Required key "DocumentProcessingScheduling[ollamaQueueSize]" has a null value in JSON.');
        assert(json.containsKey(r'ingestionConcurrencyMode'), 'Required key "DocumentProcessingScheduling[ingestionConcurrencyMode]" is missing from JSON.');
        assert(json[r'ingestionConcurrencyMode'] != null, 'Required key "DocumentProcessingScheduling[ingestionConcurrencyMode]" has a null value in JSON.');
        assert(json.containsKey(r'aiConcurrencyMode'), 'Required key "DocumentProcessingScheduling[aiConcurrencyMode]" is missing from JSON.');
        assert(json[r'aiConcurrencyMode'] != null, 'Required key "DocumentProcessingScheduling[aiConcurrencyMode]" has a null value in JSON.');
        assert(json.containsKey(r'providerStepRetries'), 'Required key "DocumentProcessingScheduling[providerStepRetries]" is missing from JSON.');
        assert(json[r'providerStepRetries'] != null, 'Required key "DocumentProcessingScheduling[providerStepRetries]" has a null value in JSON.');
        assert(json.containsKey(r'priorityPolicy'), 'Required key "DocumentProcessingScheduling[priorityPolicy]" is missing from JSON.');
        assert(json[r'priorityPolicy'] != null, 'Required key "DocumentProcessingScheduling[priorityPolicy]" has a null value in JSON.');
        return true;
      }());

      return DocumentProcessingScheduling(
        ingestionConcurrency: mapValueOfType<int>(json, r'ingestionConcurrency')!,
        aiConcurrency: mapValueOfType<int>(json, r'aiConcurrency')!,
        ollamaQueueSize: mapValueOfType<int>(json, r'ollamaQueueSize')!,
        ingestionConcurrencyMode: DocumentProcessingSchedulingIngestionConcurrencyModeEnum.fromJson(json[r'ingestionConcurrencyMode'])!,
        aiConcurrencyMode: DocumentProcessingSchedulingAiConcurrencyModeEnum.fromJson(json[r'aiConcurrencyMode'])!,
        providerStepRetries: mapValueOfType<int>(json, r'providerStepRetries')!,
        priorityPolicy: DocumentProcessingSchedulingPriorityPolicyEnum.fromJson(json[r'priorityPolicy'])!,
      );
    }
    return null;
  }

  static List<DocumentProcessingScheduling> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingScheduling>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingScheduling.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentProcessingScheduling> mapFromJson(dynamic json) {
    final map = <String, DocumentProcessingScheduling>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentProcessingScheduling.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentProcessingScheduling>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentProcessingScheduling>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentProcessingScheduling.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'ingestionConcurrency',
    'aiConcurrency',
    'ollamaQueueSize',
    'ingestionConcurrencyMode',
    'aiConcurrencyMode',
    'providerStepRetries',
    'priorityPolicy',
  };
}

enum DocumentProcessingSchedulingIngestionConcurrencyModeEnum {
  fixed._(r'fixed'),
  ollamaHalfQueue._(r'ollama_half_queue'),
  ;

  const DocumentProcessingSchedulingIngestionConcurrencyModeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingSchedulingIngestionConcurrencyModeEnum? fromJson(dynamic value) => DocumentProcessingSchedulingIngestionConcurrencyModeEnumTypeTransformer().decode(value);

  static List<DocumentProcessingSchedulingIngestionConcurrencyModeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingSchedulingIngestionConcurrencyModeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingSchedulingIngestionConcurrencyModeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingSchedulingIngestionConcurrencyModeEnumTypeTransformer {
  factory DocumentProcessingSchedulingIngestionConcurrencyModeEnumTypeTransformer() => _instance ??= const DocumentProcessingSchedulingIngestionConcurrencyModeEnumTypeTransformer._();

  const DocumentProcessingSchedulingIngestionConcurrencyModeEnumTypeTransformer._();

  String encode(DocumentProcessingSchedulingIngestionConcurrencyModeEnum data) => data._value;

  DocumentProcessingSchedulingIngestionConcurrencyModeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingSchedulingIngestionConcurrencyModeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'fixed': return DocumentProcessingSchedulingIngestionConcurrencyModeEnum.fixed;
        case r'ollama_half_queue': return DocumentProcessingSchedulingIngestionConcurrencyModeEnum.ollamaHalfQueue;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingSchedulingIngestionConcurrencyModeEnumTypeTransformer? _instance;
}

enum DocumentProcessingSchedulingAiConcurrencyModeEnum {
  fixed._(r'fixed'),
  ollamaHalfQueue._(r'ollama_half_queue'),
  ;

  const DocumentProcessingSchedulingAiConcurrencyModeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingSchedulingAiConcurrencyModeEnum? fromJson(dynamic value) => DocumentProcessingSchedulingAiConcurrencyModeEnumTypeTransformer().decode(value);

  static List<DocumentProcessingSchedulingAiConcurrencyModeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingSchedulingAiConcurrencyModeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingSchedulingAiConcurrencyModeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingSchedulingAiConcurrencyModeEnumTypeTransformer {
  factory DocumentProcessingSchedulingAiConcurrencyModeEnumTypeTransformer() => _instance ??= const DocumentProcessingSchedulingAiConcurrencyModeEnumTypeTransformer._();

  const DocumentProcessingSchedulingAiConcurrencyModeEnumTypeTransformer._();

  String encode(DocumentProcessingSchedulingAiConcurrencyModeEnum data) => data._value;

  DocumentProcessingSchedulingAiConcurrencyModeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingSchedulingAiConcurrencyModeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'fixed': return DocumentProcessingSchedulingAiConcurrencyModeEnum.fixed;
        case r'ollama_half_queue': return DocumentProcessingSchedulingAiConcurrencyModeEnum.ollamaHalfQueue;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingSchedulingAiConcurrencyModeEnumTypeTransformer? _instance;
}

enum DocumentProcessingSchedulingPriorityPolicyEnum {
  ingestionFirst._(r'ingestion_first'),
  ;

  const DocumentProcessingSchedulingPriorityPolicyEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentProcessingSchedulingPriorityPolicyEnum? fromJson(dynamic value) => DocumentProcessingSchedulingPriorityPolicyEnumTypeTransformer().decode(value);

  static List<DocumentProcessingSchedulingPriorityPolicyEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentProcessingSchedulingPriorityPolicyEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentProcessingSchedulingPriorityPolicyEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentProcessingSchedulingPriorityPolicyEnumTypeTransformer {
  factory DocumentProcessingSchedulingPriorityPolicyEnumTypeTransformer() => _instance ??= const DocumentProcessingSchedulingPriorityPolicyEnumTypeTransformer._();

  const DocumentProcessingSchedulingPriorityPolicyEnumTypeTransformer._();

  String encode(DocumentProcessingSchedulingPriorityPolicyEnum data) => data._value;

  DocumentProcessingSchedulingPriorityPolicyEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentProcessingSchedulingPriorityPolicyEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ingestion_first': return DocumentProcessingSchedulingPriorityPolicyEnum.ingestionFirst;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentProcessingSchedulingPriorityPolicyEnumTypeTransformer? _instance;
}
