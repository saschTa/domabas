// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoiceFilterValuePage {
  InvoiceFilterValuePage({
    this.items = const [],
    this.nextCursor,
  });

  List<String> items;

  String? nextCursor;

  @override
  bool operator ==(Object other) => identical(this, other) || other is InvoiceFilterValuePage &&
    _deepEquality.equals(other.items, items) &&
    other.nextCursor == nextCursor;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (items.hashCode) +
    (nextCursor == null ? 0 : nextCursor!.hashCode);

  @override
  String toString() => 'InvoiceFilterValuePage[items=$items, nextCursor=$nextCursor]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'items'] = this.items;
    if (this.nextCursor != null) {
      json[r'nextCursor'] = this.nextCursor;
    } else {
      json[r'nextCursor'] = null;
    }
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static InvoiceFilterValuePage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "InvoiceFilterValuePage[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "InvoiceFilterValuePage[items]" has a null value in JSON.');
        return true;
      }());

      return InvoiceFilterValuePage(
        items: json[r'items'] is Iterable
            ? (json[r'items'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        nextCursor: mapValueOfType<String>(json, r'nextCursor'),
      );
    }
    return null;
  }

  static List<InvoiceFilterValuePage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <InvoiceFilterValuePage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = InvoiceFilterValuePage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, InvoiceFilterValuePage> mapFromJson(dynamic json) {
    final map = <String, InvoiceFilterValuePage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = InvoiceFilterValuePage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<InvoiceFilterValuePage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<InvoiceFilterValuePage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = InvoiceFilterValuePage.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
  };
}
