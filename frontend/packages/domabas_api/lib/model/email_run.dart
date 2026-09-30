// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailRun {
  EmailRun({
    required this.id,
    required this.providerId,
    required this.namespaceId,
    required this.reason,
    required this.status,
    required this.stage,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
    required this.failureCode,
    required this.messagesDiscovered,
    required this.messagesAccepted,
    required this.messagesReused,
    required this.messagesSkipped,
    required this.messagesFailed,
    required this.messagesWithContentFailures,
    required this.attachmentsAccepted,
    required this.attachmentsReused,
    required this.attachmentsSkipped,
    required this.attachmentsFailed,
    required this.hasMore,
  });

  String id;

  String providerId;

  String namespaceId;

  EmailRunReasonEnum reason;

  EmailRunStatusEnum status;

  EmailRunStageEnum stage;

  DateTime createdAt;

  DateTime? startedAt;

  DateTime? finishedAt;

  String? failureCode;

  int messagesDiscovered;

  int messagesAccepted;

  int messagesReused;

  int messagesSkipped;

  int messagesFailed;

  int messagesWithContentFailures;

  int attachmentsAccepted;

  int attachmentsReused;

  int attachmentsSkipped;

  int attachmentsFailed;

  bool hasMore;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmailRun &&
    other.id == id &&
    other.providerId == providerId &&
    other.namespaceId == namespaceId &&
    other.reason == reason &&
    other.status == status &&
    other.stage == stage &&
    other.createdAt == createdAt &&
    other.startedAt == startedAt &&
    other.finishedAt == finishedAt &&
    other.failureCode == failureCode &&
    other.messagesDiscovered == messagesDiscovered &&
    other.messagesAccepted == messagesAccepted &&
    other.messagesReused == messagesReused &&
    other.messagesSkipped == messagesSkipped &&
    other.messagesFailed == messagesFailed &&
    other.messagesWithContentFailures == messagesWithContentFailures &&
    other.attachmentsAccepted == attachmentsAccepted &&
    other.attachmentsReused == attachmentsReused &&
    other.attachmentsSkipped == attachmentsSkipped &&
    other.attachmentsFailed == attachmentsFailed &&
    other.hasMore == hasMore;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (providerId.hashCode) +
    (namespaceId.hashCode) +
    (reason.hashCode) +
    (status.hashCode) +
    (stage.hashCode) +
    (createdAt.hashCode) +
    (startedAt == null ? 0 : startedAt!.hashCode) +
    (finishedAt == null ? 0 : finishedAt!.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (messagesDiscovered.hashCode) +
    (messagesAccepted.hashCode) +
    (messagesReused.hashCode) +
    (messagesSkipped.hashCode) +
    (messagesFailed.hashCode) +
    (messagesWithContentFailures.hashCode) +
    (attachmentsAccepted.hashCode) +
    (attachmentsReused.hashCode) +
    (attachmentsSkipped.hashCode) +
    (attachmentsFailed.hashCode) +
    (hasMore.hashCode);

  @override
  String toString() => 'EmailRun[id=$id, providerId=$providerId, namespaceId=$namespaceId, reason=$reason, status=$status, stage=$stage, createdAt=$createdAt, startedAt=$startedAt, finishedAt=$finishedAt, failureCode=$failureCode, messagesDiscovered=$messagesDiscovered, messagesAccepted=$messagesAccepted, messagesReused=$messagesReused, messagesSkipped=$messagesSkipped, messagesFailed=$messagesFailed, messagesWithContentFailures=$messagesWithContentFailures, attachmentsAccepted=$attachmentsAccepted, attachmentsReused=$attachmentsReused, attachmentsSkipped=$attachmentsSkipped, attachmentsFailed=$attachmentsFailed, hasMore=$hasMore]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'providerId'] = this.providerId;
      json[r'namespaceId'] = this.namespaceId;
      json[r'reason'] = this.reason;
      json[r'status'] = this.status;
      json[r'stage'] = this.stage;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    if (this.startedAt != null) {
      json[r'startedAt'] = this.startedAt!.toUtc().toIso8601String();
    } else {
      json[r'startedAt'] = null;
    }
    if (this.finishedAt != null) {
      json[r'finishedAt'] = this.finishedAt!.toUtc().toIso8601String();
    } else {
      json[r'finishedAt'] = null;
    }
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
      json[r'messagesDiscovered'] = this.messagesDiscovered;
      json[r'messagesAccepted'] = this.messagesAccepted;
      json[r'messagesReused'] = this.messagesReused;
      json[r'messagesSkipped'] = this.messagesSkipped;
      json[r'messagesFailed'] = this.messagesFailed;
      json[r'messagesWithContentFailures'] = this.messagesWithContentFailures;
      json[r'attachmentsAccepted'] = this.attachmentsAccepted;
      json[r'attachmentsReused'] = this.attachmentsReused;
      json[r'attachmentsSkipped'] = this.attachmentsSkipped;
      json[r'attachmentsFailed'] = this.attachmentsFailed;
      json[r'hasMore'] = this.hasMore;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static EmailRun? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "EmailRun[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "EmailRun[id]" has a null value in JSON.');
        assert(json.containsKey(r'providerId'), 'Required key "EmailRun[providerId]" is missing from JSON.');
        assert(json[r'providerId'] != null, 'Required key "EmailRun[providerId]" has a null value in JSON.');
        assert(json.containsKey(r'namespaceId'), 'Required key "EmailRun[namespaceId]" is missing from JSON.');
        assert(json[r'namespaceId'] != null, 'Required key "EmailRun[namespaceId]" has a null value in JSON.');
        assert(json.containsKey(r'reason'), 'Required key "EmailRun[reason]" is missing from JSON.');
        assert(json[r'reason'] != null, 'Required key "EmailRun[reason]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "EmailRun[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "EmailRun[status]" has a null value in JSON.');
        assert(json.containsKey(r'stage'), 'Required key "EmailRun[stage]" is missing from JSON.');
        assert(json[r'stage'] != null, 'Required key "EmailRun[stage]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "EmailRun[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "EmailRun[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'startedAt'), 'Required key "EmailRun[startedAt]" is missing from JSON.');
        assert(json.containsKey(r'finishedAt'), 'Required key "EmailRun[finishedAt]" is missing from JSON.');
        assert(json.containsKey(r'failureCode'), 'Required key "EmailRun[failureCode]" is missing from JSON.');
        assert(json.containsKey(r'messagesDiscovered'), 'Required key "EmailRun[messagesDiscovered]" is missing from JSON.');
        assert(json[r'messagesDiscovered'] != null, 'Required key "EmailRun[messagesDiscovered]" has a null value in JSON.');
        assert(json.containsKey(r'messagesAccepted'), 'Required key "EmailRun[messagesAccepted]" is missing from JSON.');
        assert(json[r'messagesAccepted'] != null, 'Required key "EmailRun[messagesAccepted]" has a null value in JSON.');
        assert(json.containsKey(r'messagesReused'), 'Required key "EmailRun[messagesReused]" is missing from JSON.');
        assert(json[r'messagesReused'] != null, 'Required key "EmailRun[messagesReused]" has a null value in JSON.');
        assert(json.containsKey(r'messagesSkipped'), 'Required key "EmailRun[messagesSkipped]" is missing from JSON.');
        assert(json[r'messagesSkipped'] != null, 'Required key "EmailRun[messagesSkipped]" has a null value in JSON.');
        assert(json.containsKey(r'messagesFailed'), 'Required key "EmailRun[messagesFailed]" is missing from JSON.');
        assert(json[r'messagesFailed'] != null, 'Required key "EmailRun[messagesFailed]" has a null value in JSON.');
        assert(json.containsKey(r'messagesWithContentFailures'), 'Required key "EmailRun[messagesWithContentFailures]" is missing from JSON.');
        assert(json[r'messagesWithContentFailures'] != null, 'Required key "EmailRun[messagesWithContentFailures]" has a null value in JSON.');
        assert(json.containsKey(r'attachmentsAccepted'), 'Required key "EmailRun[attachmentsAccepted]" is missing from JSON.');
        assert(json[r'attachmentsAccepted'] != null, 'Required key "EmailRun[attachmentsAccepted]" has a null value in JSON.');
        assert(json.containsKey(r'attachmentsReused'), 'Required key "EmailRun[attachmentsReused]" is missing from JSON.');
        assert(json[r'attachmentsReused'] != null, 'Required key "EmailRun[attachmentsReused]" has a null value in JSON.');
        assert(json.containsKey(r'attachmentsSkipped'), 'Required key "EmailRun[attachmentsSkipped]" is missing from JSON.');
        assert(json[r'attachmentsSkipped'] != null, 'Required key "EmailRun[attachmentsSkipped]" has a null value in JSON.');
        assert(json.containsKey(r'attachmentsFailed'), 'Required key "EmailRun[attachmentsFailed]" is missing from JSON.');
        assert(json[r'attachmentsFailed'] != null, 'Required key "EmailRun[attachmentsFailed]" has a null value in JSON.');
        assert(json.containsKey(r'hasMore'), 'Required key "EmailRun[hasMore]" is missing from JSON.');
        assert(json[r'hasMore'] != null, 'Required key "EmailRun[hasMore]" has a null value in JSON.');
        return true;
      }());

      return EmailRun(
        id: mapValueOfType<String>(json, r'id')!,
        providerId: mapValueOfType<String>(json, r'providerId')!,
        namespaceId: mapValueOfType<String>(json, r'namespaceId')!,
        reason: EmailRunReasonEnum.fromJson(json[r'reason'])!,
        status: EmailRunStatusEnum.fromJson(json[r'status'])!,
        stage: EmailRunStageEnum.fromJson(json[r'stage'])!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        startedAt: mapDateTime(json, r'startedAt', r''),
        finishedAt: mapDateTime(json, r'finishedAt', r''),
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        messagesDiscovered: mapValueOfType<int>(json, r'messagesDiscovered')!,
        messagesAccepted: mapValueOfType<int>(json, r'messagesAccepted')!,
        messagesReused: mapValueOfType<int>(json, r'messagesReused')!,
        messagesSkipped: mapValueOfType<int>(json, r'messagesSkipped')!,
        messagesFailed: mapValueOfType<int>(json, r'messagesFailed')!,
        messagesWithContentFailures: mapValueOfType<int>(json, r'messagesWithContentFailures')!,
        attachmentsAccepted: mapValueOfType<int>(json, r'attachmentsAccepted')!,
        attachmentsReused: mapValueOfType<int>(json, r'attachmentsReused')!,
        attachmentsSkipped: mapValueOfType<int>(json, r'attachmentsSkipped')!,
        attachmentsFailed: mapValueOfType<int>(json, r'attachmentsFailed')!,
        hasMore: mapValueOfType<bool>(json, r'hasMore')!,
      );
    }
    return null;
  }

  static List<EmailRun> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailRun>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailRun.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailRun> mapFromJson(dynamic json) {
    final map = <String, EmailRun>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailRun.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<EmailRun>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EmailRun>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailRun.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'providerId',
    'namespaceId',
    'reason',
    'status',
    'stage',
    'createdAt',
    'startedAt',
    'finishedAt',
    'failureCode',
    'messagesDiscovered',
    'messagesAccepted',
    'messagesReused',
    'messagesSkipped',
    'messagesFailed',
    'messagesWithContentFailures',
    'attachmentsAccepted',
    'attachmentsReused',
    'attachmentsSkipped',
    'attachmentsFailed',
    'hasMore',
  };
}

