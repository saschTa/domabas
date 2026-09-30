// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoiceLine {
  InvoiceLine({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.netAmount,
    required this.taxCategory,
    required this.taxRate,
  });

  String id;

  String description;

  String quantity;

  String unitCode;

  String unitPrice;

  String netAmount;

  String taxCategory;

  String taxRate;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoiceLine &&
    other.id == id &&
    other.description == description &&
    other.quantity == quantity &&
    other.unitCode == unitCode &&
    other.unitPrice == unitPrice &&
    other.netAmount == netAmount &&
    other.taxCategory == taxCategory &&
    other.taxRate == taxRate;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (description.hashCode) +
    (quantity.hashCode) +
    (unitCode.hashCode) +
    (unitPrice.hashCode) +
    (netAmount.hashCode) +
    (taxCategory.hashCode) +
    (taxRate.hashCode);

  @override
  String toString() => 'InvoiceLine[id=$id, description=$description, quantity=$quantity, unitCode=$unitCode, unitPrice=$unitPrice, netAmount=$netAmount, taxCategory=$taxCategory, taxRate=$taxRate]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'description'] = this.description;
      json[r'quantity'] = this.quantity;
      json[r'unitCode'] = this.unitCode;
      json[r'unitPrice'] = this.unitPrice;
      json[r'netAmount'] = this.netAmount;
      json[r'taxCategory'] = this.taxCategory;
      json[r'taxRate'] = this.taxRate;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoiceLine? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "InvoiceLine[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "InvoiceLine[id]" has a null value in JSON.');
        assert(json.containsKey(r'description'), 'Required key "InvoiceLine[description]" is missing from JSON.');
        assert(json[r'description'] != null, 'Required key "InvoiceLine[description]" has a null value in JSON.');
        assert(json.containsKey(r'quantity'), 'Required key "InvoiceLine[quantity]" is missing from JSON.');
        assert(json[r'quantity'] != null, 'Required key "InvoiceLine[quantity]" has a null value in JSON.');
        assert(json.containsKey(r'unitCode'), 'Required key "InvoiceLine[unitCode]" is missing from JSON.');
        assert(json[r'unitCode'] != null, 'Required key "InvoiceLine[unitCode]" has a null value in JSON.');
        assert(json.containsKey(r'unitPrice'), 'Required key "InvoiceLine[unitPrice]" is missing from JSON.');
        assert(json[r'unitPrice'] != null, 'Required key "InvoiceLine[unitPrice]" has a null value in JSON.');
        assert(json.containsKey(r'netAmount'), 'Required key "InvoiceLine[netAmount]" is missing from JSON.');
        assert(json[r'netAmount'] != null, 'Required key "InvoiceLine[netAmount]" has a null value in JSON.');
        assert(json.containsKey(r'taxCategory'), 'Required key "InvoiceLine[taxCategory]" is missing from JSON.');
        assert(json[r'taxCategory'] != null, 'Required key "InvoiceLine[taxCategory]" has a null value in JSON.');
        assert(json.containsKey(r'taxRate'), 'Required key "InvoiceLine[taxRate]" is missing from JSON.');
        assert(json[r'taxRate'] != null, 'Required key "InvoiceLine[taxRate]" has a null value in JSON.');
        return true;
      }());

      return InvoiceLine(
        id: mapValueOfType<String>(json, r'id')!,
        description: mapValueOfType<String>(json, r'description')!,
        quantity: mapValueOfType<String>(json, r'quantity')!,
        unitCode: mapValueOfType<String>(json, r'unitCode')!,
        unitPrice: mapValueOfType<String>(json, r'unitPrice')!,
        netAmount: mapValueOfType<String>(json, r'netAmount')!,
        taxCategory: mapValueOfType<String>(json, r'taxCategory')!,
        taxRate: mapValueOfType<String>(json, r'taxRate')!,
      );
    }
    return null;
  }

  static List<InvoiceLine> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceLine>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceLine.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoiceLine> mapFromJson(dynamic json) {
    final map = <String, InvoiceLine>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoiceLine.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoiceLine>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoiceLine>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoiceLine.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'description',
    'quantity',
    'unitCode',
    'unitPrice',
    'netAmount',
    'taxCategory',
    'taxRate',
  };
}
