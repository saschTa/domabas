import 'dart:io';

import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every public Glacier widget has an isolated catalog registration', () {
    final publicWidget = RegExp(
      r'(?:final\s+)?class\s+(Glacier\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget|InheritedWidget)',
    );
    final expected = <String>{};
    for (final source
        in Directory('../lib/ui/glacier')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      expected.addAll(
        publicWidget
            .allMatches(source.readAsStringSync())
            .map((match) => match.group(1)!),
      );
    }
    final registered = catalogCases().map((entry) => entry.widgetType).toSet();
    expect(expected, isNotEmpty);
    expect(
      expected.difference(registered),
      isEmpty,
      reason: 'Every public presenter needs a named catalog example. Do not hide missing coverage in a broad screen story.',
    );
  });
  test('catalog fixtures do not leak into production UI', () {
    for (final source
        in Directory('../lib/ui/glacier')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final text = source.readAsStringSync();
      expect(
        text.contains('package:widgetbook/'),
        isFalse,
        reason: source.path,
      );
      expect(text.contains('catalog/'), isFalse, reason: source.path);
    }
  });
}
