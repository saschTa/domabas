// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PaperlessOutcomePage {
  PaperlessOutcomePage({
    this.nextCursor,
    this.items = const [],
  });

  String? nextCursor;

  List<PaperlessOutcome> items;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PaperlessOutcomePage &&
    other.nextCursor == nextCursor &&
    _deepEquality.equals(other.items, items);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (nextCursor == null ? 0 : nextCursor!.hashCode) +
    (items.hashCode);

  @override
  String toString() => 'PaperlessOutcomePage[nextCursor=$nextCursor, items=$items]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.nextCursor != null) {
      json[r'nextCursor'] = this.nextCursor;
    } else {
      json[r'nextCursor'] = null;
    }
      json[r'items'] = this.items;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static PaperlessOutcomePage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'items'), 'Required key "PaperlessOutcomePage[items]" is missing from JSON.');
        assert(json[r'items'] != null, 'Required key "PaperlessOutcomePage[items]" has a null value in JSON.');
        return true;
      }());

      return PaperlessOutcomePage(
        nextCursor: mapValueOfType<String>(json, r'nextCursor'),
        items: PaperlessOutcome.listFromJson(json[r'items']),
      );
    }
    return null;
  }

  static List<PaperlessOutcomePage> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaperlessOutcomePage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaperlessOutcomePage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PaperlessOutcomePage> mapFromJson(dynamic json) {
    final map = <String, PaperlessOutcomePage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PaperlessOutcomePage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<PaperlessOutcomePage>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PaperlessOutcomePage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PaperlessOutcomePage.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'items',
  };
}
