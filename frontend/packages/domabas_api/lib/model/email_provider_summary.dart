// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailProviderSummary {
  EmailProviderSummary({
    required this.id,
    required this.namespaceId,
    required this.label,
    required this.host,
    required this.port,
    required this.mailbox,
    required this.intervalMinutes,
    required this.maxAgeDays,
    required this.pageSize,
    required this.enabled,
    required this.revision,
    required this.sourceGeneration,
    required this.credentialState,
    required this.consentState,
    required this.createdAt,
    required this.updatedAt,
    required this.lastAttemptAt,
    required this.nextDueAt,
    required this.activeRunId,
    required this.lastRunStatus,
    required this.failureCode,
  });

  String id;

  String namespaceId;

  String label;

  String host;

  int port;

  String mailbox;

  int intervalMinutes;

  int maxAgeDays;

  int pageSize;

  bool enabled;

  int revision;

  int sourceGeneration;

  EmailProviderSummaryCredentialStateEnum credentialState;

  EmailProviderSummaryConsentStateEnum consentState;

  DateTime createdAt;

  DateTime updatedAt;

  DateTime? lastAttemptAt;

  DateTime? nextDueAt;

  String? activeRunId;

  EmailProviderSummaryLastRunStatusEnum? lastRunStatus;

  String? failureCode;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmailProviderSummary &&
    other.id == id &&
    other.namespaceId == namespaceId &&
    other.label == label &&
    other.host == host &&
    other.port == port &&
    other.mailbox == mailbox &&
    other.intervalMinutes == intervalMinutes &&
    other.maxAgeDays == maxAgeDays &&
    other.pageSize == pageSize &&
    other.enabled == enabled &&
    other.revision == revision &&
    other.sourceGeneration == sourceGeneration &&
    other.credentialState == credentialState &&
    other.consentState == consentState &&
    other.createdAt == createdAt &&
    other.updatedAt == updatedAt &&
    other.lastAttemptAt == lastAttemptAt &&
    other.nextDueAt == nextDueAt &&
    other.activeRunId == activeRunId &&
    other.lastRunStatus == lastRunStatus &&
    other.failureCode == failureCode;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (namespaceId.hashCode) +
    (label.hashCode) +
    (host.hashCode) +
    (port.hashCode) +
    (mailbox.hashCode) +
    (intervalMinutes.hashCode) +
    (maxAgeDays.hashCode) +
    (pageSize.hashCode) +
    (enabled.hashCode) +
    (revision.hashCode) +
    (sourceGeneration.hashCode) +
    (credentialState.hashCode) +
    (consentState.hashCode) +
    (createdAt.hashCode) +
    (updatedAt.hashCode) +
    (lastAttemptAt == null ? 0 : lastAttemptAt!.hashCode) +
    (nextDueAt == null ? 0 : nextDueAt!.hashCode) +
    (activeRunId == null ? 0 : activeRunId!.hashCode) +
    (lastRunStatus == null ? 0 : lastRunStatus!.hashCode) +
    (failureCode == null ? 0 : failureCode!.hashCode);

  @override
  String toString() => 'EmailProviderSummary[id=$id, namespaceId=$namespaceId, label=$label, host=$host, port=$port, mailbox=$mailbox, intervalMinutes=$intervalMinutes, maxAgeDays=$maxAgeDays, pageSize=$pageSize, enabled=$enabled, revision=$revision, sourceGeneration=$sourceGeneration, credentialState=$credentialState, consentState=$consentState, createdAt=$createdAt, updatedAt=$updatedAt, lastAttemptAt=$lastAttemptAt, nextDueAt=$nextDueAt, activeRunId=$activeRunId, lastRunStatus=$lastRunStatus, failureCode=$failureCode]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'namespaceId'] = this.namespaceId;
      json[r'label'] = this.label;
      json[r'host'] = this.host;
      json[r'port'] = this.port;
      json[r'mailbox'] = this.mailbox;
      json[r'intervalMinutes'] = this.intervalMinutes;
      json[r'maxAgeDays'] = this.maxAgeDays;
      json[r'pageSize'] = this.pageSize;
      json[r'enabled'] = this.enabled;
      json[r'revision'] = this.revision;
      json[r'sourceGeneration'] = this.sourceGeneration;
      json[r'credentialState'] = this.credentialState;
      json[r'consentState'] = this.consentState;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    if (this.lastAttemptAt != null) {
      json[r'lastAttemptAt'] = this.lastAttemptAt!.toUtc().toIso8601String();
    } else {
      json[r'lastAttemptAt'] = null;
    }
    if (this.nextDueAt != null) {
      json[r'nextDueAt'] = this.nextDueAt!.toUtc().toIso8601String();
    } else {
      json[r'nextDueAt'] = null;
    }
    if (this.activeRunId != null) {
      json[r'activeRunId'] = this.activeRunId;
    } else {
      json[r'activeRunId'] = null;
    }
    if (this.lastRunStatus != null) {
      json[r'lastRunStatus'] = this.lastRunStatus;
    } else {
      json[r'lastRunStatus'] = null;
    }
    if (this.failureCode != null) {
      json[r'failureCode'] = this.failureCode;
    } else {
      json[r'failureCode'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static EmailProviderSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "EmailProviderSummary[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "EmailProviderSummary[id]" has a null value in JSON.');
        assert(json.containsKey(r'namespaceId'), 'Required key "EmailProviderSummary[namespaceId]" is missing from JSON.');
        assert(json[r'namespaceId'] != null, 'Required key "EmailProviderSummary[namespaceId]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "EmailProviderSummary[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "EmailProviderSummary[label]" has a null value in JSON.');
        assert(json.containsKey(r'host'), 'Required key "EmailProviderSummary[host]" is missing from JSON.');
        assert(json[r'host'] != null, 'Required key "EmailProviderSummary[host]" has a null value in JSON.');
        assert(json.containsKey(r'port'), 'Required key "EmailProviderSummary[port]" is missing from JSON.');
        assert(json[r'port'] != null, 'Required key "EmailProviderSummary[port]" has a null value in JSON.');
        assert(json.containsKey(r'mailbox'), 'Required key "EmailProviderSummary[mailbox]" is missing from JSON.');
        assert(json[r'mailbox'] != null, 'Required key "EmailProviderSummary[mailbox]" has a null value in JSON.');
        assert(json.containsKey(r'intervalMinutes'), 'Required key "EmailProviderSummary[intervalMinutes]" is missing from JSON.');
        assert(json[r'intervalMinutes'] != null, 'Required key "EmailProviderSummary[intervalMinutes]" has a null value in JSON.');
        assert(json.containsKey(r'maxAgeDays'), 'Required key "EmailProviderSummary[maxAgeDays]" is missing from JSON.');
        assert(json[r'maxAgeDays'] != null, 'Required key "EmailProviderSummary[maxAgeDays]" has a null value in JSON.');
        assert(json.containsKey(r'pageSize'), 'Required key "EmailProviderSummary[pageSize]" is missing from JSON.');
        assert(json[r'pageSize'] != null, 'Required key "EmailProviderSummary[pageSize]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "EmailProviderSummary[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "EmailProviderSummary[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "EmailProviderSummary[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "EmailProviderSummary[revision]" has a null value in JSON.');
        assert(json.containsKey(r'sourceGeneration'), 'Required key "EmailProviderSummary[sourceGeneration]" is missing from JSON.');
        assert(json[r'sourceGeneration'] != null, 'Required key "EmailProviderSummary[sourceGeneration]" has a null value in JSON.');
        assert(json.containsKey(r'credentialState'), 'Required key "EmailProviderSummary[credentialState]" is missing from JSON.');
        assert(json[r'credentialState'] != null, 'Required key "EmailProviderSummary[credentialState]" has a null value in JSON.');
        assert(json.containsKey(r'consentState'), 'Required key "EmailProviderSummary[consentState]" is missing from JSON.');
        assert(json[r'consentState'] != null, 'Required key "EmailProviderSummary[consentState]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "EmailProviderSummary[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "EmailProviderSummary[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "EmailProviderSummary[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "EmailProviderSummary[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'lastAttemptAt'), 'Required key "EmailProviderSummary[lastAttemptAt]" is missing from JSON.');
        assert(json.containsKey(r'nextDueAt'), 'Required key "EmailProviderSummary[nextDueAt]" is missing from JSON.');
        assert(json.containsKey(r'activeRunId'), 'Required key "EmailProviderSummary[activeRunId]" is missing from JSON.');
        assert(json.containsKey(r'lastRunStatus'), 'Required key "EmailProviderSummary[lastRunStatus]" is missing from JSON.');
        assert(json.containsKey(r'failureCode'), 'Required key "EmailProviderSummary[failureCode]" is missing from JSON.');
        return true;
      }());

      return EmailProviderSummary(
        id: mapValueOfType<String>(json, r'id')!,
        namespaceId: mapValueOfType<String>(json, r'namespaceId')!,
        label: mapValueOfType<String>(json, r'label')!,
        host: mapValueOfType<String>(json, r'host')!,
        port: mapValueOfType<int>(json, r'port')!,
        mailbox: mapValueOfType<String>(json, r'mailbox')!,
        intervalMinutes: mapValueOfType<int>(json, r'intervalMinutes')!,
        maxAgeDays: mapValueOfType<int>(json, r'maxAgeDays')!,
        pageSize: mapValueOfType<int>(json, r'pageSize')!,
        enabled: mapValueOfType<bool>(json, r'enabled')!,
        revision: mapValueOfType<int>(json, r'revision')!,
        sourceGeneration: mapValueOfType<int>(json, r'sourceGeneration')!,
        credentialState: EmailProviderSummaryCredentialStateEnum.fromJson(json[r'credentialState'])!,
        consentState: EmailProviderSummaryConsentStateEnum.fromJson(json[r'consentState'])!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        lastAttemptAt: mapDateTime(json, r'lastAttemptAt', r''),
        nextDueAt: mapDateTime(json, r'nextDueAt', r''),
        activeRunId: mapValueOfType<String>(json, r'activeRunId'),
        lastRunStatus: EmailProviderSummaryLastRunStatusEnum.fromJson(json[r'lastRunStatus']),
        failureCode: mapValueOfType<String>(json, r'failureCode'),
      );
    }
    return null;
  }

  static List<EmailProviderSummary> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProviderSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProviderSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailProviderSummary> mapFromJson(dynamic json) {
    final map = <String, EmailProviderSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailProviderSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<EmailProviderSummary>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EmailProviderSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailProviderSummary.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'namespaceId',
    'label',
    'host',
    'port',
    'mailbox',
    'intervalMinutes',
    'maxAgeDays',
    'pageSize',
    'enabled',
    'revision',
    'sourceGeneration',
    'credentialState',
    'consentState',
    'createdAt',
    'updatedAt',
    'lastAttemptAt',
    'nextDueAt',
    'activeRunId',
    'lastRunStatus',
    'failureCode',
  };
}

