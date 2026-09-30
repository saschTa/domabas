// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoiceReference {
  InvoiceReference({
    required this.number,
    required this.issueDate,
    this.invoiceId,
    this.documentId,
  });

  String number;

  String issueDate;

  String? invoiceId;

  String? documentId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoiceReference &&
    other.number == number &&
    other.issueDate == issueDate &&
    other.invoiceId == invoiceId &&
    other.documentId == documentId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (number.hashCode) +
    (issueDate.hashCode) +
    (invoiceId == null ? 0 : invoiceId!.hashCode) +
    (documentId == null ? 0 : documentId!.hashCode);

  @override
  String toString() => 'InvoiceReference[number=$number, issueDate=$issueDate, invoiceId=$invoiceId, documentId=$documentId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'number'] = this.number;
      json[r'issueDate'] = this.issueDate;
    if (this.invoiceId != null) {
      json[r'invoiceId'] = this.invoiceId;
    } else {
      json[r'invoiceId'] = null;
    }
    if (this.documentId != null) {
      json[r'documentId'] = this.documentId;
    } else {
      json[r'documentId'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoiceReference? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'number'), 'Required key "InvoiceReference[number]" is missing from JSON.');
        assert(json[r'number'] != null, 'Required key "InvoiceReference[number]" has a null value in JSON.');
        assert(json.containsKey(r'issueDate'), 'Required key "InvoiceReference[issueDate]" is missing from JSON.');
        assert(json[r'issueDate'] != null, 'Required key "InvoiceReference[issueDate]" has a null value in JSON.');
        return true;
      }());

      return InvoiceReference(
        number: mapValueOfType<String>(json, r'number')!,
        issueDate: mapValueOfType<String>(json, r'issueDate')!,
        invoiceId: mapValueOfType<String>(json, r'invoiceId'),
        documentId: mapValueOfType<String>(json, r'documentId'),
      );
    }
    return null;
  }

  static List<InvoiceReference> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceReference>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceReference.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoiceReference> mapFromJson(dynamic json) {
    final map = <String, InvoiceReference>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoiceReference.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoiceReference>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoiceReference>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoiceReference.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'number',
    'issueDate',
  };
}
