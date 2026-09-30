// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoiceAllowance {
  InvoiceAllowance({
    required this.reason,
    required this.amount,
    required this.taxCategory,
    required this.taxRate,
    required this.charge,
  });

  String reason;

  String amount;

  String taxCategory;

  String taxRate;

  bool charge;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoiceAllowance &&
    other.reason == reason &&
    other.amount == amount &&
    other.taxCategory == taxCategory &&
    other.taxRate == taxRate &&
    other.charge == charge;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (reason.hashCode) +
    (amount.hashCode) +
    (taxCategory.hashCode) +
    (taxRate.hashCode) +
    (charge.hashCode);

  @override
  String toString() => 'InvoiceAllowance[reason=$reason, amount=$amount, taxCategory=$taxCategory, taxRate=$taxRate, charge=$charge]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'reason'] = this.reason;
      json[r'amount'] = this.amount;
      json[r'taxCategory'] = this.taxCategory;
      json[r'taxRate'] = this.taxRate;
      json[r'charge'] = this.charge;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoiceAllowance? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'reason'), 'Required key "InvoiceAllowance[reason]" is missing from JSON.');
        assert(json[r'reason'] != null, 'Required key "InvoiceAllowance[reason]" has a null value in JSON.');
        assert(json.containsKey(r'amount'), 'Required key "InvoiceAllowance[amount]" is missing from JSON.');
        assert(json[r'amount'] != null, 'Required key "InvoiceAllowance[amount]" has a null value in JSON.');
        assert(json.containsKey(r'taxCategory'), 'Required key "InvoiceAllowance[taxCategory]" is missing from JSON.');
        assert(json[r'taxCategory'] != null, 'Required key "InvoiceAllowance[taxCategory]" has a null value in JSON.');
        assert(json.containsKey(r'taxRate'), 'Required key "InvoiceAllowance[taxRate]" is missing from JSON.');
        assert(json[r'taxRate'] != null, 'Required key "InvoiceAllowance[taxRate]" has a null value in JSON.');
        assert(json.containsKey(r'charge'), 'Required key "InvoiceAllowance[charge]" is missing from JSON.');
        assert(json[r'charge'] != null, 'Required key "InvoiceAllowance[charge]" has a null value in JSON.');
        return true;
      }());

      return InvoiceAllowance(
        reason: mapValueOfType<String>(json, r'reason')!,
        amount: mapValueOfType<String>(json, r'amount')!,
        taxCategory: mapValueOfType<String>(json, r'taxCategory')!,
        taxRate: mapValueOfType<String>(json, r'taxRate')!,
        charge: mapValueOfType<bool>(json, r'charge')!,
      );
    }
    return null;
  }

  static List<InvoiceAllowance> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceAllowance>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceAllowance.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoiceAllowance> mapFromJson(dynamic json) {
    final map = <String, InvoiceAllowance>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoiceAllowance.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoiceAllowance>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoiceAllowance>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoiceAllowance.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'reason',
    'amount',
    'taxCategory',
    'taxRate',
    'charge',
  };
}
