import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = catalogCases();

  test('every catalog entry has a unique stable identity and widget owner', () {
    expect(cases, isNotEmpty);
    expect(cases.map((entry) => entry.id).toSet().length, cases.length);
    final paths = <String>{};
    for (final entry in cases) {
      expect(entry.id, matches(RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')));
      expect(entry.widgetType, isNotEmpty, reason: entry.id);
      expect(entry.domain, isNotEmpty, reason: entry.id);
      expect(entry.component, isNotEmpty, reason: entry.id);
      expect(entry.name, isNotEmpty, reason: entry.id);
      expect(
        paths.add('${entry.domain}/${entry.component}/${entry.name}'),
        isTrue,
      );
    }
  });

  for (final entry in cases) {
    for (final dark in [false, true]) {
      for (final size in const [
        Size(1440, 900),
        Size(800, 600),
        Size(390, 844),
      ]) {
        testWidgets('${entry.id} ${dark ? 'dark' : 'light'} ${size.width}', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            CatalogPreview(entry: entry, dark: dark, reduceMotion: true),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
    testWidgets('${entry.id} supports enlarged text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(entry: entry, textScale: 2, reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
