// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoiceParty {
  InvoiceParty({
    required this.name,
    required this.taxId,
    required this.registrationId,
    required this.address,
    required this.country,
    required this.email,
  });

  String name;

  String taxId;

  String registrationId;

  String address;

  String country;

  String email;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoiceParty &&
    other.name == name &&
    other.taxId == taxId &&
    other.registrationId == registrationId &&
    other.address == address &&
    other.country == country &&
    other.email == email;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (name.hashCode) +
    (taxId.hashCode) +
    (registrationId.hashCode) +
    (address.hashCode) +
    (country.hashCode) +
    (email.hashCode);

  @override
  String toString() => 'InvoiceParty[name=$name, taxId=$taxId, registrationId=$registrationId, address=$address, country=$country, email=$email]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'name'] = this.name;
      json[r'taxId'] = this.taxId;
      json[r'registrationId'] = this.registrationId;
      json[r'address'] = this.address;
      json[r'country'] = this.country;
      json[r'email'] = this.email;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoiceParty? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'name'), 'Required key "InvoiceParty[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "InvoiceParty[name]" has a null value in JSON.');
        assert(json.containsKey(r'taxId'), 'Required key "InvoiceParty[taxId]" is missing from JSON.');
        assert(json[r'taxId'] != null, 'Required key "InvoiceParty[taxId]" has a null value in JSON.');
        assert(json.containsKey(r'registrationId'), 'Required key "InvoiceParty[registrationId]" is missing from JSON.');
        assert(json[r'registrationId'] != null, 'Required key "InvoiceParty[registrationId]" has a null value in JSON.');
        assert(json.containsKey(r'address'), 'Required key "InvoiceParty[address]" is missing from JSON.');
        assert(json[r'address'] != null, 'Required key "InvoiceParty[address]" has a null value in JSON.');
        assert(json.containsKey(r'country'), 'Required key "InvoiceParty[country]" is missing from JSON.');
        assert(json[r'country'] != null, 'Required key "InvoiceParty[country]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "InvoiceParty[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "InvoiceParty[email]" has a null value in JSON.');
        return true;
      }());

      return InvoiceParty(
        name: mapValueOfType<String>(json, r'name')!,
        taxId: mapValueOfType<String>(json, r'taxId')!,
        registrationId: mapValueOfType<String>(json, r'registrationId')!,
        address: mapValueOfType<String>(json, r'address')!,
        country: mapValueOfType<String>(json, r'country')!,
        email: mapValueOfType<String>(json, r'email')!,
      );
    }
    return null;
  }

  static List<InvoiceParty> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceParty>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceParty.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoiceParty> mapFromJson(dynamic json) {
    final map = <String, InvoiceParty>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoiceParty.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoiceParty>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoiceParty>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoiceParty.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'name',
    'taxId',
    'registrationId',
    'address',
    'country',
    'email',
  };
}
