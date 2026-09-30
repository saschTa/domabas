// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateLLMConfiguration {
  UpdateLLMConfiguration({
    this.propertyThinkingEnabled,
    this.invoiceThinkingEnabled,
    this.lmStudioCompatibility,
    this.contextLength,
    required this.enabled,
    this.invoiceEnabled,
    required this.provider,
    required this.model,
    required this.baseUrl,
    this.apiKey,
    this.clearApiKey = false,
  });

  bool? propertyThinkingEnabled;

  bool? invoiceThinkingEnabled;

  bool? lmStudioCompatibility;

  int? contextLength;

  bool enabled;

  bool? invoiceEnabled;

  UpdateLLMConfigurationProviderEnum provider;

  String model;

  String baseUrl;

  String? apiKey;

  bool clearApiKey;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateLLMConfiguration &&
    other.propertyThinkingEnabled == propertyThinkingEnabled &&
    other.invoiceThinkingEnabled == invoiceThinkingEnabled &&
    other.lmStudioCompatibility == lmStudioCompatibility &&
    other.contextLength == contextLength &&
    other.enabled == enabled &&
    other.invoiceEnabled == invoiceEnabled &&
    other.provider == provider &&
    other.model == model &&
    other.baseUrl == baseUrl &&
    other.apiKey == apiKey &&
    other.clearApiKey == clearApiKey;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (propertyThinkingEnabled == null ? 0 : propertyThinkingEnabled!.hashCode) +
    (invoiceThinkingEnabled == null ? 0 : invoiceThinkingEnabled!.hashCode) +
    (lmStudioCompatibility == null ? 0 : lmStudioCompatibility!.hashCode) +
    (contextLength == null ? 0 : contextLength!.hashCode) +
    (enabled.hashCode) +
    (invoiceEnabled == null ? 0 : invoiceEnabled!.hashCode) +
    (provider.hashCode) +
    (model.hashCode) +
    (baseUrl.hashCode) +
    (apiKey == null ? 0 : apiKey!.hashCode) +
    (clearApiKey.hashCode);

  @override
  String toString() => 'UpdateLLMConfiguration[propertyThinkingEnabled=$propertyThinkingEnabled, invoiceThinkingEnabled=$invoiceThinkingEnabled, lmStudioCompatibility=$lmStudioCompatibility, contextLength=$contextLength, enabled=$enabled, invoiceEnabled=$invoiceEnabled, provider=$provider, model=$model, baseUrl=$baseUrl, apiKey=$apiKey, clearApiKey=$clearApiKey]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.propertyThinkingEnabled != null) {
      json[r'propertyThinkingEnabled'] = this.propertyThinkingEnabled;
    } else {
      json[r'propertyThinkingEnabled'] = null;
    }
    if (this.invoiceThinkingEnabled != null) {
      json[r'invoiceThinkingEnabled'] = this.invoiceThinkingEnabled;
    } else {
      json[r'invoiceThinkingEnabled'] = null;
    }
    if (this.lmStudioCompatibility != null) {
      json[r'lmStudioCompatibility'] = this.lmStudioCompatibility;
    } else {
      json[r'lmStudioCompatibility'] = null;
    }
    if (this.contextLength != null) {
      json[r'contextLength'] = this.contextLength;
    } else {
      json[r'contextLength'] = null;
    }
      json[r'enabled'] = this.enabled;
    if (this.invoiceEnabled != null) {
      json[r'invoiceEnabled'] = this.invoiceEnabled;
    } else {
      json[r'invoiceEnabled'] = null;
    }
      json[r'provider'] = this.provider;
      json[r'model'] = this.model;
      json[r'baseUrl'] = this.baseUrl;
    if (this.apiKey != null) {
      json[r'apiKey'] = this.apiKey;
    } else {
      json[r'apiKey'] = null;
    }
      json[r'clearApiKey'] = this.clearApiKey;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateLLMConfiguration? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'enabled'), 'Required key "UpdateLLMConfiguration[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "UpdateLLMConfiguration[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'provider'), 'Required key "UpdateLLMConfiguration[provider]" is missing from JSON.');
        assert(json[r'provider'] != null, 'Required key "UpdateLLMConfiguration[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'), 'Required key "UpdateLLMConfiguration[model]" is missing from JSON.');
        assert(json[r'model'] != null, 'Required key "UpdateLLMConfiguration[model]" has a null value in JSON.');
        assert(json.containsKey(r'baseUrl'), 'Required key "UpdateLLMConfiguration[baseUrl]" is missing from JSON.');
        assert(json[r'baseUrl'] != null, 'Required key "UpdateLLMConfiguration[baseUrl]" has a null value in JSON.');
        return true;
      }());

      return UpdateLLMConfiguration(
        propertyThinkingEnabled: mapValueOfType<bool>(json, r'propertyThinkingEnabled'),
        invoiceThinkingEnabled: mapValueOfType<bool>(json, r'invoiceThinkingEnabled'),
        lmStudioCompatibility: mapValueOfType<bool>(json, r'lmStudioCompatibility'),
        contextLength: mapValueOfType<int>(json, r'contextLength'),
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        invoiceEnabled: mapValueOfType<bool>(json, r'invoiceEnabled'),
        provider: UpdateLLMConfigurationProviderEnum.fromJson(json[r'provider'])!,
        model: mapValueOfType<String>(json, r'model')!,
        baseUrl: mapValueOfType<String>(json, r'baseUrl')!,
        apiKey: mapValueOfType<String>(json, r'apiKey'),
        clearApiKey: mapValueOfType<bool>(json, r'clearApiKey') ?? false,
      );
    }
    return null;
  }

  static List<UpdateLLMConfiguration> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateLLMConfiguration>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateLLMConfiguration.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateLLMConfiguration> mapFromJson(dynamic json) {
    final map = <String, UpdateLLMConfiguration>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateLLMConfiguration.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateLLMConfiguration>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateLLMConfiguration>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateLLMConfiguration.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'enabled',
    'provider',
    'model',
    'baseUrl',
  };
}

enum UpdateLLMConfigurationProviderEnum {
  ollama._(r'ollama'),
  openai._(r'openai'),
  ;

  const UpdateLLMConfigurationProviderEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static UpdateLLMConfigurationProviderEnum? fromJson(dynamic value) => UpdateLLMConfigurationProviderEnumTypeTransformer().decode(value);

  static List<UpdateLLMConfigurationProviderEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateLLMConfigurationProviderEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateLLMConfigurationProviderEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class UpdateLLMConfigurationProviderEnumTypeTransformer {
  factory UpdateLLMConfigurationProviderEnumTypeTransformer() => _instance ??= const UpdateLLMConfigurationProviderEnumTypeTransformer._();

  const UpdateLLMConfigurationProviderEnumTypeTransformer._();

  String encode(UpdateLLMConfigurationProviderEnum data) => data._value;

  UpdateLLMConfigurationProviderEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is UpdateLLMConfigurationProviderEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ollama': return UpdateLLMConfigurationProviderEnum.ollama;
        case r'openai': return UpdateLLMConfigurationProviderEnum.openai;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static UpdateLLMConfigurationProviderEnumTypeTransformer? _instance;
}
