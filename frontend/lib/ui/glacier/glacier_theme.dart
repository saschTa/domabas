import 'package:flutter/material.dart';

import '../app_theme.dart';

@immutable
class GlacierTokens extends ThemeExtension<GlacierTokens> {
  const GlacierTokens({
    required this.glass,
    required this.surface,
    required this.edge,
    required this.preview,
    required this.solid,
    required this.canvas,
    required this.muted,
    required this.accent,
    required this.border,
    required this.selectedNavigation,
    required this.onSelectedNavigation,
    this.opaque = false,
  });
  final Color glass,
      surface,
      edge,
      preview,
      solid,
      canvas,
      muted,
      accent,
      border;
  final Color selectedNavigation, onSelectedNavigation;
  final bool opaque;
  Color get choiceSelected => Color.lerp(solid, accent, .12)!;
  Color get choiceSelectedEdge => Color.lerp(solid, accent, .55)!;
  Color get choiceEdge => Color.lerp(solid, muted, .42)!;
  Color get choiceHover => Color.lerp(solid, accent, .06)!;
  Color get choiceLocked => Color.lerp(solid, muted, .08)!;
  static const light = GlacierTokens(
    glass: Color(0xA8F4FAF9),
    surface: Color(0xDEFFFFFF),
    edge: Color(0xB3FFFFFF),
    preview: Color(0xFFE8EEEC),
    solid: Color(0xFFF7FAF9),
    canvas: Color(0xFFDCE8EA),
    muted: Color(0xFF53676D),
    accent: Color(0xFF176961),
    border: Color(0x2454717D),
    selectedNavigation: Color(0xFF1F434B),
    onSelectedNavigation: Color(0xFFFFFFFF),
  );
  static const dark = GlacierTokens(
    glass: Color(0xB8182F3B),
    surface: Color(0xEB132831),
    edge: Color(0x30BADFED),
    preview: Color(0xFF1E333C),
    solid: Color(0xFF162B35),
    canvas: Color(0xFF0C1720),
    muted: Color(0xFFB8CCD4),
    accent: Color(0xFF8AD5C9),
    border: Color(0x2EA6D2E1),
    selectedNavigation: Color(0xFFB2DFD7),
    onSelectedNavigation: Color(0xFF122F35),
  );
  static GlacierTokens of(BuildContext context) =>
      Theme.of(context).extension<GlacierTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  @override
  GlacierTokens copyWith({
    Color? glass,
    Color? surface,
    Color? edge,
    Color? preview,
    Color? solid,
    Color? canvas,
    Color? muted,
    Color? accent,
    Color? border,
    Color? selectedNavigation,
    Color? onSelectedNavigation,
    bool? opaque,
  }) => GlacierTokens(
    glass: glass ?? this.glass,
    surface: surface ?? this.surface,
    edge: edge ?? this.edge,
    preview: preview ?? this.preview,
    solid: solid ?? this.solid,
    canvas: canvas ?? this.canvas,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    border: border ?? this.border,
    selectedNavigation: selectedNavigation ?? this.selectedNavigation,
    onSelectedNavigation: onSelectedNavigation ?? this.onSelectedNavigation,
    opaque: opaque ?? this.opaque,
  );
  @override
  GlacierTokens lerp(GlacierTokens? other, double t) => other == null
      ? this
      : GlacierTokens(
          glass: Color.lerp(glass, other.glass, t)!,
          surface: Color.lerp(surface, other.surface, t)!,
          edge: Color.lerp(edge, other.edge, t)!,
          preview: Color.lerp(preview, other.preview, t)!,
          solid: Color.lerp(solid, other.solid, t)!,
          canvas: Color.lerp(canvas, other.canvas, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          border: Color.lerp(border, other.border, t)!,
          selectedNavigation: Color.lerp(
            selectedNavigation,
            other.selectedNavigation,
            t,
          )!,
          onSelectedNavigation: Color.lerp(
            onSelectedNavigation,
            other.onSelectedNavigation,
            t,
          )!,
          opaque: t < .5 ? opaque : other.opaque,
        );
}

abstract final class GlacierTheme {
  static ThemeData light({bool opaque = false}) =>
      _theme(Brightness.light, opaque);
  static ThemeData dark({bool opaque = false}) =>
      _theme(Brightness.dark, opaque);
  static ThemeData _theme(Brightness brightness, bool opaque) {
    final dark = brightness == Brightness.dark;
    final tokens = (dark ? GlacierTokens.dark : GlacierTokens.light).copyWith(
      opaque: opaque,
    );
    final base = dark ? AppTheme.dark() : AppTheme.light();
    final scheme = base.colorScheme.copyWith(
      primary: tokens.accent,
      onPrimary: Color(dark ? 0xFF102C2D : 0xFFFFFFFF),
      primaryContainer: Color(dark ? 0xFF1E3C42 : 0xFFDFEDE9),
      onPrimaryContainer: tokens.accent,
      primaryFixed: GlacierTokens.light.solid,
      primaryFixedDim: GlacierTokens.dark.accent,
      onPrimaryFixed: GlacierTokens.light.accent,
      onPrimaryFixedVariant: GlacierTokens.light.muted,
      inversePrimary: dark
          ? GlacierTokens.light.accent
          : GlacierTokens.dark.accent,
      secondary: tokens.muted,
      onSecondary: tokens.solid,
      secondaryContainer: Color(dark ? 0xFF223B44 : 0xFFE2ECEC),
      onSecondaryContainer: Color(dark ? 0xFFE7F2F4 : 0xFF172C34),
      tertiary: tokens.accent,
      onTertiary: Color(dark ? 0xFF102C2D : 0xFFFFFFFF),
      tertiaryContainer: Color(dark ? 0xFF223B44 : 0xFFE2ECEC),
      onTertiaryContainer: Color(dark ? 0xFFB8CCD4 : 0xFF345A63),
      surface: tokens.solid,
      onSurface: Color(dark ? 0xFFE7F2F4 : 0xFF172C34),
      onSurfaceVariant: tokens.muted,
      outline: tokens.muted,
      outlineVariant: tokens.border,
      surfaceContainerLowest: tokens.canvas,
      surfaceContainerLow: tokens.solid,
      surfaceContainer: Color(dark ? 0xFF203640 : 0xFFEBF2F2),
      surfaceContainerHigh: Color(dark ? 0xFF29424B : 0xFFE3EDED),
      surfaceContainerHighest: Color(dark ? 0xFF344F58 : 0xFFD6E4E4),
    );
    final text = ThemeData(fontFamily: 'DMSans', colorScheme: scheme).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'DMSans',
    ).copyWith(
      visualDensity: VisualDensity.standard,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: text.copyWith(
        bodyMedium: text.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
          letterSpacing: 0,
        ),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.4,
          color: tokens.muted,
          letterSpacing: 0,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -.4,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        labelSmall: text.labelSmall?.copyWith(letterSpacing: 0, fontSize: 11),
        labelMedium: text.labelMedium?.copyWith(letterSpacing: 0),
        labelLarge: text.labelLarge?.copyWith(letterSpacing: 0),
      ),
      extensions: [
        tokens,
        AppSemanticColors(
          successContainer: scheme.primaryContainer,
          onSuccessContainer: scheme.primary,
          warningContainer: Color(dark ? 0xFF433725 : 0xFFF5ECD5),
          onWarningContainer: Color(dark ? 0xFFF0CE93 : 0xFF76561B),
          documentCanvas: Color(dark ? 0xFF20343D : 0xFFE8EFEF),
        ),
      ],
      inputDecorationTheme: InputDecorationTheme(
        errorMaxLines: 8,
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: TextStyle(color: tokens.muted),
        hintStyle: TextStyle(color: tokens.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(36, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: tokens.surface,
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(36, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          shape: shape,
          side: BorderSide(color: tokens.border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(36, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          shape: shape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.muted,
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.all(7),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: shape,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        shape: shape,
        side: WidgetStateBorderSide.fromMap({
          WidgetState.focused: BorderSide(color: scheme.primary, width: 2),
          WidgetState.selected: BorderSide(color: scheme.primary),
          WidgetState.any: BorderSide(color: tokens.border),
        }),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(shape),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.accent,
        selectionColor: tokens.accent.withValues(alpha: .25),
        selectionHandleColor: tokens.accent,
      ),
      dividerColor: tokens.border,
    );
  }
}
