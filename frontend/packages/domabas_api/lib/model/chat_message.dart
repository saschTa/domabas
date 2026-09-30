// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sequence,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.turnId,
    required this.status,
    required this.stage,
    this.failureCode,
    required this.provider,
    required this.model,
    this.sources = const [],
  });

  String id;

  String conversationId;

  int sequence;

  ChatMessageRoleEnum role;

  String content;

  DateTime createdAt;

  DateTime updatedAt;

  String turnId;

  ChatMessageStatusEnum status;

  ChatMessageStageEnum stage;

  String? failureCode;

  ChatMessageProviderEnum provider;

  String model;

  List<ChatSource> sources;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatMessage &&
    other.id == id &&
    other.conversationId == conversationId &&
    other.sequence == sequence &&
    other.role == role &&
    other.content == content &&
    other.createdAt == createdAt &&
    other.updatedAt == updatedAt &&
    other.turnId == turnId &&
    other.status == status &&
    other.stage == stage &&
    other.failureCode == failureCode &&
    other.provider == provider &&
    other.model == model &&
    _deepEquality.equals(other.sources, sources);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (conversationId.hashCode) +
    (sequence.hashCode) +
    (role.hashCode) +
    (content.hashCode) +
    (createdAt.hashCode) +
    (updatedAt.hashCode) +
    (turnId.hashCode) +
    (status.hashCode) +
    (stage.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (provider.hashCode) +
    (model.hashCode) +
    (sources.hashCode);

  @override
  String toString() => 'ChatMessage[id=$id, conversationId=$conversationId, sequence=$sequence, role=$role, content=$content, createdAt=$createdAt, updatedAt=$updatedAt, turnId=$turnId, status=$status, stage=$stage, failureCode=$failureCode, provider=$provider, model=$model, sources=$sources]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'conversationId'] = this.conversationId;
      json[r'sequence'] = this.sequence;
      json[r'role'] = this.role;
      json[r'content'] = this.content;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
      json[r'turnId'] = this.turnId;
      json[r'status'] = this.status;
      json[r'stage'] = this.stage;
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
      json[r'provider'] = this.provider;
      json[r'model'] = this.model;
      json[r'sources'] = this.sources;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static ChatMessage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "ChatMessage[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "ChatMessage[id]" has a null value in JSON.');
        assert(json.containsKey(r'conversationId'), 'Required key "ChatMessage[conversationId]" is missing from JSON.');
        assert(json[r'conversationId'] != null, 'Required key "ChatMessage[conversationId]" has a null value in JSON.');
        assert(json.containsKey(r'sequence'), 'Required key "ChatMessage[sequence]" is missing from JSON.');
        assert(json[r'sequence'] != null, 'Required key "ChatMessage[sequence]" has a null value in JSON.');
        assert(json.containsKey(r'role'), 'Required key "ChatMessage[role]" is missing from JSON.');
        assert(json[r'role'] != null, 'Required key "ChatMessage[role]" has a null value in JSON.');
        assert(json.containsKey(r'content'), 'Required key "ChatMessage[content]" is missing from JSON.');
        assert(json[r'content'] != null, 'Required key "ChatMessage[content]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "ChatMessage[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "ChatMessage[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "ChatMessage[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "ChatMessage[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'turnId'), 'Required key "ChatMessage[turnId]" is missing from JSON.');
        assert(json[r'turnId'] != null, 'Required key "ChatMessage[turnId]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "ChatMessage[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "ChatMessage[status]" has a null value in JSON.');
        assert(json.containsKey(r'stage'), 'Required key "ChatMessage[stage]" is missing from JSON.');
        assert(json[r'stage'] != null, 'Required key "ChatMessage[stage]" has a null value in JSON.');
        assert(json.containsKey(r'provider'), 'Required key "ChatMessage[provider]" is missing from JSON.');
        assert(json[r'provider'] != null, 'Required key "ChatMessage[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'), 'Required key "ChatMessage[model]" is missing from JSON.');
        assert(json[r'model'] != null, 'Required key "ChatMessage[model]" has a null value in JSON.');
        assert(json.containsKey(r'sources'), 'Required key "ChatMessage[sources]" is missing from JSON.');
        assert(json[r'sources'] != null, 'Required key "ChatMessage[sources]" has a null value in JSON.');
        return true;
      }());

      return ChatMessage(
        id: mapValueOfType<String>(json, r'id')!,
        conversationId: mapValueOfType<String>(json, r'conversationId')!,
        sequence: mapValueOfType<int>(json, r'sequence')!,
        role: ChatMessageRoleEnum.fromJson(json[r'role'])!,
        content: mapValueOfType<String>(json, r'content')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        turnId: mapValueOfType<String>(json, r'turnId')!,
        status: ChatMessageStatusEnum.fromJson(json[r'status'])!,
        stage: ChatMessageStageEnum.fromJson(json[r'stage'])!,
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        provider: ChatMessageProviderEnum.fromJson(json[r'provider'])!,
        model: mapValueOfType<String>(json, r'model')!,
        sources: ChatSource.listFromJson(json[r'sources']),
      );
    }
    return null;
  }

  static List<ChatMessage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatMessage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatMessage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ChatMessage> mapFromJson(dynamic json) {
    final map = <String, ChatMessage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ChatMessage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<ChatMessage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ChatMessage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ChatMessage.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'conversationId',
    'sequence',
    'role',
    'content',
    'createdAt',
    'updatedAt',
    'turnId',
    'status',
    'stage',
    'provider',
    'model',
    'sources',
  };
}

