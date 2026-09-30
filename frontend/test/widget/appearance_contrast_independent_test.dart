import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    test(
      '${theme.brightness} semantic text and enabled controls meet contrast',
      () {
        final scheme = theme.colorScheme;
        final extra = theme.extension<AppSemanticColors>()!;
        for (final (label, foreground, background) in [
          ('body', scheme.onSurface, scheme.surface),
          ('canvas body', scheme.onSurface, theme.scaffoldBackgroundColor),
          ('muted', scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
          ('primary', scheme.onPrimary, scheme.primary),
          ('selection', scheme.onPrimaryContainer, scheme.primaryContainer),
          ('secondary', scheme.onSecondary, scheme.secondary),
          (
            'secondary selection',
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ),
          ('tertiary', scheme.onTertiary, scheme.tertiary),
          (
            'tertiary selection',
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          ),
          ('error', scheme.onError, scheme.error),
          ('error notice', scheme.onErrorContainer, scheme.errorContainer),
          ('success', extra.onSuccessContainer, extra.successContainer),
          ('warning', extra.onWarningContainer, extra.warningContainer),
        ]) {
          expect(
            _contrast(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: label,
          );
        }
        final input = theme.inputDecorationTheme;
        for (final (label, border) in [
          ('focused input', input.focusedBorder!),
          ('invalid input', input.errorBorder!),
          ('focused invalid input', input.focusedErrorBorder!),
        ]) {
          expect(
            _contrast(border.borderSide.color, input.fillColor!),
            greaterThanOrEqualTo(3),
            reason: label,
          );
          expect(border.borderSide.width, greaterThanOrEqualTo(2));
        }
        expect(
          _contrast(scheme.onSurfaceVariant, input.fillColor!),
          greaterThanOrEqualTo(4.5),
          reason: 'filled input label',
        );
        final button = theme.outlinedButtonTheme.style!;
        final outlined = button.side!.resolve({WidgetState.focused})!;
        expect(
          _contrast(outlined.color, scheme.surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          _contrast(scheme.primary, button.backgroundColor!.resolve({})!),
          greaterThanOrEqualTo(4.5),
          reason: 'secondary action label',
        );
        expect(
          _contrast(scheme.primary, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(3),
        );
      },
    );

    testWidgets(
      '${theme.brightness} rendered status badges and notices retain readable pairs',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  for (final tone in AppTone.values) ...[
                    AppStatusBadge(label: 'badge-${tone.name}', tone: tone),
                    AppNotice(message: 'notice-${tone.name}', tone: tone),
                  ],
                ],
              ),
            ),
          ),
        );
        for (final tone in AppTone.values) {
          for (final prefix in ['badge', 'notice']) {
            final text = find.text('$prefix-${tone.name}');
            final widget = tester.widget<Text>(text);
            final foreground =
                widget.style?.color ??
                DefaultTextStyle.of(tester.element(text)).style.color!;
            final container = tester
                .widgetList<Container>(
                  find.ancestor(of: text, matching: find.byType(Container)),
                )
                .firstWhere(
                  (value) =>
                      value.decoration is BoxDecoration &&
                      (value.decoration! as BoxDecoration).color != null,
                );
            final background = (container.decoration! as BoxDecoration).color!;
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: '$prefix ${tone.name}',
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
