import 'package:domabas/ui/glacier/glacier_theme.dart';
import 'package:domabas/ui/glacier/glacier_surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:widgetbook/widgetbook.dart';

import 'catalog/catalog.dart';
import 'catalog/catalog_case.dart';
import 'catalog/mobile_catalog.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['DM Sans'],
      await rootBundle.loadString(
        'packages/domabas/assets/licenses/dmsans-ofl.txt',
      ),
    );
    yield LicenseEntryWithLineBreaks(
      ['Barlow Condensed'],
      await rootBundle.loadString(
        'packages/domabas/assets/licenses/barlow-ofl.txt',
      ),
    );
  });
  runApp(const DomabasWidgetbook());
}

final class DomabasWidgetbook extends StatelessWidget {
  const DomabasWidgetbook({super.key});

  @override
  Widget build(BuildContext context) {
    final cases = catalogCases();
    final parameters = Uri.base.queryParameters;
    final selected = parameters['case'];
    if (selected != null) {
      final matches = cases.where((entry) => entry.id == selected);
      return CatalogPreview(
        entry: matches.firstOrNull,
        dark: parameters['appearance'] == 'dark',
        textScale: double.tryParse(parameters['textScale'] ?? '') ?? 1,
        reduceMotion: parameters['motion'] == 'reduced',
        opaque: parameters['opaque'] == 'true',
        platform: parameters['platform'] == 'android'
            ? TargetPlatform.android
            : TargetPlatform.iOS,
        safeInsets: parameters['safe'] != 'false',
        keyboard:
            parameters['keyboard'] == 'true' ||
            matches.firstOrNull?.referenceState == 'keyboard',
      );
    }
    return Widgetbook.material(
      directories: catalogDirectories(cases),
      lightTheme: GlacierTheme.light(),
      darkTheme: GlacierTheme.dark(),
      header: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Domabas · Glacier'),
      ),
      home: const Material(child: _CatalogHome()),
      addons: [
        ViewportAddon([
          Viewports.none,
          for (final size in const [
            Size(1440, 900),
            Size(1024, 768),
            Size(800, 600),
            Size(390, 844),
          ])
            ViewportData(
              name: '${size.width.toInt()} × ${size.height.toInt()}',
              width: size.width,
              height: size.height,
              pixelRatio: 1,
              platform: size.width < 600
                  ? TargetPlatform.iOS
                  : TargetPlatform.macOS,
            ),
        ]),
        MaterialThemeAddon(
          themes: [
            WidgetbookTheme(name: 'Light', data: GlacierTheme.light()),
            WidgetbookTheme(name: 'Dark', data: GlacierTheme.dark()),
            WidgetbookTheme(
              name: 'Light · opaque',
              data: GlacierTheme.light(opaque: true),
            ),
            WidgetbookTheme(
              name: 'Dark · opaque',
              data: GlacierTheme.dark(opaque: true),
            ),
          ],
        ),
        TextScaleAddon(min: 1, max: 2, divisions: 4, initialScale: 1),
        _CatalogMotionAddon(),
        _CatalogMobileHostAddon(),
      ],
    );
  }
}

final class CatalogPreview extends StatelessWidget {
  const CatalogPreview({
    super.key,
    required this.entry,
    this.dark = false,
    this.textScale = 1,
    this.reduceMotion = false,
    this.opaque = false,
    this.platform = TargetPlatform.iOS,
    this.safeInsets = true,
    this.keyboard = false,
  });

  final CatalogCase? entry;
  final bool dark;
  final double textScale;
  final bool reduceMotion;
  final bool opaque;
  final TargetPlatform platform;
  final bool safeInsets, keyboard;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark
        ? GlacierTheme.dark(opaque: opaque)
        : GlacierTheme.light(opaque: opaque),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale.clamp(1, 2)),
        disableAnimations: reduceMotion,
      ),
      child: MobileCatalogScope(
        routes: {for (final entry in catalogCases()) entry.id: entry.builder},
        child: child!,
      ),
    ),
    home: entry == null
        ? const Scaffold(body: Center(child: Text('Example not found')))
        : GlacierActivityBackdrop(
            atmosphere: true,
            child: entry!.mobile
                ? MobileCatalogEnvironment(
                    platform: platform,
                    safe: safeInsets,
                    keyboard: keyboard || entry!.referenceState == 'keyboard',
                    child: MobileCatalogHost(
                      child: Builder(builder: entry!.builder),
                    ),
                  )
                : Builder(builder: entry!.builder),
          ),
  );
}

final class _CatalogMobileHostAddon extends WidgetbookAddon<String> {
  _CatalogMobileHostAddon() : super(name: 'Mobile host');
  @override
  List<Field> get fields => [
    ObjectDropdownField<String>(
      name: 'Platform',
      values: const ['iOS', 'Android'],
      initialValue: 'iOS',
    ),
    BooleanField(name: 'Safe insets', initialValue: true),
    BooleanField(name: 'Keyboard', initialValue: false),
  ];
  @override
  String valueFromQueryGroup(Map<String, String> group) =>
      '${valueOf<String>('Platform', group) ?? 'iOS'}|${valueOf<bool>('Safe insets', group) ?? true}|${valueOf<bool>('Keyboard', group) ?? false}';
  @override
  Widget buildUseCase(BuildContext context, Widget child, String setting) {
    final values = setting.split('|');
    return MobileCatalogEnvironment(
      platform: values.first == 'Android'
          ? TargetPlatform.android
          : TargetPlatform.iOS,
      safe: values[1] == 'true',
      keyboard: values[2] == 'true',
      child: child,
    );
  }
}

final class _CatalogMotionAddon extends WidgetbookAddon<bool> {
  _CatalogMotionAddon() : super(name: 'Motion');

  @override
  List<Field> get fields => [
    BooleanField(name: 'Reduce motion', initialValue: false),
  ];

  @override
  bool valueFromQueryGroup(Map<String, String> group) =>
      valueOf<bool>('Reduce motion', group) ?? false;

  @override
  Widget buildUseCase(BuildContext context, Widget child, bool setting) =>
      MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: setting),
        child: child,
      );
}

final class _CatalogHome extends StatelessWidget {
  const _CatalogHome();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(40),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Glacier component library',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text(
              'Explore reusable Domabas components and complete desktop screens. '
              'Choose an example from the sidebar, then compare themes, '
              'window sizes and text scale using the controls.',
            ),
            const SizedBox(height: 24),
            const Text(
              'All documents, people and processing outcomes here are fictional. '
              'Examples run locally without an account or backend connection.',
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Domabas Glacier catalog',
                applicationVersion: 'Widgetbook 3.25.0',
              ),
              child: const Text('Catalog dependency licenses'),
            ),
          ],
        ),
      ),
    ),
  );
}
