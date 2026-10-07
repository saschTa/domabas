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
    successContainer: Color(0xFFEBEBEB),
    onSuccessContainer: Color(0xFF232323),
    warningContainer: Color(0xFFFFF1D6),
    onWarningContainer: Color(0xFF714A0C),
    documentCanvas: Color(0xFFEEEEEE),
  );
  static const dark = AppSemanticColors(
    successContainer: Color(0xFF363636),
    onSuccessContainer: Color(0xFFF0F0F0),
    warningContainer: Color(0xFF44351E),
    onWarningContainer: Color(0xFFF1D398),
    documentCanvas: Color(0xFF2C2C2C),
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
      primary: Color(dark ? 0xFFFF8869 : 0xFFB83E23),
      onPrimary: Color(dark ? 0xFF28170F : 0xFFFFFFFF),
      primaryContainer: Color(dark ? 0xFF392A22 : 0xFFFBEDE7),
      onPrimaryContainer: Color(dark ? 0xFFFF9C81 : 0xFF9E341D),
      primaryFixed: const Color(0xFFFBEDE7),
      primaryFixedDim: const Color(0xFFFF8869),
      onPrimaryFixed: const Color(0xFF28170F),
      onPrimaryFixedVariant: const Color(0xFF9E341D),
      secondary: Color(dark ? 0xFFABABAB : 0xFF686868),
      onSecondary: Color(dark ? 0xFF232323 : 0xFFFFFFFF),
      secondaryContainer: Color(dark ? 0xFF363636 : 0xFFEBEBEB),
      onSecondaryContainer: Color(dark ? 0xFFF0F0F0 : 0xFF232323),
      secondaryFixed: const Color(0xFFEBEBEB),
      secondaryFixedDim: const Color(0xFFABABAB),
      onSecondaryFixed: const Color(0xFF232323),
      onSecondaryFixedVariant: const Color(0xFF555555),
      tertiary: Color(dark ? 0xFFABABAB : 0xFF686868),
      onTertiary: Color(dark ? 0xFF232323 : 0xFFFFFFFF),
      tertiaryContainer: Color(dark ? 0xFF363636 : 0xFFEBEBEB),
      onTertiaryContainer: Color(dark ? 0xFFF0F0F0 : 0xFF232323),
      tertiaryFixed: const Color(0xFFEBEBEB),
      tertiaryFixedDim: const Color(0xFFABABAB),
      onTertiaryFixed: const Color(0xFF232323),
      onTertiaryFixedVariant: const Color(0xFF555555),
      error: Color(dark ? 0xFFFF978F : 0xFFAF332D),
      onError: Color(dark ? 0xFF3F1714 : 0xFFFFFFFF),
      errorContainer: Color(dark ? 0xFF4B2422 : 0xFFFCE7E5),
      onErrorContainer: Color(dark ? 0xFFFFDAD5 : 0xFF8F2823),
      surface: Color(dark ? 0xFF222222 : 0xFFFFFFFF),
      onSurface: Color(dark ? 0xFFF0F0F0 : 0xFF232323),
      onSurfaceVariant: Color(dark ? 0xFFABABAB : 0xFF686868),
      outline: const Color(0xFF858585),
      outlineVariant: Color(dark ? 0xFF373737 : 0xFFE5E5E5),
      surfaceContainerLowest: Color(dark ? 0xFF181818 : 0xFFFFFFFF),
      surfaceContainerLow: Color(dark ? 0xFF282828 : 0xFFFAFAFA),
      surfaceContainer: Color(dark ? 0xFF2C2C2C : 0xFFF5F5F5),
      surfaceContainerHigh: Color(dark ? 0xFF303030 : 0xFFEFEFEF),
      surfaceContainerHighest: Color(dark ? 0xFF363636 : 0xFFEBEBEB),
      surfaceDim: Color(dark ? 0xFF181818 : 0xFFEBEBEB),
      surfaceBright: Color(dark ? 0xFF363636 : 0xFFFFFFFF),
      inverseSurface: Color(dark ? 0xFFF0F0F0 : 0xFF232323),
      onInverseSurface: Color(dark ? 0xFF232323 : 0xFFF0F0F0),
      inversePrimary: Color(dark ? 0xFFB83E23 : 0xFFFF8869),
      surfaceTint: Colors.transparent,
      shadow: Colors.transparent,
      scrim: const Color(0xFF101010),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'DMSans',
    );
    return base.copyWith(
      extensions: [dark ? AppSemanticColors.dark : AppSemanticColors.light],
      scaffoldBackgroundColor: Color(dark ? 0xFF181818 : 0xFFF5F5F5),
      visualDensity: VisualDensity.standard,
      textTheme: base.textTheme.copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
        displayMedium: base.textTheme.displayMedium?.copyWith(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: 'BarlowCondensed',
          fontSize: 40,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
          height: 1.1,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: 'BarlowCondensed',
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
          height: 1.1,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: 'BarlowCondensed',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -.2,
          height: 1.15,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -.3,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -.1,
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
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
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
          side: BorderSide(color: scheme.outlineVariant),
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
              side: BorderSide(color: scheme.outlineVariant),
              foregroundColor: scheme.onSurface,
              backgroundColor: scheme.surface,
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
                WidgetState.any: BorderSide(color: scheme.outlineVariant),
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
          WidgetState.selected: BorderSide(color: scheme.primary),
          WidgetState.any: BorderSide(color: scheme.outlineVariant),
        }),
      ),
      toggleButtonsTheme: ToggleButtonsThemeData(
        borderColor: scheme.outlineVariant,
        disabledBorderColor: scheme.outlineVariant,
        selectedBorderColor: scheme.primary,
        borderWidth: 1,
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
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
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
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: AppElevation.materialShadow(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
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
            BorderSide(color: scheme.outlineVariant),
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
