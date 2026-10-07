import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    test('${theme.brightness} Studio chrome remains neutral', () {
      final scheme = theme.colorScheme;
      for (final color in [
        theme.scaffoldBackgroundColor,
        scheme.surface,
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        scheme.onSurfaceVariant,
        scheme.outlineVariant,
        theme.extension<AppSemanticColors>()!.documentCanvas,
      ]) {
        expect(color.r, color.g, reason: '$color has a chromatic tint');
        expect(color.g, color.b, reason: '$color has a chromatic tint');
      }
      expect(theme.textTheme.bodyMedium!.fontFamily, 'DMSans');
      expect(theme.textTheme.titleMedium!.fontFamily, 'DMSans');
      expect(theme.textTheme.headlineMedium!.fontFamily, 'BarlowCondensed');
      expect(theme.textTheme.headlineMedium!.fontWeight, FontWeight.w700);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.dialogTheme.elevation, 0);
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).side,
        BorderSide.none,
      );
    });
  }
}
