// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoicePayment {
  InvoicePayment({
    required this.meansCode,
    required this.reference,
    required this.iban,
    required this.bic,
    required this.terms,
  });

  String meansCode;

  String reference;

  String iban;

  String bic;

  String terms;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoicePayment &&
    other.meansCode == meansCode &&
    other.reference == reference &&
    other.iban == iban &&
    other.bic == bic &&
    other.terms == terms;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (meansCode.hashCode) +
    (reference.hashCode) +
    (iban.hashCode) +
    (bic.hashCode) +
    (terms.hashCode);

  @override
  String toString() => 'InvoicePayment[meansCode=$meansCode, reference=$reference, iban=$iban, bic=$bic, terms=$terms]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'meansCode'] = this.meansCode;
      json[r'reference'] = this.reference;
      json[r'iban'] = this.iban;
      json[r'bic'] = this.bic;
      json[r'terms'] = this.terms;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoicePayment? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'meansCode'), 'Required key "InvoicePayment[meansCode]" is missing from JSON.');
        assert(json[r'meansCode'] != null, 'Required key "InvoicePayment[meansCode]" has a null value in JSON.');
        assert(json.containsKey(r'reference'), 'Required key "InvoicePayment[reference]" is missing from JSON.');
        assert(json[r'reference'] != null, 'Required key "InvoicePayment[reference]" has a null value in JSON.');
        assert(json.containsKey(r'iban'), 'Required key "InvoicePayment[iban]" is missing from JSON.');
        assert(json[r'iban'] != null, 'Required key "InvoicePayment[iban]" has a null value in JSON.');
        assert(json.containsKey(r'bic'), 'Required key "InvoicePayment[bic]" is missing from JSON.');
        assert(json[r'bic'] != null, 'Required key "InvoicePayment[bic]" has a null value in JSON.');
        assert(json.containsKey(r'terms'), 'Required key "InvoicePayment[terms]" is missing from JSON.');
        assert(json[r'terms'] != null, 'Required key "InvoicePayment[terms]" has a null value in JSON.');
        return true;
      }());

      return InvoicePayment(
        meansCode: mapValueOfType<String>(json, r'meansCode')!,
        reference: mapValueOfType<String>(json, r'reference')!,
        iban: mapValueOfType<String>(json, r'iban')!,
        bic: mapValueOfType<String>(json, r'bic')!,
        terms: mapValueOfType<String>(json, r'terms')!,
      );
    }
    return null;
  }

  static List<InvoicePayment> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoicePayment>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoicePayment.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoicePayment> mapFromJson(dynamic json) {
    final map = <String, InvoicePayment>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoicePayment.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoicePayment>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoicePayment>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoicePayment.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'meansCode',
    'reference',
    'iban',
    'bic',
    'terms',
  };
}
