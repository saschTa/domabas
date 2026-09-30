enum InvoiceSort {
  automatic(null, 'Automatic'),
  createdDescending('created_desc', 'Newest added'),
  createdAscending('created_asc', 'Oldest added'),
  dueAscending('due_asc', 'Due date, earliest'),
  dueDescending('due_desc', 'Due date, latest'),
  issueAscending('issue_asc', 'Issue date, earliest'),
  issueDescending('issue_desc', 'Issue date, latest'),
  numberAscending('number_asc', 'Invoice number A–Z'),
  numberDescending('number_desc', 'Invoice number Z–A'),
  sellerAscending('seller_asc', 'Supplier A–Z'),
  sellerDescending('seller_desc', 'Supplier Z–A'),
  buyerAscending('buyer_asc', 'Customer A–Z'),
  buyerDescending('buyer_desc', 'Customer Z–A');

  const InvoiceSort(this.value, this.label);
  final String? value;
  final String label;
}

enum InvoiceFilterField {
  number('Invoice number'),
  seller('Supplier'),
  buyer('Customer'),
  currency('Currency'),
  typeCode('Invoice type'),
  format('Format'),
  paymentMeansCode('Payment method');

  const InvoiceFilterField(this.label);
  final String label;
}

final class InvoiceFilters {
  const InvoiceFilters({
    this.number = '',
    this.seller = '',
    this.buyer = '',
    this.currency = '',
    this.typeCode = '',
    this.format = '',
    this.paymentMeansCode = '',
    this.createdFrom = '',
    this.createdTo = '',
    this.issueFrom = '',
    this.issueTo = '',
    this.dueFrom = '',
    this.dueTo = '',
    this.totalMin = '',
    this.totalMax = '',
  });

  final String number, seller, buyer, currency, typeCode, format;
  final String paymentMeansCode, createdFrom, createdTo, issueFrom, issueTo;
  final String dueFrom, dueTo, totalMin, totalMax;

  String value(InvoiceFilterField field) => switch (field) {
    InvoiceFilterField.number => number,
    InvoiceFilterField.seller => seller,
    InvoiceFilterField.buyer => buyer,
    InvoiceFilterField.currency => currency,
    InvoiceFilterField.typeCode => typeCode,
    InvoiceFilterField.format => format,
    InvoiceFilterField.paymentMeansCode => paymentMeansCode,
  };

  int get count =>
      InvoiceFilterField.values
          .where((field) => value(field).isNotEmpty)
          .length +
      (createdFrom.isNotEmpty || createdTo.isNotEmpty ? 1 : 0) +
      (issueFrom.isNotEmpty || issueTo.isNotEmpty ? 1 : 0) +
      (dueFrom.isNotEmpty || dueTo.isNotEmpty ? 1 : 0) +
      (totalMin.isNotEmpty || totalMax.isNotEmpty ? 1 : 0);

  InvoiceFilters copyWith({
    String? number,
    String? seller,
    String? buyer,
    String? currency,
    String? typeCode,
    String? format,
    String? paymentMeansCode,
    String? createdFrom,
    String? createdTo,
    String? issueFrom,
    String? issueTo,
    String? dueFrom,
    String? dueTo,
    String? totalMin,
    String? totalMax,
  }) => InvoiceFilters(
    number: number ?? this.number,
    seller: seller ?? this.seller,
    buyer: buyer ?? this.buyer,
    currency: currency ?? this.currency,
    typeCode: typeCode ?? this.typeCode,
    format: format ?? this.format,
    paymentMeansCode: paymentMeansCode ?? this.paymentMeansCode,
    createdFrom: createdFrom ?? this.createdFrom,
    createdTo: createdTo ?? this.createdTo,
    issueFrom: issueFrom ?? this.issueFrom,
    issueTo: issueTo ?? this.issueTo,
    dueFrom: dueFrom ?? this.dueFrom,
    dueTo: dueTo ?? this.dueTo,
    totalMin: totalMin ?? this.totalMin,
    totalMax: totalMax ?? this.totalMax,
  );

  InvoiceFilters withValue(InvoiceFilterField field, String value) =>
      switch (field) {
        InvoiceFilterField.number => copyWith(number: value),
        InvoiceFilterField.seller => copyWith(seller: value),
        InvoiceFilterField.buyer => copyWith(buyer: value),
        InvoiceFilterField.currency => copyWith(currency: value),
        InvoiceFilterField.typeCode => copyWith(typeCode: value),
        InvoiceFilterField.format => copyWith(format: value),
        InvoiceFilterField.paymentMeansCode => copyWith(
          paymentMeansCode: value,
        ),
      };

  bool matches(InvoiceFilters other) =>
      InvoiceFilterField.values.every(
        (field) => value(field) == other.value(field),
      ) &&
      createdFrom == other.createdFrom &&
      createdTo == other.createdTo &&
      issueFrom == other.issueFrom &&
      issueTo == other.issueTo &&
      dueFrom == other.dueFrom &&
      dueTo == other.dueTo &&
      totalMin == other.totalMin &&
      totalMax == other.totalMax;

  String? get validation {
    for (final (label, from, to) in [
      ('Added', createdFrom, createdTo),
      ('Issue date', issueFrom, issueTo),
      ('Due date', dueFrom, dueTo),
    ]) {
      if (!_validDate(from) || !_validDate(to)) {
        return '$label: use a valid date in YYYY-MM-DD format.';
      }
      if (from.isNotEmpty && to.isNotEmpty && from.compareTo(to) > 0) {
        return '$label: the start must be on or before the end.';
      }
    }
    if (totalMin.isNotEmpty || totalMax.isNotEmpty) {
      if (currency.isEmpty) return 'Choose a currency for the total range.';
      for (final amount in [totalMin, totalMax]) {
        if (amount.isNotEmpty &&
            !RegExp(r'^-?(0|[1-9][0-9]{0,23})(\.[0-9]{1,12})?$')
                .hasMatch(amount)) {
          return 'Use a decimal total, for example 119.00, without separators.';
        }
      }
      if (totalMin.isNotEmpty &&
          totalMax.isNotEmpty &&
          compareDecimals(totalMin, totalMax) > 0) {
        return 'The minimum total must be no greater than the maximum.';
      }
    }
    return null;
  }

  static bool _validDate(String value) {
    if (value.isEmpty) return true;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final date = DateTime.tryParse(value);
    return date != null &&
        date.year >= 1 &&
        date.toIso8601String().substring(0, 10) == value;
  }

  static int compareDecimals(String left, String right) {
    final leftParts = left.split('.');
    final rightParts = right.split('.');
    final leftFraction = leftParts.length == 2 ? leftParts[1] : '';
    final rightFraction = rightParts.length == 2 ? rightParts[1] : '';
    final scale = leftFraction.length > rightFraction.length
        ? leftFraction.length
        : rightFraction.length;
    final leftValue = BigInt.parse(
      '${leftParts[0]}${leftFraction.padRight(scale, '0')}',
    );
    final rightValue = BigInt.parse(
      '${rightParts[0]}${rightFraction.padRight(scale, '0')}',
    );
    return leftValue.compareTo(rightValue);
  }
}

final class InvoiceFilterValuePage {
  InvoiceFilterValuePage({required Iterable<String> items, this.nextCursor})
    : items = List.unmodifiable(items);
  final List<String> items;
  final String? nextCursor;
}
