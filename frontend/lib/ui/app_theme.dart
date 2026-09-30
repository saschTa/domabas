import 'package:flutter/material.dart';

abstract final class AppLayout {
  static const mobileBreakpoint = 600.0;
  static const desktopBreakpoint = 1100.0;

  static double pageInset(double width) => width < mobileBreakpoint
      ? 16
      : width < desktopBreakpoint
      ? 24
      : 32;

  static EdgeInsets cardListPadding(BuildContext context) {
    final inset = pageInset(MediaQuery.sizeOf(context).width);
    return EdgeInsets.fromLTRB(
      inset,
      16,
      inset,
      32 + MediaQuery.paddingOf(context).bottom,
    );
  }
}

enum AppElevation {
  control,
  panel,
  floating;

  List<BoxShadow> shadows(BuildContext context) => const [];

  static Color materialShadow(ColorScheme scheme) => Colors.transparent;
}

@immutable
final class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.documentCanvas,
  });

  final Color successContainer;
  final Color onSuccessContainer;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color documentCanvas;

  static const light = AppSemanticColors(
    successContainer: Color(0xFFE5DFD3),
    onSuccessContainer: Color(0xFF2C2925),
    warningContainer: Color(0xFFF1E3CA),
    onWarningContainer: Color(0xFF694912),
    documentCanvas: Color(0xFFE5E0D6),
  );
  static const dark = AppSemanticColors(
    successContainer: Color(0xFF3B3832),
    onSuccessContainer: Color(0xFFEEE8DC),
    warningContainer: Color(0xFF493A24),
    onWarningContainer: Color(0xFFF0D5A5),
    documentCanvas: Color(0xFF191917),
  );

  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppSemanticColors copyWith({
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? documentCanvas,
  }) => AppSemanticColors(
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    documentCanvas: documentCanvas ?? this.documentCanvas,
  );

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      documentCanvas: Color.lerp(documentCanvas, other.documentCanvas, t)!,
    );
  }
}

