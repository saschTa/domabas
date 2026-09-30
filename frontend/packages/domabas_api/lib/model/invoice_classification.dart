// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoiceClassification {
  InvoiceClassification({
    required this.decision,
    required this.reason,
    required this.inputCharacters,
    required this.sourceCharacters,
    required this.pass,
  });

  InvoiceClassificationDecisionEnum decision;

  String reason;

  int inputCharacters;

  int sourceCharacters;

  int pass;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoiceClassification &&
    other.decision == decision &&
    other.reason == reason &&
    other.inputCharacters == inputCharacters &&
    other.sourceCharacters == sourceCharacters &&
    other.pass == pass;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (decision.hashCode) +
    (reason.hashCode) +
    (inputCharacters.hashCode) +
    (sourceCharacters.hashCode) +
    (pass.hashCode);

  @override
  String toString() => 'InvoiceClassification[decision=$decision, reason=$reason, inputCharacters=$inputCharacters, sourceCharacters=$sourceCharacters, pass=$pass]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'decision'] = this.decision;
      json[r'reason'] = this.reason;
      json[r'inputCharacters'] = this.inputCharacters;
      json[r'sourceCharacters'] = this.sourceCharacters;
      json[r'pass'] = this.pass;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoiceClassification? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'decision'), 'Required key "InvoiceClassification[decision]" is missing from JSON.');
        assert(json[r'decision'] != null, 'Required key "InvoiceClassification[decision]" has a null value in JSON.');
        assert(json.containsKey(r'reason'), 'Required key "InvoiceClassification[reason]" is missing from JSON.');
        assert(json[r'reason'] != null, 'Required key "InvoiceClassification[reason]" has a null value in JSON.');
        assert(json.containsKey(r'inputCharacters'), 'Required key "InvoiceClassification[inputCharacters]" is missing from JSON.');
        assert(json[r'inputCharacters'] != null, 'Required key "InvoiceClassification[inputCharacters]" has a null value in JSON.');
        assert(json.containsKey(r'sourceCharacters'), 'Required key "InvoiceClassification[sourceCharacters]" is missing from JSON.');
        assert(json[r'sourceCharacters'] != null, 'Required key "InvoiceClassification[sourceCharacters]" has a null value in JSON.');
        assert(json.containsKey(r'pass'), 'Required key "InvoiceClassification[pass]" is missing from JSON.');
        assert(json[r'pass'] != null, 'Required key "InvoiceClassification[pass]" has a null value in JSON.');
        return true;
      }());

      return InvoiceClassification(
        decision: InvoiceClassificationDecisionEnum.fromJson(json[r'decision'])!,
        reason: mapValueOfType<String>(json, r'reason')!,
        inputCharacters: mapValueOfType<int>(json, r'inputCharacters')!,
        sourceCharacters: mapValueOfType<int>(json, r'sourceCharacters')!,
        pass: mapValueOfType<int>(json, r'pass')!,
      );
    }
    return null;
  }

  static List<InvoiceClassification> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceClassification>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceClassification.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoiceClassification> mapFromJson(dynamic json) {
    final map = <String, InvoiceClassification>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoiceClassification.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoiceClassification>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoiceClassification>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoiceClassification.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'decision',
    'reason',
    'inputCharacters',
    'sourceCharacters',
    'pass',
  };
}

enum InvoiceClassificationDecisionEnum {
  invoice._(r'invoice'),
  notInvoice._(r'not_invoice'),
  uncertain._(r'uncertain'),
  ;

  const InvoiceClassificationDecisionEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static InvoiceClassificationDecisionEnum? fromJson(dynamic value) => InvoiceClassificationDecisionEnumTypeTransformer().decode(value);

  static List<InvoiceClassificationDecisionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceClassificationDecisionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceClassificationDecisionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class InvoiceClassificationDecisionEnumTypeTransformer {
  factory InvoiceClassificationDecisionEnumTypeTransformer() => _instance ??= const InvoiceClassificationDecisionEnumTypeTransformer._();

  const InvoiceClassificationDecisionEnumTypeTransformer._();

  String encode(InvoiceClassificationDecisionEnum data) => data._value;

  InvoiceClassificationDecisionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is InvoiceClassificationDecisionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'invoice': return InvoiceClassificationDecisionEnum.invoice;
        case r'not_invoice': return InvoiceClassificationDecisionEnum.notInvoice;
        case r'uncertain': return InvoiceClassificationDecisionEnum.uncertain;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static InvoiceClassificationDecisionEnumTypeTransformer? _instance;
}
