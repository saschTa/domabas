// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class LLMConfiguration {
  LLMConfiguration({
    this.propertyThinkingEnabled = false,
    this.invoiceThinkingEnabled = false,
    required this.contextLength,
    required this.enabled,
    required this.invoiceEnabled,
    required this.provider,
    required this.model,
    required this.baseUrl,
    required this.credentialConfigured,
    this.lmStudioCompatibility = false,
  });

  bool propertyThinkingEnabled;

  bool invoiceThinkingEnabled;

  int contextLength;

  bool enabled;

  bool invoiceEnabled;

  LLMConfigurationProviderEnum provider;

  String model;

  String baseUrl;

  bool credentialConfigured;

  bool lmStudioCompatibility;

  @override
  bool operator ==(Object other) => identical(this, other) || other is LLMConfiguration &&
    other.propertyThinkingEnabled == propertyThinkingEnabled &&
    other.invoiceThinkingEnabled == invoiceThinkingEnabled &&
    other.contextLength == contextLength &&
    other.enabled == enabled &&
    other.invoiceEnabled == invoiceEnabled &&
    other.provider == provider &&
    other.model == model &&
    other.baseUrl == baseUrl &&
    other.credentialConfigured == credentialConfigured &&
    other.lmStudioCompatibility == lmStudioCompatibility;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (propertyThinkingEnabled.hashCode) +
    (invoiceThinkingEnabled.hashCode) +
    (contextLength.hashCode) +
    (enabled.hashCode) +
    (invoiceEnabled.hashCode) +
    (provider.hashCode) +
    (model.hashCode) +
    (baseUrl.hashCode) +
    (credentialConfigured.hashCode) +
    (lmStudioCompatibility.hashCode);

  @override
  String toString() => 'LLMConfiguration[propertyThinkingEnabled=$propertyThinkingEnabled, invoiceThinkingEnabled=$invoiceThinkingEnabled, contextLength=$contextLength, enabled=$enabled, invoiceEnabled=$invoiceEnabled, provider=$provider, model=$model, baseUrl=$baseUrl, credentialConfigured=$credentialConfigured, lmStudioCompatibility=$lmStudioCompatibility]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'propertyThinkingEnabled'] = this.propertyThinkingEnabled;
      json[r'invoiceThinkingEnabled'] = this.invoiceThinkingEnabled;
      json[r'contextLength'] = this.contextLength;
      json[r'enabled'] = this.enabled;
      json[r'invoiceEnabled'] = this.invoiceEnabled;
      json[r'provider'] = this.provider;
      json[r'model'] = this.model;
      json[r'baseUrl'] = this.baseUrl;
      json[r'credentialConfigured'] = this.credentialConfigured;
      json[r'lmStudioCompatibility'] = this.lmStudioCompatibility;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static LLMConfiguration? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'contextLength'), 'Required key "LLMConfiguration[contextLength]" is missing from JSON.');
        assert(json[r'contextLength'] != null, 'Required key "LLMConfiguration[contextLength]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "LLMConfiguration[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "LLMConfiguration[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'invoiceEnabled'), 'Required key "LLMConfiguration[invoiceEnabled]" is missing from JSON.');
        assert(json[r'invoiceEnabled'] != null, 'Required key "LLMConfiguration[invoiceEnabled]" has a null value in JSON.');
        assert(json.containsKey(r'provider'), 'Required key "LLMConfiguration[provider]" is missing from JSON.');
        assert(json[r'provider'] != null, 'Required key "LLMConfiguration[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'), 'Required key "LLMConfiguration[model]" is missing from JSON.');
        assert(json[r'model'] != null, 'Required key "LLMConfiguration[model]" has a null value in JSON.');
        assert(json.containsKey(r'baseUrl'), 'Required key "LLMConfiguration[baseUrl]" is missing from JSON.');
        assert(json[r'baseUrl'] != null, 'Required key "LLMConfiguration[baseUrl]" has a null value in JSON.');
        assert(json.containsKey(r'credentialConfigured'), 'Required key "LLMConfiguration[credentialConfigured]" is missing from JSON.');
        assert(json[r'credentialConfigured'] != null, 'Required key "LLMConfiguration[credentialConfigured]" has a null value in JSON.');
        return true;
      }());

      return LLMConfiguration(
        propertyThinkingEnabled: mapValueOfType<bool>(json, r'propertyThinkingEnabled') ?? false,
        invoiceThinkingEnabled: mapValueOfType<bool>(json, r'invoiceThinkingEnabled') ?? false,
        contextLength: mapValueOfType<int>(json, r'contextLength')!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        invoiceEnabled: mapValueOfType<bool>(json, r'invoiceEnabled')!,
        provider: LLMConfigurationProviderEnum.fromJson(json[r'provider'])!,
        model: mapValueOfType<String>(json, r'model')!,
        baseUrl: mapValueOfType<String>(json, r'baseUrl')!,
        credentialConfigured: mapValueOfType<bool>(json, r'credentialConfigured')!,
        lmStudioCompatibility: mapValueOfType<bool>(json, r'lmStudioCompatibility') ?? false,
      );
    }
    return null;
  }

  static List<LLMConfiguration> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LLMConfiguration>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LLMConfiguration.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, LLMConfiguration> mapFromJson(dynamic json) {
    final map = <String, LLMConfiguration>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = LLMConfiguration.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<LLMConfiguration>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<LLMConfiguration>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = LLMConfiguration.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'contextLength',
    'enabled',
    'invoiceEnabled',
    'provider',
    'model',
    'baseUrl',
    'credentialConfigured',
  };
}

enum LLMConfigurationProviderEnum {
  ollama._(r'ollama'),
  openai._(r'openai'),
  ;

  const LLMConfigurationProviderEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static LLMConfigurationProviderEnum? fromJson(dynamic value) => LLMConfigurationProviderEnumTypeTransformer().decode(value);

  static List<LLMConfigurationProviderEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LLMConfigurationProviderEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LLMConfigurationProviderEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class LLMConfigurationProviderEnumTypeTransformer {
  factory LLMConfigurationProviderEnumTypeTransformer() => _instance ??= const LLMConfigurationProviderEnumTypeTransformer._();

  const LLMConfigurationProviderEnumTypeTransformer._();

  String encode(LLMConfigurationProviderEnum data) => data._value;

  LLMConfigurationProviderEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is LLMConfigurationProviderEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ollama': return LLMConfigurationProviderEnum.ollama;
        case r'openai': return LLMConfigurationProviderEnum.openai;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static LLMConfigurationProviderEnumTypeTransformer? _instance;
}
