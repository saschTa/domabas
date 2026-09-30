// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Invoice {
  Invoice({
    required this.id,
    required this.documentId,
    required this.createdAt,
    required this.documentTitle,
    required this.source_,
    required this.format,
    required this.number,
    required this.typeCode,
    required this.issueDate,
    required this.dueDate,
    required this.currency,
    required this.taxCurrency,
    required this.totalNet,
    required this.totalTax,
    required this.totalGross,
    required this.amountDue,
    required this.paidAmount,
    required this.roundingAmount,
    required this.taxAccountingAmount,
    required this.profile,
    required this.extractionModel,
    required this.seller,
    required this.buyer,
    required this.payment,
    this.lines = const [],
    this.taxes = const [],
    this.allowances = const [],
    this.references = const [],
    this.notes = const [],
  });

  String id;

  String documentId;

  DateTime createdAt;

  String documentTitle;

  String source_;

  String format;

  String number;

  String typeCode;

  String issueDate;

  String dueDate;

  String currency;

  String taxCurrency;

  String totalNet;

  String totalTax;

  String totalGross;

  String amountDue;

  String paidAmount;

  String roundingAmount;

  String taxAccountingAmount;

  String profile;

  String extractionModel;

  InvoiceParty seller;

  InvoiceParty buyer;

  InvoicePayment payment;

  List<InvoiceLine> lines;

  List<InvoiceTax> taxes;

  List<InvoiceAllowance> allowances;

  List<InvoiceReference> references;

  List<String> notes;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Invoice &&
    other.id == id &&
    other.documentId == documentId &&
    other.createdAt == createdAt &&
    other.documentTitle == documentTitle &&
    other.source_ == source_ &&
    other.format == format &&
    other.number == number &&
    other.typeCode == typeCode &&
    other.issueDate == issueDate &&
    other.dueDate == dueDate &&
    other.currency == currency &&
    other.taxCurrency == taxCurrency &&
    other.totalNet == totalNet &&
    other.totalTax == totalTax &&
    other.totalGross == totalGross &&
    other.amountDue == amountDue &&
    other.paidAmount == paidAmount &&
    other.roundingAmount == roundingAmount &&
    other.taxAccountingAmount == taxAccountingAmount &&
    other.profile == profile &&
    other.extractionModel == extractionModel &&
    other.seller == seller &&
    other.buyer == buyer &&
    other.payment == payment &&
    _deepEquality.equals(other.lines, lines) &&
    _deepEquality.equals(other.taxes, taxes) &&
    _deepEquality.equals(other.allowances, allowances) &&
    _deepEquality.equals(other.references, references) &&
    _deepEquality.equals(other.notes, notes);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (documentId.hashCode) +
    (createdAt.hashCode) +
    (documentTitle.hashCode) +
    (source_.hashCode) +
    (format.hashCode) +
    (number.hashCode) +
    (typeCode.hashCode) +
    (issueDate.hashCode) +
    (dueDate.hashCode) +
    (currency.hashCode) +
    (taxCurrency.hashCode) +
    (totalNet.hashCode) +
    (totalTax.hashCode) +
    (totalGross.hashCode) +
    (amountDue.hashCode) +
    (paidAmount.hashCode) +
    (roundingAmount.hashCode) +
    (taxAccountingAmount.hashCode) +
    (profile.hashCode) +
    (extractionModel.hashCode) +
    (seller.hashCode) +
    (buyer.hashCode) +
    (payment.hashCode) +
    (lines.hashCode) +
    (taxes.hashCode) +
    (allowances.hashCode) +
    (references.hashCode) +
    (notes.hashCode);

  @override
  String toString() => 'Invoice[id=$id, documentId=$documentId, createdAt=$createdAt, documentTitle=$documentTitle, source_=$source_, format=$format, number=$number, typeCode=$typeCode, issueDate=$issueDate, dueDate=$dueDate, currency=$currency, taxCurrency=$taxCurrency, totalNet=$totalNet, totalTax=$totalTax, totalGross=$totalGross, amountDue=$amountDue, paidAmount=$paidAmount, roundingAmount=$roundingAmount, taxAccountingAmount=$taxAccountingAmount, profile=$profile, extractionModel=$extractionModel, seller=$seller, buyer=$buyer, payment=$payment, lines=$lines, taxes=$taxes, allowances=$allowances, references=$references, notes=$notes]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'documentId'] = this.documentId;
      json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
      json[r'documentTitle'] = this.documentTitle;
      json[r'source'] = this.source_;
      json[r'format'] = this.format;
      json[r'number'] = this.number;
      json[r'typeCode'] = this.typeCode;
      json[r'issueDate'] = this.issueDate;
      json[r'dueDate'] = this.dueDate;
      json[r'currency'] = this.currency;
      json[r'taxCurrency'] = this.taxCurrency;
      json[r'totalNet'] = this.totalNet;
      json[r'totalTax'] = this.totalTax;
      json[r'totalGross'] = this.totalGross;
      json[r'amountDue'] = this.amountDue;
      json[r'paidAmount'] = this.paidAmount;
      json[r'roundingAmount'] = this.roundingAmount;
      json[r'taxAccountingAmount'] = this.taxAccountingAmount;
      json[r'profile'] = this.profile;
      json[r'extractionModel'] = this.extractionModel;
      json[r'seller'] = this.seller;
      json[r'buyer'] = this.buyer;
      json[r'payment'] = this.payment;
      json[r'lines'] = this.lines;
      json[r'taxes'] = this.taxes;
      json[r'allowances'] = this.allowances;
      json[r'references'] = this.references;
      json[r'notes'] = this.notes;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static Invoice? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Invoice[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Invoice[id]" has a null value in JSON.');
        assert(json.containsKey(r'documentId'), 'Required key "Invoice[documentId]" is missing from JSON.');
        assert(json[r'documentId'] != null, 'Required key "Invoice[documentId]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'), 'Required key "Invoice[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null, 'Required key "Invoice[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'documentTitle'), 'Required key "Invoice[documentTitle]" is missing from JSON.');
        assert(json[r'documentTitle'] != null, 'Required key "Invoice[documentTitle]" has a null value in JSON.');
        assert(json.containsKey(r'source'), 'Required key "Invoice[source]" is missing from JSON.');
        assert(json[r'source'] != null, 'Required key "Invoice[source]" has a null value in JSON.');
        assert(json.containsKey(r'format'), 'Required key "Invoice[format]" is missing from JSON.');
        assert(json[r'format'] != null, 'Required key "Invoice[format]" has a null value in JSON.');
        assert(json.containsKey(r'number'), 'Required key "Invoice[number]" is missing from JSON.');
        assert(json[r'number'] != null, 'Required key "Invoice[number]" has a null value in JSON.');
        assert(json.containsKey(r'typeCode'), 'Required key "Invoice[typeCode]" is missing from JSON.');
        assert(json[r'typeCode'] != null, 'Required key "Invoice[typeCode]" has a null value in JSON.');
        assert(json.containsKey(r'issueDate'), 'Required key "Invoice[issueDate]" is missing from JSON.');
        assert(json[r'issueDate'] != null, 'Required key "Invoice[issueDate]" has a null value in JSON.');
        assert(json.containsKey(r'dueDate'), 'Required key "Invoice[dueDate]" is missing from JSON.');
        assert(json[r'dueDate'] != null, 'Required key "Invoice[dueDate]" has a null value in JSON.');
        assert(json.containsKey(r'currency'), 'Required key "Invoice[currency]" is missing from JSON.');
        assert(json[r'currency'] != null, 'Required key "Invoice[currency]" has a null value in JSON.');
        assert(json.containsKey(r'taxCurrency'), 'Required key "Invoice[taxCurrency]" is missing from JSON.');
        assert(json[r'taxCurrency'] != null, 'Required key "Invoice[taxCurrency]" has a null value in JSON.');
        assert(json.containsKey(r'totalNet'), 'Required key "Invoice[totalNet]" is missing from JSON.');
        assert(json[r'totalNet'] != null, 'Required key "Invoice[totalNet]" has a null value in JSON.');
        assert(json.containsKey(r'totalTax'), 'Required key "Invoice[totalTax]" is missing from JSON.');
        assert(json[r'totalTax'] != null, 'Required key "Invoice[totalTax]" has a null value in JSON.');
        assert(json.containsKey(r'totalGross'), 'Required key "Invoice[totalGross]" is missing from JSON.');
        assert(json[r'totalGross'] != null, 'Required key "Invoice[totalGross]" has a null value in JSON.');
        assert(json.containsKey(r'amountDue'), 'Required key "Invoice[amountDue]" is missing from JSON.');
        assert(json[r'amountDue'] != null, 'Required key "Invoice[amountDue]" has a null value in JSON.');
        assert(json.containsKey(r'paidAmount'), 'Required key "Invoice[paidAmount]" is missing from JSON.');
        assert(json[r'paidAmount'] != null, 'Required key "Invoice[paidAmount]" has a null value in JSON.');
        assert(json.containsKey(r'roundingAmount'), 'Required key "Invoice[roundingAmount]" is missing from JSON.');
        assert(json[r'roundingAmount'] != null, 'Required key "Invoice[roundingAmount]" has a null value in JSON.');
        assert(json.containsKey(r'taxAccountingAmount'), 'Required key "Invoice[taxAccountingAmount]" is missing from JSON.');
        assert(json[r'taxAccountingAmount'] != null, 'Required key "Invoice[taxAccountingAmount]" has a null value in JSON.');
        assert(json.containsKey(r'profile'), 'Required key "Invoice[profile]" is missing from JSON.');
        assert(json[r'profile'] != null, 'Required key "Invoice[profile]" has a null value in JSON.');
        assert(json.containsKey(r'extractionModel'), 'Required key "Invoice[extractionModel]" is missing from JSON.');
        assert(json[r'extractionModel'] != null, 'Required key "Invoice[extractionModel]" has a null value in JSON.');
        assert(json.containsKey(r'seller'), 'Required key "Invoice[seller]" is missing from JSON.');
        assert(json[r'seller'] != null, 'Required key "Invoice[seller]" has a null value in JSON.');
        assert(json.containsKey(r'buyer'), 'Required key "Invoice[buyer]" is missing from JSON.');
        assert(json[r'buyer'] != null, 'Required key "Invoice[buyer]" has a null value in JSON.');
        assert(json.containsKey(r'payment'), 'Required key "Invoice[payment]" is missing from JSON.');
        assert(json[r'payment'] != null, 'Required key "Invoice[payment]" has a null value in JSON.');
        assert(json.containsKey(r'lines'), 'Required key "Invoice[lines]" is missing from JSON.');
        assert(json[r'lines'] != null, 'Required key "Invoice[lines]" has a null value in JSON.');
        assert(json.containsKey(r'taxes'), 'Required key "Invoice[taxes]" is missing from JSON.');
        assert(json[r'taxes'] != null, 'Required key "Invoice[taxes]" has a null value in JSON.');
        assert(json.containsKey(r'allowances'), 'Required key "Invoice[allowances]" is missing from JSON.');
        assert(json[r'allowances'] != null, 'Required key "Invoice[allowances]" has a null value in JSON.');
        assert(json.containsKey(r'references'), 'Required key "Invoice[references]" is missing from JSON.');
        assert(json[r'references'] != null, 'Required key "Invoice[references]" has a null value in JSON.');
        assert(json.containsKey(r'notes'), 'Required key "Invoice[notes]" is missing from JSON.');
        assert(json[r'notes'] != null, 'Required key "Invoice[notes]" has a null value in JSON.');
        return true;
      }());

      return Invoice(
        id: mapValueOfType<String>(json, r'id')!,
        documentId: mapValueOfType<String>(json, r'documentId')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        documentTitle: mapValueOfType<String>(json, r'documentTitle')!,
        source_: mapValueOfType<String>(json, r'source')!,
        format: mapValueOfType<String>(json, r'format')!,
        number: mapValueOfType<String>(json, r'number')!,
        typeCode: mapValueOfType<String>(json, r'typeCode')!,
        issueDate: mapValueOfType<String>(json, r'issueDate')!,
        dueDate: mapValueOfType<String>(json, r'dueDate')!,
        currency: mapValueOfType<String>(json, r'currency')!,
        taxCurrency: mapValueOfType<String>(json, r'taxCurrency')!,
        totalNet: mapValueOfType<String>(json, r'totalNet')!,
        totalTax: mapValueOfType<String>(json, r'totalTax')!,
        totalGross: mapValueOfType<String>(json, r'totalGross')!,
        amountDue: mapValueOfType<String>(json, r'amountDue')!,
        paidAmount: mapValueOfType<String>(json, r'paidAmount')!,
        roundingAmount: mapValueOfType<String>(json, r'roundingAmount')!,
        taxAccountingAmount: mapValueOfType<String>(json, r'taxAccountingAmount')!,
        profile: mapValueOfType<String>(json, r'profile')!,
        extractionModel: mapValueOfType<String>(json, r'extractionModel')!,
        seller: InvoiceParty.fromJson(json[r'seller'])!,
        buyer: InvoiceParty.fromJson(json[r'buyer'])!,
        payment: InvoicePayment.fromJson(json[r'payment'])!,
        lines: InvoiceLine.listFromJson(json[r'lines']),
        taxes: InvoiceTax.listFromJson(json[r'taxes']),
        allowances: InvoiceAllowance.listFromJson(json[r'allowances']),
        references: InvoiceReference.listFromJson(json[r'references']),
        notes: json[r'notes'] is Iterable
            ? (json[r'notes'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<Invoice> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Invoice>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Invoice.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Invoice> mapFromJson(dynamic json) {
    final map = <String, Invoice>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Invoice.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<Invoice>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Invoice>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Invoice.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'id',
    'documentId',
    'createdAt',
    'documentTitle',
    'source',
    'format',
    'number',
    'typeCode',
    'issueDate',
    'dueDate',
    'currency',
    'taxCurrency',
    'totalNet',
    'totalTax',
    'totalGross',
    'amountDue',
    'paidAmount',
    'roundingAmount',
    'taxAccountingAmount',
    'profile',
    'extractionModel',
    'seller',
    'buyer',
    'payment',
    'lines',
    'taxes',
    'allowances',
    'references',
    'notes',
  };
}
