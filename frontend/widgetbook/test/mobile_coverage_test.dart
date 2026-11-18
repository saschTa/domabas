import 'dart:convert';
import 'dart:io';

import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepted mobile reference has every exact screen state and component context', () {
    final manifest = jsonDecode(
      File('test/fixtures/glacier_mobile_reference.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final screens = manifest['screens'] as List;
    final expected = {
      for (final screen in screens)
        for (final state in screen['states'] as List)
          'mobile-${screen['id']}-${state['id']}',
    };
    final cases = catalogCases().where((entry) => entry.mobile).toList();
    final actual = {
      for (final entry in cases.where((entry) => entry.referenceScreen != null))
        entry.id,
    };
    expect(screens, hasLength(42));
    expect(expected, hasLength(176));
    expect(actual, expected);
    final expectedComponents = {
      for (final component in manifest['components'] as List)
        component['id'] as String,
    };
    final mapped = {
      for (final entry in cases)
        if (entry.referenceComponent != null) entry.referenceComponent!,
    };
    expect(expectedComponents, hasLength(45));
    expect(
      expectedComponents.difference(mapped),
      isEmpty,
      reason: 'Every reference component needs a named component example.',
    );
    expect(
      mapped.difference(expectedComponents),
      isEmpty,
      reason: 'Reference mappings must use accepted component IDs.',
    );
  });
}