enum EmailProviderSummaryCredentialStateEnum {
  ready._(r'ready'),
  missingKey._(r'missing_key'),
  unavailable._(r'unavailable'),
  ;

  const EmailProviderSummaryCredentialStateEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailProviderSummaryCredentialStateEnum? fromJson(dynamic value) => EmailProviderSummaryCredentialStateEnumTypeTransformer().decode(value);

  static List<EmailProviderSummaryCredentialStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProviderSummaryCredentialStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProviderSummaryCredentialStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailProviderSummaryCredentialStateEnumTypeTransformer {
  factory EmailProviderSummaryCredentialStateEnumTypeTransformer() => _instance ??= const EmailProviderSummaryCredentialStateEnumTypeTransformer._();

  const EmailProviderSummaryCredentialStateEnumTypeTransformer._();

  String encode(EmailProviderSummaryCredentialStateEnum data) => data._value;

  EmailProviderSummaryCredentialStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailProviderSummaryCredentialStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ready': return EmailProviderSummaryCredentialStateEnum.ready;
        case r'missing_key': return EmailProviderSummaryCredentialStateEnum.missingKey;
        case r'unavailable': return EmailProviderSummaryCredentialStateEnum.unavailable;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailProviderSummaryCredentialStateEnumTypeTransformer? _instance;
}

enum EmailProviderSummaryConsentStateEnum {
  valid._(r'valid'),
  renewalRequired._(r'renewal_required'),
  disabled._(r'disabled'),
  ;

  const EmailProviderSummaryConsentStateEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailProviderSummaryConsentStateEnum? fromJson(dynamic value) => EmailProviderSummaryConsentStateEnumTypeTransformer().decode(value);

  static List<EmailProviderSummaryConsentStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProviderSummaryConsentStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProviderSummaryConsentStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailProviderSummaryConsentStateEnumTypeTransformer {
  factory EmailProviderSummaryConsentStateEnumTypeTransformer() => _instance ??= const EmailProviderSummaryConsentStateEnumTypeTransformer._();

  const EmailProviderSummaryConsentStateEnumTypeTransformer._();

  String encode(EmailProviderSummaryConsentStateEnum data) => data._value;

  EmailProviderSummaryConsentStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailProviderSummaryConsentStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'valid': return EmailProviderSummaryConsentStateEnum.valid;
        case r'renewal_required': return EmailProviderSummaryConsentStateEnum.renewalRequired;
        case r'disabled': return EmailProviderSummaryConsentStateEnum.disabled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailProviderSummaryConsentStateEnumTypeTransformer? _instance;
}

enum EmailProviderSummaryLastRunStatusEnum {
  queued._(r'queued'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  partial._(r'partial'),
  failed._(r'failed'),
  cancelled._(r'cancelled'),
  ;

  const EmailProviderSummaryLastRunStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailProviderSummaryLastRunStatusEnum? fromJson(dynamic value) => EmailProviderSummaryLastRunStatusEnumTypeTransformer().decode(value);

  static List<EmailProviderSummaryLastRunStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProviderSummaryLastRunStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProviderSummaryLastRunStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailProviderSummaryLastRunStatusEnumTypeTransformer {
  factory EmailProviderSummaryLastRunStatusEnumTypeTransformer() => _instance ??= const EmailProviderSummaryLastRunStatusEnumTypeTransformer._();

  const EmailProviderSummaryLastRunStatusEnumTypeTransformer._();

  String encode(EmailProviderSummaryLastRunStatusEnum data) => data._value;

  EmailProviderSummaryLastRunStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailProviderSummaryLastRunStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return EmailProviderSummaryLastRunStatusEnum.queued;
        case r'running': return EmailProviderSummaryLastRunStatusEnum.running;
        case r'succeeded': return EmailProviderSummaryLastRunStatusEnum.succeeded;
        case r'partial': return EmailProviderSummaryLastRunStatusEnum.partial;
        case r'failed': return EmailProviderSummaryLastRunStatusEnum.failed;
        case r'cancelled': return EmailProviderSummaryLastRunStatusEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailProviderSummaryLastRunStatusEnumTypeTransformer? _instance;
}
