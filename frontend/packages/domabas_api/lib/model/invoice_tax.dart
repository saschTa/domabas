// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoiceTax {
  InvoiceTax({
    required this.category,
    required this.rate,
    required this.taxableAmount,
    required this.taxAmount,
    required this.exemptionReason,
  });

  String category;

  String rate;

  String taxableAmount;

  String taxAmount;

  String exemptionReason;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoiceTax &&
    other.category == category &&
    other.rate == rate &&
    other.taxableAmount == taxableAmount &&
    other.taxAmount == taxAmount &&
    other.exemptionReason == exemptionReason;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (category.hashCode) +
    (rate.hashCode) +
    (taxableAmount.hashCode) +
    (taxAmount.hashCode) +
    (exemptionReason.hashCode);

  @override
  String toString() => 'InvoiceTax[category=$category, rate=$rate, taxableAmount=$taxableAmount, taxAmount=$taxAmount, exemptionReason=$exemptionReason]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'category'] = this.category;
      json[r'rate'] = this.rate;
      json[r'taxableAmount'] = this.taxableAmount;
      json[r'taxAmount'] = this.taxAmount;
      json[r'exemptionReason'] = this.exemptionReason;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoiceTax? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'category'), 'Required key "InvoiceTax[category]" is missing from JSON.');
        assert(json[r'category'] != null, 'Required key "InvoiceTax[category]" has a null value in JSON.');
        assert(json.containsKey(r'rate'), 'Required key "InvoiceTax[rate]" is missing from JSON.');
        assert(json[r'rate'] != null, 'Required key "InvoiceTax[rate]" has a null value in JSON.');
        assert(json.containsKey(r'taxableAmount'), 'Required key "InvoiceTax[taxableAmount]" is missing from JSON.');
        assert(json[r'taxableAmount'] != null, 'Required key "InvoiceTax[taxableAmount]" has a null value in JSON.');
        assert(json.containsKey(r'taxAmount'), 'Required key "InvoiceTax[taxAmount]" is missing from JSON.');
        assert(json[r'taxAmount'] != null, 'Required key "InvoiceTax[taxAmount]" has a null value in JSON.');
        assert(json.containsKey(r'exemptionReason'), 'Required key "InvoiceTax[exemptionReason]" is missing from JSON.');
        assert(json[r'exemptionReason'] != null, 'Required key "InvoiceTax[exemptionReason]" has a null value in JSON.');
        return true;
      }());

      return InvoiceTax(
        category: mapValueOfType<String>(json, r'category')!,
        rate: mapValueOfType<String>(json, r'rate')!,
        taxableAmount: mapValueOfType<String>(json, r'taxableAmount')!,
        taxAmount: mapValueOfType<String>(json, r'taxAmount')!,
        exemptionReason: mapValueOfType<String>(json, r'exemptionReason')!,
      );
    }
    return null;
  }

  static List<InvoiceTax> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceTax>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceTax.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoiceTax> mapFromJson(dynamic json) {
    final map = <String, InvoiceTax>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoiceTax.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoiceTax>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoiceTax>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoiceTax.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'category',
    'rate',
    'taxableAmount',
    'taxAmount',
    'exemptionReason',
  };
}
