// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

enum RealtimeTopic {
  documents._(r'documents'),
  processing._(r'processing'),
  processingConfiguration._(r'processing_configuration'),
  email._(r'email'),
  paperless._(r'paperless'),
  chat._(r'chat'),
  activity._(r'activity'),
  identity._(r'identity'),
  members._(r'members'),
  systemUsers._(r'system_users'),
  ;

  const RealtimeTopic._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static RealtimeTopic? fromJson(dynamic value) => RealtimeTopicTypeTransformer().decode(value);

  static List<RealtimeTopic> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RealtimeTopic>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RealtimeTopic.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class RealtimeTopicTypeTransformer {
  factory RealtimeTopicTypeTransformer() => _instance ??= const RealtimeTopicTypeTransformer._();

  const RealtimeTopicTypeTransformer._();

  String encode(RealtimeTopic data) => data._value;

  RealtimeTopic? decode(dynamic data, {bool allowNull = true}) {
    if (data is RealtimeTopic) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'documents': return RealtimeTopic.documents;
        case r'processing': return RealtimeTopic.processing;
        case r'processing_configuration': return RealtimeTopic.processingConfiguration;
        case r'email': return RealtimeTopic.email;
        case r'paperless': return RealtimeTopic.paperless;
        case r'chat': return RealtimeTopic.chat;
        case r'activity': return RealtimeTopic.activity;
        case r'identity': return RealtimeTopic.identity;
        case r'members': return RealtimeTopic.members;
        case r'system_users': return RealtimeTopic.systemUsers;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static RealtimeTopicTypeTransformer? _instance;
}
