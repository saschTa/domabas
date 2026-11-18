import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in catalogCases().where(
    (entry) => entry.mobile && entry.referenceScreen != null,
  )) {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      for (final setting in [
        (const Size(320, 740), 2.0),
        (const Size(768, 1024), 1.0),
      ]) {
        testWidgets(
          '${entry.id} $platform ${setting.$1.width} scale${setting.$2}',
          (tester) async {
            await tester.binding.setSurfaceSize(setting.$1);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              CatalogPreview(
                entry: entry,
                platform: platform,
                safeInsets: true,
                keyboard: entry.referenceState == 'keyboard',
                textScale: setting.$2,
                dark: platform == TargetPlatform.android,
                reduceMotion: true,
              ),
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