abstract final class AppTheme {
  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: Color(dark ? 0xFFDFA28F : 0xFFAD4433),
      onPrimary: Color(dark ? 0xFF34241F : 0xFFFFFDF7),
      primaryContainer: Color(dark ? 0xFF4A332C : 0xFFF0DCD3),
      onPrimaryContainer: Color(dark ? 0xFFF2DACE : 0xFF642F23),
      primaryFixed: const Color(0xFFF0DCD3),
      primaryFixedDim: const Color(0xFFDFA28F),
      onPrimaryFixed: const Color(0xFF34241F),
      onPrimaryFixedVariant: const Color(0xFF642F23),
      secondary: Color(dark ? 0xFFBFB6A7 : 0xFF675F55),
      onSecondary: Color(dark ? 0xFF2C2925 : 0xFFFFFDF7),
      secondaryContainer: Color(dark ? 0xFF3B3832 : 0xFFE5DFD3),
      onSecondaryContainer: Color(dark ? 0xFFEEE8DC : 0xFF2C2925),
      secondaryFixed: const Color(0xFFE5DFD3),
      secondaryFixedDim: const Color(0xFFBFB6A7),
      onSecondaryFixed: const Color(0xFF2C2925),
      onSecondaryFixedVariant: const Color(0xFF514B42),
      tertiary: Color(dark ? 0xFFBFB6A7 : 0xFF675F55),
      onTertiary: Color(dark ? 0xFF2C2925 : 0xFFFFFDF7),
      tertiaryContainer: Color(dark ? 0xFF3B3832 : 0xFFE5DFD3),
      onTertiaryContainer: Color(dark ? 0xFFEEE8DC : 0xFF2C2925),
      tertiaryFixed: const Color(0xFFE5DFD3),
      tertiaryFixedDim: const Color(0xFFBFB6A7),
      onTertiaryFixed: const Color(0xFF2C2925),
      onTertiaryFixedVariant: const Color(0xFF514B42),
      error: Color(dark ? 0xFFF2AAA0 : 0xFFA3332C),
      onError: Color(dark ? 0xFF451914 : 0xFFFFFDF7),
      errorContainer: Color(dark ? 0xFF552A24 : 0xFFF5DDD6),
      onErrorContainer: Color(dark ? 0xFFF9DCD5 : 0xFF74261F),
      surface: Color(dark ? 0xFF2B2A27 : 0xFFFFFDF7),
      onSurface: Color(dark ? 0xFFEEE8DC : 0xFF2C2925),
      onSurfaceVariant: Color(dark ? 0xFFBFB6A7 : 0xFF675F55),
      outline: Color(dark ? 0xFFA49E92 : 0xFF81796C),
      outlineVariant: Color(dark ? 0xFF6D685D : 0xFFC6C0B4),
      surfaceContainerLowest: Color(dark ? 0xFF191917 : 0xFFFFFDF7),
      surfaceContainerLow: Color(dark ? 0xFF302F2B : 0xFFF5F1E8),
      surfaceContainer: Color(dark ? 0xFF35332E : 0xFFEFEAE0),
      surfaceContainerHigh: Color(dark ? 0xFF393630 : 0xFFE9E3D8),
      surfaceContainerHighest: Color(dark ? 0xFF3B3832 : 0xFFE5DFD3),
      surfaceDim: Color(dark ? 0xFF20201E : 0xFFE5DFD3),
      surfaceBright: Color(dark ? 0xFF3B3832 : 0xFFFFFDF7),
      inverseSurface: Color(dark ? 0xFFEEE8DC : 0xFF2C2925),
      onInverseSurface: Color(dark ? 0xFF2C2925 : 0xFFEEE8DC),
      inversePrimary: Color(dark ? 0xFFAD4433 : 0xFFDFA28F),
      surfaceTint: Colors.transparent,
      shadow: Colors.transparent,
      scrim: const Color(0xFF191816),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      extensions: [dark ? AppSemanticColors.dark : AppSemanticColors.light],
      scaffoldBackgroundColor: Color(dark ? 0xFF20201E : 0xFFEFEBE2),
      visualDensity: VisualDensity.standard,
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: 'DomabasSerif',
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: 'DomabasSerif',
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: 'DomabasSerif',
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -.3,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.45,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: AppElevation.materialShadow(scheme),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              side: BorderSide(color: scheme.outline, width: 1.5),
              backgroundColor: scheme.surfaceContainerLow,
              disabledBackgroundColor: scheme.surfaceContainerLow.withValues(
                alpha: .5,
              ),
              elevation: 0,
              shadowColor: AppElevation.materialShadow(scheme),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ).copyWith(
              side: WidgetStateProperty.fromMap({
                WidgetState.focused: BorderSide(
                  color: scheme.primary,
                  width: 2,
                ),
                WidgetState.disabled: BorderSide(color: scheme.outlineVariant),
                WidgetState.any: BorderSide(color: scheme.outline, width: 1.5),
              }),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: WidgetStateBorderSide.fromMap({
          WidgetState.focused: BorderSide(color: scheme.primary, width: 2),
          WidgetState.selected: BorderSide(color: scheme.primary, width: 2),
          WidgetState.any: BorderSide(color: scheme.outlineVariant, width: 2),
        }),
      ),
      toggleButtonsTheme: ToggleButtonsThemeData(
        borderColor: scheme.outlineVariant,
        disabledBorderColor: scheme.outlineVariant,
        selectedBorderColor: scheme.primary,
        borderWidth: 2,
        fillColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: WidgetStatePropertyAll(0),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: AppElevation.materialShadow(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shadowColor: AppElevation.materialShadow(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: AppElevation.materialShadow(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: WidgetStatePropertyAll(
            AppElevation.materialShadow(scheme),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outline, width: 1.5),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        linearMinHeight: 3,
      ),
    );
  }
}
