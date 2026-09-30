// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatConfigurationSummary {
  ChatConfigurationSummary({
    required this.enabled,
    required this.provider,
    required this.model,
    required this.revision,
  });

  bool enabled;

  ChatConfigurationSummaryProviderEnum provider;

  String model;

  int revision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatConfigurationSummary &&
    other.enabled == enabled &&
    other.provider == provider &&
    other.model == model &&
    other.revision == revision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (enabled.hashCode) +
    (provider.hashCode) +
    (model.hashCode) +
    (revision.hashCode);

  @override
  String toString() => 'ChatConfigurationSummary[enabled=$enabled, provider=$provider, model=$model, revision=$revision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'enabled'] = this.enabled;
      json[r'provider'] = this.provider;
      json[r'model'] = this.model;
      json[r'revision'] = this.revision;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatConfigurationSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'enabled'), 'Required key "ChatConfigurationSummary[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "ChatConfigurationSummary[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'provider'), 'Required key "ChatConfigurationSummary[provider]" is missing from JSON.');
        assert(json[r'provider'] != null, 'Required key "ChatConfigurationSummary[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'), 'Required key "ChatConfigurationSummary[model]" is missing from JSON.');
        assert(json[r'model'] != null, 'Required key "ChatConfigurationSummary[model]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "ChatConfigurationSummary[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "ChatConfigurationSummary[revision]" has a null value in JSON.');
        return true;
      }());

      return ChatConfigurationSummary(
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        provider: ChatConfigurationSummaryProviderEnum.fromJson(json[r'provider'])!,
        model: mapValueOfType<String>(json, r'model')!,
        revision: mapValueOfType<int>(json, r'revision')!,
      );
    }
    return null;
  }

  static List<ChatConfigurationSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatConfigurationSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatConfigurationSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatConfigurationSummary> mapFromJson(dynamic json) {
    final map = <String, ChatConfigurationSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatConfigurationSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatConfigurationSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatConfigurationSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatConfigurationSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'enabled',
    'provider',
    'model',
    'revision',
  };
}

enum ChatConfigurationSummaryProviderEnum {
  ollama._(r'ollama'),
  openai._(r'openai'),
  ;

  const ChatConfigurationSummaryProviderEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static ChatConfigurationSummaryProviderEnum? fromJson(dynamic value) => ChatConfigurationSummaryProviderEnumTypeTransformer().decode(value);

  static List<ChatConfigurationSummaryProviderEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatConfigurationSummaryProviderEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatConfigurationSummaryProviderEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class ChatConfigurationSummaryProviderEnumTypeTransformer {
  factory ChatConfigurationSummaryProviderEnumTypeTransformer() => _instance ??= const ChatConfigurationSummaryProviderEnumTypeTransformer._();

  const ChatConfigurationSummaryProviderEnumTypeTransformer._();

  String encode(ChatConfigurationSummaryProviderEnum data) => data._value;

  ChatConfigurationSummaryProviderEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ChatConfigurationSummaryProviderEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ollama': return ChatConfigurationSummaryProviderEnum.ollama;
        case r'openai': return ChatConfigurationSummaryProviderEnum.openai;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static ChatConfigurationSummaryProviderEnumTypeTransformer? _instance;
}