enum ChatMessageRoleEnum {
  user._(r'user'),
  assistant._(r'assistant'),
  ;

  const ChatMessageRoleEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static ChatMessageRoleEnum? fromJson(dynamic value) => ChatMessageRoleEnumTypeTransformer().decode(value);

  static List<ChatMessageRoleEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatMessageRoleEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatMessageRoleEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class ChatMessageRoleEnumTypeTransformer {
  factory ChatMessageRoleEnumTypeTransformer() => _instance ??= const ChatMessageRoleEnumTypeTransformer._();

  const ChatMessageRoleEnumTypeTransformer._();

  String encode(ChatMessageRoleEnum data) => data._value;

  ChatMessageRoleEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ChatMessageRoleEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'user': return ChatMessageRoleEnum.user;
        case r'assistant': return ChatMessageRoleEnum.assistant;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static ChatMessageRoleEnumTypeTransformer? _instance;
}

enum ChatMessageStatusEnum {
  queued._(r'queued'),
  running._(r'running'),
  completed._(r'completed'),
  failed._(r'failed'),
  cancelled._(r'cancelled'),
  ;

  const ChatMessageStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static ChatMessageStatusEnum? fromJson(dynamic value) => ChatMessageStatusEnumTypeTransformer().decode(value);

  static List<ChatMessageStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatMessageStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatMessageStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class ChatMessageStatusEnumTypeTransformer {
  factory ChatMessageStatusEnumTypeTransformer() => _instance ??= const ChatMessageStatusEnumTypeTransformer._();

  const ChatMessageStatusEnumTypeTransformer._();

  String encode(ChatMessageStatusEnum data) => data._value;

  ChatMessageStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ChatMessageStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return ChatMessageStatusEnum.queued;
        case r'running': return ChatMessageStatusEnum.running;
        case r'completed': return ChatMessageStatusEnum.completed;
        case r'failed': return ChatMessageStatusEnum.failed;
        case r'cancelled': return ChatMessageStatusEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static ChatMessageStatusEnumTypeTransformer? _instance;
}

enum ChatMessageStageEnum {
  queued._(r'queued'),
  waitingForIngestion._(r'waiting_for_ingestion'),
  preparing._(r'preparing'),
  generating._(r'generating'),
  searchingDocuments._(r'searching_documents'),
  readingDocument._(r'reading_document'),
  completed._(r'completed'),
  failed._(r'failed'),
  cancelled._(r'cancelled'),
  ;

  const ChatMessageStageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static ChatMessageStageEnum? fromJson(dynamic value) => ChatMessageStageEnumTypeTransformer().decode(value);

  static List<ChatMessageStageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatMessageStageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatMessageStageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class ChatMessageStageEnumTypeTransformer {
  factory ChatMessageStageEnumTypeTransformer() => _instance ??= const ChatMessageStageEnumTypeTransformer._();

  const ChatMessageStageEnumTypeTransformer._();

  String encode(ChatMessageStageEnum data) => data._value;

  ChatMessageStageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ChatMessageStageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return ChatMessageStageEnum.queued;
        case r'waiting_for_ingestion': return ChatMessageStageEnum.waitingForIngestion;
        case r'preparing': return ChatMessageStageEnum.preparing;
        case r'generating': return ChatMessageStageEnum.generating;
        case r'searching_documents': return ChatMessageStageEnum.searchingDocuments;
        case r'reading_document': return ChatMessageStageEnum.readingDocument;
        case r'completed': return ChatMessageStageEnum.completed;
        case r'failed': return ChatMessageStageEnum.failed;
        case r'cancelled': return ChatMessageStageEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static ChatMessageStageEnumTypeTransformer? _instance;
}

enum ChatMessageProviderEnum {
  ollama._(r'ollama'),
  openai._(r'openai'),
  ;

  const ChatMessageProviderEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static ChatMessageProviderEnum? fromJson(dynamic value) => ChatMessageProviderEnumTypeTransformer().decode(value);

  static List<ChatMessageProviderEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ChatMessageProviderEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ChatMessageProviderEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class ChatMessageProviderEnumTypeTransformer {
  factory ChatMessageProviderEnumTypeTransformer() => _instance ??= const ChatMessageProviderEnumTypeTransformer._();

  const ChatMessageProviderEnumTypeTransformer._();

  String encode(ChatMessageProviderEnum data) => data._value;

  ChatMessageProviderEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ChatMessageProviderEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ollama': return ChatMessageProviderEnum.ollama;
        case r'openai': return ChatMessageProviderEnum.openai;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static ChatMessageProviderEnumTypeTransformer? _instance;
}