enum EmailRunReasonEnum {
  scheduled._(r'scheduled'),
  manual._(r'manual'),
  continuation._(r'continuation'),
  ;

  const EmailRunReasonEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailRunReasonEnum? fromJson(dynamic value) => EmailRunReasonEnumTypeTransformer().decode(value);

  static List<EmailRunReasonEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailRunReasonEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailRunReasonEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailRunReasonEnumTypeTransformer {
  factory EmailRunReasonEnumTypeTransformer() => _instance ??= const EmailRunReasonEnumTypeTransformer._();

  const EmailRunReasonEnumTypeTransformer._();

  String encode(EmailRunReasonEnum data) => data._value;

  EmailRunReasonEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailRunReasonEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'scheduled': return EmailRunReasonEnum.scheduled;
        case r'manual': return EmailRunReasonEnum.manual;
        case r'continuation': return EmailRunReasonEnum.continuation;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailRunReasonEnumTypeTransformer? _instance;
}

enum EmailRunStatusEnum {
  queued._(r'queued'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  partial._(r'partial'),
  failed._(r'failed'),
  cancelled._(r'cancelled'),
  ;

  const EmailRunStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailRunStatusEnum? fromJson(dynamic value) => EmailRunStatusEnumTypeTransformer().decode(value);

  static List<EmailRunStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailRunStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailRunStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailRunStatusEnumTypeTransformer {
  factory EmailRunStatusEnumTypeTransformer() => _instance ??= const EmailRunStatusEnumTypeTransformer._();

  const EmailRunStatusEnumTypeTransformer._();

  String encode(EmailRunStatusEnum data) => data._value;

  EmailRunStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailRunStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return EmailRunStatusEnum.queued;
        case r'running': return EmailRunStatusEnum.running;
        case r'succeeded': return EmailRunStatusEnum.succeeded;
        case r'partial': return EmailRunStatusEnum.partial;
        case r'failed': return EmailRunStatusEnum.failed;
        case r'cancelled': return EmailRunStatusEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailRunStatusEnumTypeTransformer? _instance;
}

enum EmailRunStageEnum {
  queued._(r'queued'),
  discovering._(r'discovering'),
  fetching._(r'fetching'),
  importing._(r'importing'),
  complete._(r'complete'),
  ;

  const EmailRunStageEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailRunStageEnum? fromJson(dynamic value) => EmailRunStageEnumTypeTransformer().decode(value);

  static List<EmailRunStageEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailRunStageEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailRunStageEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailRunStageEnumTypeTransformer {
  factory EmailRunStageEnumTypeTransformer() => _instance ??= const EmailRunStageEnumTypeTransformer._();

  const EmailRunStageEnumTypeTransformer._();

  String encode(EmailRunStageEnum data) => data._value;

  EmailRunStageEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailRunStageEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return EmailRunStageEnum.queued;
        case r'discovering': return EmailRunStageEnum.discovering;
        case r'fetching': return EmailRunStageEnum.fetching;
        case r'importing': return EmailRunStageEnum.importing;
        case r'complete': return EmailRunStageEnum.complete;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailRunStageEnumTypeTransformer? _instance;
}
