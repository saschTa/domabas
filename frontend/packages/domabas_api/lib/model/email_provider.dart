// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class EmailProvider {
  EmailProvider({
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
    required this.username,
    required this.hasPassword,
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

  EmailProviderCredentialStateEnum credentialState;

  EmailProviderConsentStateEnum consentState;

  DateTime createdAt;

  DateTime updatedAt;

  DateTime? lastAttemptAt;

  DateTime? nextDueAt;

  String? activeRunId;

  EmailProviderLastRunStatusEnum? lastRunStatus;

  String? failureCode;

  String? username;

  bool hasPassword;

  @override
  bool operator ==(Object other) => identical(this, other) || other is EmailProvider &&
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
    other.failureCode == failureCode &&
    other.username == username &&
    other.hasPassword == hasPassword;

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
    (failureCode == null ? 0 : failureCode!.hashCode) +
    (username == null ? 0 : username!.hashCode) +
    (hasPassword.hashCode);

  @override
  String toString() => 'EmailProvider[id=$id, namespaceId=$namespaceId, label=$label, host=$host, port=$port, mailbox=$mailbox, intervalMinutes=$intervalMinutes, maxAgeDays=$maxAgeDays, pageSize=$pageSize, enabled=$enabled, revision=$revision, sourceGeneration=$sourceGeneration, credentialState=$credentialState, consentState=$consentState, createdAt=$createdAt, updatedAt=$updatedAt, lastAttemptAt=$lastAttemptAt, nextDueAt=$nextDueAt, activeRunId=$activeRunId, lastRunStatus=$lastRunStatus, failureCode=$failureCode, username=$username, hasPassword=$hasPassword]';

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
    if (this.username != null) {
      json[r'username'] = this.username;
    } else {
      json[r'username'] = null;
    }
      json[r'hasPassword'] = this.hasPassword;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static EmailProvider? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "EmailProvider[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "EmailProvider[id]" has a null value in JSON.');
        assert(json.containsKey(r'namespaceId'), 'Required key "EmailProvider[namespaceId]" is missing from JSON.');
        assert(json[r'namespaceId'] != null, 'Required key "EmailProvider[namespaceId]" has a null value in JSON.');
        assert(json.containsKey(r'label'), 'Required key "EmailProvider[label]" is missing from JSON.');
        assert(json[r'label'] != null, 'Required key "EmailProvider[label]" has a null value in JSON.');
        assert(json.containsKey(r'host'), 'Required key "EmailProvider[host]" is missing from JSON.');
        assert(json[r'host'] != null, 'Required key "EmailProvider[host]" has a null value in JSON.');
        assert(json.containsKey(r'port'), 'Required key "EmailProvider[port]" is missing from JSON.');
        assert(json[r'port'] != null, 'Required key "EmailProvider[port]" has a null value in JSON.');
        assert(json.containsKey(r'mailbox'), 'Required key "EmailProvider[mailbox]" is missing from JSON.');
        assert(json[r'mailbox'] != null, 'Required key "EmailProvider[mailbox]" has a null value in JSON.');
        assert(json.containsKey(r'intervalMinutes'), 'Required key "EmailProvider[intervalMinutes]" is missing from JSON.');
        assert(json[r'intervalMinutes'] != null, 'Required key "EmailProvider[intervalMinutes]" has a null value in JSON.');
        assert(json.containsKey(r'maxAgeDays'), 'Required key "EmailProvider[maxAgeDays]" is missing from JSON.');
        assert(json[r'maxAgeDays'] != null, 'Required key "EmailProvider[maxAgeDays]" has a null value in JSON.');
        assert(json.containsKey(r'pageSize'), 'Required key "EmailProvider[pageSize]" is missing from JSON.');
        assert(json[r'pageSize'] != null, 'Required key "EmailProvider[pageSize]" has a null value in JSON.');
        assert(json.containsKey(r'enabled'), 'Required key "EmailProvider[enabled]" is missing from JSON.');
        assert(json[r'enabled'] != null, 'Required key "EmailProvider[enabled]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "EmailProvider[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "EmailProvider[revision]" has a null value in JSON.');
        assert(json.containsKey(r'sourceGeneration'), 'Required key "EmailProvider[sourceGeneration]" is missing from JSON.');
        assert(json[r'sourceGeneration'] != null, 'Required key "EmailProvider[sourceGeneration]" has a null value in JSON.');
        assert(json.containsKey(r'credentialState'), 'Required key "EmailProvider[credentialState]" is missing from JSON.');
        assert(json[r'credentialState'] != null, 'Required key "EmailProvider[credentialState]" has a null value in JSON.');
        assert(json.containsKey(r'consentState'), 'Required key "EmailProvider[consentState]" is missing from JSON.');
        assert(json[r'consentState'] != null, 'Required key "EmailProvider[consentState]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "EmailProvider[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "EmailProvider[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'), 'Required key "EmailProvider[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null, 'Required key "EmailProvider[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'lastAttemptAt'), 'Required key "EmailProvider[lastAttemptAt]" is missing from JSON.');
        assert(json.containsKey(r'nextDueAt'), 'Required key "EmailProvider[nextDueAt]" is missing from JSON.');
        assert(json.containsKey(r'activeRunId'), 'Required key "EmailProvider[activeRunId]" is missing from JSON.');
        assert(json.containsKey(r'lastRunStatus'), 'Required key "EmailProvider[lastRunStatus]" is missing from JSON.');
        assert(json.containsKey(r'failureCode'), 'Required key "EmailProvider[failureCode]" is missing from JSON.');
        assert(json.containsKey(r'username'), 'Required key "EmailProvider[username]" is missing from JSON.');
        assert(json.containsKey(r'hasPassword'), 'Required key "EmailProvider[hasPassword]" is missing from JSON.');
        assert(json[r'hasPassword'] != null, 'Required key "EmailProvider[hasPassword]" has a null value in JSON.');
        return true;
      }());

      return EmailProvider(
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
        credentialState: EmailProviderCredentialStateEnum.fromJson(json[r'credentialState'])!,
        consentState: EmailProviderConsentStateEnum.fromJson(json[r'consentState'])!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        lastAttemptAt: mapDateTime(json, r'lastAttemptAt', r''),
        nextDueAt: mapDateTime(json, r'nextDueAt', r''),
        activeRunId: mapValueOfType<String>(json, r'activeRunId'),
        lastRunStatus: EmailProviderLastRunStatusEnum.fromJson(json[r'lastRunStatus']),
        failureCode: mapValueOfType<String>(json, r'failureCode'),
        username: mapValueOfType<String>(json, r'username'),
        hasPassword: mapValueOfType<bool>(json, r'hasPassword')!,
      );
    }
    return null;
  }

  static List<EmailProvider> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProvider>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProvider.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, EmailProvider> mapFromJson(dynamic json) {
    final map = <String, EmailProvider>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = EmailProvider.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<EmailProvider>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<EmailProvider>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = EmailProvider.listFromJson(entry.value, growable: growable,);
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
    'username',
    'hasPassword',
  };
}

