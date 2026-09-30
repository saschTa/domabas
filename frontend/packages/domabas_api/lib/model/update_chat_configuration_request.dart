// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class UpdateChatConfigurationRequest {
  UpdateChatConfigurationRequest({
    this.thinkingEnabled,
    this.contextLength,
    required this.expectedRevision,
    required this.enabled,
    required this.provider,
    required this.model,
    required this.baseUrl,
    this.apiKey,
    this.clearApiKey,
  });

  bool? thinkingEnabled;

  int? contextLength;

  int expectedRevision;

  bool enabled;

  UpdateChatConfigurationRequestProviderEnum provider;

  String model;

  String baseUrl;

  String? apiKey;

  bool? clearApiKey;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateChatConfigurationRequest &&
    other.thinkingEnabled == thinkingEnabled &&
    other.contextLength == contextLength &&
    other.expectedRevision == expectedRevision &&
    other.enabled == enabled &&
    other.provider == provider &&
    other.model == model &&
    other.baseUrl == baseUrl &&
    other.apiKey == apiKey &&
    other.clearApiKey == clearApiKey;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (thinkingEnabled == null ? 0 : thinkingEnabled!.hashCode) +
    (contextLength == null ? 0 : contextLength!.hashCode) +
    (expectedRevision.hashCode) +
    (enabled.hashCode) +
    (provider.hashCode) +
    (model.hashCode) +
    (baseUrl.hashCode) +
    (apiKey == null ? 0 : apiKey!.hashCode) +
    (clearApiKey == null ? 0 : clearApiKey!.hashCode);

  @override
  String toString() => 'UpdateChatConfigurationRequest[thinkingEnabled=$thinkingEnabled, contextLength=$contextLength, expectedRevision=$expectedRevision, enabled=$enabled, provider=$provider, model=$model, baseUrl=$baseUrl, apiKey=$apiKey, clearApiKey=$clearApiKey]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.thinkingEnabled != null) {
      json[r'thinkingEnabled'] = this.thinkingEnabled;
    } else {
      json[r'thinkingEnabled'] = null;
    }
    if (this.contextLength != null) {
      json[r'contextLength'] = this.contextLength;
    } else {
      json[r'contextLength'] = null;
    }
      json[r'expectedRevision'] = this.expectedRevision;
      json[r'enabled'] = this.enabled;
      json[r'provider'] = this.provider;
      json[r'model'] = this.model;
      json[r'baseUrl'] = this.baseUrl;
    if (this.apiKey != null) {
      json[r'apiKey'] = this.apiKey;
    } else {
      json[r'apiKey'] = null;
    }
    if (this.clearApiKey != null) {
      json[r'clearApiKey'] = this.clearApiKey;
    } else {
      json[r'clearApiKey'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static UpdateChatConfigurationRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'expectedRevision'), 'Required key "UpdateChatConfigurationRequest[expectedRevision]" is missing from JSON.');
        assert(json[r'expectedRevision'] != null, 'Required key "UpdateChatConfigurationRequest[expectedRevision]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "UpdateChatConfigurationRequest[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "UpdateChatConfigurationRequest[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'provider'), 'Required key "UpdateChatConfigurationRequest[provider]" is missing from JSON.');
        assert(json[r'provider'] != null, 'Required key "UpdateChatConfigurationRequest[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'), 'Required key "UpdateChatConfigurationRequest[model]" is missing from JSON.');
        assert(json[r'model'] != null, 'Required key "UpdateChatConfigurationRequest[model]" has a null value in JSON.');
        assert(json.containsKey(r'baseUrl'), 'Required key "UpdateChatConfigurationRequest[baseUrl]" is missing from JSON.');
        assert(json[r'baseUrl'] != null, 'Required key "UpdateChatConfigurationRequest[baseUrl]" has a null value in JSON.');
        return true;
      }());

      return UpdateChatConfigurationRequest(
        thinkingEnabled: mapValueOfType<bool>(json, r'thinkingEnabled'),
        contextLength: mapValueOfType<int>(json, r'contextLength'),
        expectedRevision: mapValueOfType<int>(json, r'expectedRevision')!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        provider: UpdateChatConfigurationRequestProviderEnum.fromJson(json[r'provider'])!,
        model: mapValueOfType<String>(json, r'model')!,
        baseUrl: mapValueOfType<String>(json, r'baseUrl')!,
        apiKey: mapValueOfType<String>(json, r'apiKey'),
        clearApiKey: mapValueOfType<bool>(json, r'clearApiKey'),
      );
    }
    return null;
  }

  static List<UpdateChatConfigurationRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateChatConfigurationRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateChatConfigurationRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateChatConfigurationRequest> mapFromJson(dynamic json) {
    final map = <String, UpdateChatConfigurationRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateChatConfigurationRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<UpdateChatConfigurationRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UpdateChatConfigurationRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateChatConfigurationRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'expectedRevision',
    'enabled',
    'provider',
    'model',
    'baseUrl',
  };
}

enum UpdateChatConfigurationRequestProviderEnum {
  ollama._(r'ollama'),
  openai._(r'openai'),
  ;

  const UpdateChatConfigurationRequestProviderEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static UpdateChatConfigurationRequestProviderEnum? fromJson(dynamic value) => UpdateChatConfigurationRequestProviderEnumTypeTransformer().decode(value);

  static List<UpdateChatConfigurationRequestProviderEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UpdateChatConfigurationRequestProviderEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateChatConfigurationRequestProviderEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class UpdateChatConfigurationRequestProviderEnumTypeTransformer {
  factory UpdateChatConfigurationRequestProviderEnumTypeTransformer() => _instance ??= const UpdateChatConfigurationRequestProviderEnumTypeTransformer._();

  const UpdateChatConfigurationRequestProviderEnumTypeTransformer._();

  String encode(UpdateChatConfigurationRequestProviderEnum data) => data._value;

  UpdateChatConfigurationRequestProviderEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is UpdateChatConfigurationRequestProviderEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ollama': return UpdateChatConfigurationRequestProviderEnum.ollama;
        case r'openai': return UpdateChatConfigurationRequestProviderEnum.openai;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static UpdateChatConfigurationRequestProviderEnumTypeTransformer? _instance;
}
