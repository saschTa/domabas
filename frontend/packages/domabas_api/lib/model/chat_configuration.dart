// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatConfiguration {
  ChatConfiguration({
    this.thinkingEnabled = false,
    required this.contextLength,
    required this.enabled,
    required this.provider,
    required this.model,
    required this.revision,
    required this.baseUrl,
    required this.hasApiKey,
  });

  bool thinkingEnabled;

  int contextLength;

  bool enabled;

  ChatConfigurationProviderEnum provider;

  String model;

  int revision;

  String baseUrl;

  bool hasApiKey;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatConfiguration &&
    other.thinkingEnabled == thinkingEnabled &&
    other.contextLength == contextLength &&
    other.enabled == enabled &&
    other.provider == provider &&
    other.model == model &&
    other.revision == revision &&
    other.baseUrl == baseUrl &&
    other.hasApiKey == hasApiKey;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (thinkingEnabled.hashCode) +
    (contextLength.hashCode) +
    (enabled.hashCode) +
    (provider.hashCode) +
    (model.hashCode) +
    (revision.hashCode) +
    (baseUrl.hashCode) +
    (hasApiKey.hashCode);

  @override
  String toString() => 'ChatConfiguration[thinkingEnabled=$thinkingEnabled, contextLength=$contextLength, enabled=$enabled, provider=$provider, model=$model, revision=$revision, baseUrl=$baseUrl, hasApiKey=$hasApiKey]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'thinkingEnabled'] = this.thinkingEnabled;
      json[r'contextLength'] = this.contextLength;
      json[r'enabled'] = this.enabled;
      json[r'provider'] = this.provider;
      json[r'model'] = this.model;
      json[r'revision'] = this.revision;
      json[r'baseUrl'] = this.baseUrl;
      json[r'hasApiKey'] = this.hasApiKey;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatConfiguration? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'contextLength'), 'Required key "ChatConfiguration[contextLength]" is missing from JSON.');
        assert(json[r'contextLength'] != null, 'Required key "ChatConfiguration[contextLength]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "ChatConfiguration[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "ChatConfiguration[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'provider'), 'Required key "ChatConfiguration[provider]" is missing from JSON.');
        assert(json[r'provider'] != null, 'Required key "ChatConfiguration[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'), 'Required key "ChatConfiguration[model]" is missing from JSON.');
        assert(json[r'model'] != null, 'Required key "ChatConfiguration[model]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "ChatConfiguration[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "ChatConfiguration[revision]" has a null value in JSON.');
        assert(json.containsKey(r'baseUrl'), 'Required key "ChatConfiguration[baseUrl]" is missing from JSON.');
        assert(json[r'baseUrl'] != null, 'Required key "ChatConfiguration[baseUrl]" has a null value in JSON.');
        assert(json.containsKey(r'hasApiKey'), 'Required key "ChatConfiguration[hasApiKey]" is missing from JSON.');
        assert(json[r'hasApiKey'] != null, 'Required key "ChatConfiguration[hasApiKey]" has a null value in JSON.');
        return true;
      }());

      return ChatConfiguration(
        thinkingEnabled: mapValueOfType<bool>(json, r'thinkingEnabled') ?? false,
        contextLength: mapValueOfType<int>(json, r'contextLength')!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        provider: ChatConfigurationProviderEnum.fromJson(json[r'provider'])!,
        model: mapValueOfType<String>(json, r'model')!,
        revision: mapValueOfType<int>(json, r'revision')!,
        baseUrl: mapValueOfType<String>(json, r'baseUrl')!,
        hasApiKey: mapValueOfType<bool>(json, r'hasApiKey')!,
      );
    }
    return null;
  }

  static List<ChatConfiguration> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatConfiguration>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatConfiguration.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatConfiguration> mapFromJson(dynamic json) {
    final map = <String, ChatConfiguration>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatConfiguration.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatConfiguration>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatConfiguration>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatConfiguration.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'contextLength',
    'enabled',
    'provider',
    'model',
    'revision',
    'baseUrl',
    'hasApiKey',
  };
}

enum ChatConfigurationProviderEnum {
  ollama._(r'ollama'),
  openai._(r'openai'),
  ;

  const ChatConfigurationProviderEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static ChatConfigurationProviderEnum? fromJson(dynamic value) => ChatConfigurationProviderEnumTypeTransformer().decode(value);

  static List<ChatConfigurationProviderEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatConfigurationProviderEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatConfigurationProviderEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class ChatConfigurationProviderEnumTypeTransformer {
  factory ChatConfigurationProviderEnumTypeTransformer() => _instance ??= const ChatConfigurationProviderEnumTypeTransformer._();

  const ChatConfigurationProviderEnumTypeTransformer._();

  String encode(ChatConfigurationProviderEnum data) => data._value;

  ChatConfigurationProviderEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ChatConfigurationProviderEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ollama': return ChatConfigurationProviderEnum.ollama;
        case r'openai': return ChatConfigurationProviderEnum.openai;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static ChatConfigurationProviderEnumTypeTransformer? _instance;
}