enum EmailProviderCredentialStateEnum {
  ready._(r'ready'),
  missingKey._(r'missing_key'),
  unavailable._(r'unavailable'),
  ;

  const EmailProviderCredentialStateEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailProviderCredentialStateEnum? fromJson(dynamic value) => EmailProviderCredentialStateEnumTypeTransformer().decode(value);

  static List<EmailProviderCredentialStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProviderCredentialStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProviderCredentialStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailProviderCredentialStateEnumTypeTransformer {
  factory EmailProviderCredentialStateEnumTypeTransformer() => _instance ??= const EmailProviderCredentialStateEnumTypeTransformer._();

  const EmailProviderCredentialStateEnumTypeTransformer._();

  String encode(EmailProviderCredentialStateEnum data) => data._value;

  EmailProviderCredentialStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailProviderCredentialStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ready': return EmailProviderCredentialStateEnum.ready;
        case r'missing_key': return EmailProviderCredentialStateEnum.missingKey;
        case r'unavailable': return EmailProviderCredentialStateEnum.unavailable;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailProviderCredentialStateEnumTypeTransformer? _instance;
}

enum EmailProviderConsentStateEnum {
  valid._(r'valid'),
  renewalRequired._(r'renewal_required'),
  disabled._(r'disabled'),
  ;

  const EmailProviderConsentStateEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailProviderConsentStateEnum? fromJson(dynamic value) => EmailProviderConsentStateEnumTypeTransformer().decode(value);

  static List<EmailProviderConsentStateEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProviderConsentStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProviderConsentStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailProviderConsentStateEnumTypeTransformer {
  factory EmailProviderConsentStateEnumTypeTransformer() => _instance ??= const EmailProviderConsentStateEnumTypeTransformer._();

  const EmailProviderConsentStateEnumTypeTransformer._();

  String encode(EmailProviderConsentStateEnum data) => data._value;

  EmailProviderConsentStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailProviderConsentStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'valid': return EmailProviderConsentStateEnum.valid;
        case r'renewal_required': return EmailProviderConsentStateEnum.renewalRequired;
        case r'disabled': return EmailProviderConsentStateEnum.disabled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailProviderConsentStateEnumTypeTransformer? _instance;
}

enum EmailProviderLastRunStatusEnum {
  queued._(r'queued'),
  running._(r'running'),
  succeeded._(r'succeeded'),
  partial._(r'partial'),
  failed._(r'failed'),
  cancelled._(r'cancelled'),
  ;

  const EmailProviderLastRunStatusEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static EmailProviderLastRunStatusEnum? fromJson(dynamic value) => EmailProviderLastRunStatusEnumTypeTransformer().decode(value);

  static List<EmailProviderLastRunStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <EmailProviderLastRunStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = EmailProviderLastRunStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class EmailProviderLastRunStatusEnumTypeTransformer {
  factory EmailProviderLastRunStatusEnumTypeTransformer() => _instance ??= const EmailProviderLastRunStatusEnumTypeTransformer._();

  const EmailProviderLastRunStatusEnumTypeTransformer._();

  String encode(EmailProviderLastRunStatusEnum data) => data._value;

  EmailProviderLastRunStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is EmailProviderLastRunStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'queued': return EmailProviderLastRunStatusEnum.queued;
        case r'running': return EmailProviderLastRunStatusEnum.running;
        case r'succeeded': return EmailProviderLastRunStatusEnum.succeeded;
        case r'partial': return EmailProviderLastRunStatusEnum.partial;
        case r'failed': return EmailProviderLastRunStatusEnum.failed;
        case r'cancelled': return EmailProviderLastRunStatusEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static EmailProviderLastRunStatusEnumTypeTransformer? _instance;
}
