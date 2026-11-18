import 'package:flutter/material.dart';
import 'package:domabas/ui/glacier.dart';

import 'catalog_case.dart';

CatalogCase mobileScreenCase({
  required String screen,
  required String state,
  required String title,
  required String widgetType,
  required WidgetBuilder builder,
  String domain = 'Mobile',
}) => CatalogCase(
  id: 'mobile-$screen-$state',
  domain: domain,
  component: title,
  name: state,
  widgetType: widgetType,
  builder: builder,
  mobile: true,
  referenceScreen: screen,
  referenceState: state,
);

CatalogCase mobileComponentCase({
  required String id,
  required String title,
  required String widgetType,
  required String referenceComponent,
  required WidgetBuilder builder,
  String domain = 'Mobile components',
}) => CatalogCase(
  id: 'mobile-component-$id',
  domain: domain,
  component: title,
  name: 'Reference',
  widgetType: widgetType,
  builder: builder,
  mobile: true,
  referenceComponent: referenceComponent,
);

class MobileCatalogSession extends ChangeNotifier {
  String library = 'Personal';
  String get libraryLabel =>
      library == 'Personal' ? 'Personal library' : library;
  void selectLibrary(String value) {
    if (library == value) return;
    library = value;
    notifyListeners();
  }
}

class MobileCatalogScope extends StatefulWidget {
  const MobileCatalogScope({
    super.key,
    required this.routes,
    required this.child,
    this.session,
  });
  final Map<String, WidgetBuilder> routes;
  final Widget child;
  final MobileCatalogSession? session;
  static MobileCatalogScopeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileCatalogScopeData>();
  @override
  State<MobileCatalogScope> createState() => _MobileCatalogScopeState();
}

class _MobileCatalogScopeState extends State<MobileCatalogScope> {
  late final MobileCatalogSession session =
      widget.session ?? MobileCatalogSession();
  @override
  void dispose() {
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileCatalogScopeData(
    routes: widget.routes,
    notifier: session,
    child: widget.child,
  );
}

class MobileCatalogScopeData extends InheritedNotifier<MobileCatalogSession> {
  const MobileCatalogScopeData({
    super.key,
    required this.routes,
    required super.notifier,
    required super.child,
  });
  final Map<String, WidgetBuilder> routes;
  MobileCatalogSession get session => notifier!;
}

String mobileCatalogLibrary(BuildContext context) =>
    MobileCatalogScope.maybeOf(context)?.session.library ?? 'Personal';
String mobileCatalogLibraryLabel(BuildContext context) =>
    MobileCatalogScope.maybeOf(context)?.session.libraryLabel ??
    'Personal library';

void mobileCatalogNavigate(
  BuildContext context,
  String screen, {
  String state = 'ready',
  Object? arguments,
}) {
  final scope = MobileCatalogScope.maybeOf(context);
  final routes = scope?.routes;
  final builder = routes?['mobile-$screen-$state'];
  if (builder == null) throw StateError('Missing mobile route: $screen/$state');
  final environment = MobileCatalogEnvironment.maybeOf(context);
  final theme = Theme.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(arguments: arguments),
      builder: (_) => MobileCatalogScope(
        routes: routes!,
        session: scope?.session,
        child: MobileCatalogEnvironment(
          platform: environment?.platform ?? theme.platform,
          safe: environment?.safe ?? true,
          keyboard: state == 'keyboard',
          child: Theme(
            data: theme,
            child: MobileCatalogHost(child: Builder(builder: builder)),
          ),
        ),
      ),
    ),
  );
}

Widget mobileCatalogShell(
  BuildContext context, {
  required String title,
  required Widget child,
  String subtitle = 'Personal library',
  String selectedId = 'documents',
  VoidCallback? onBack,
  List<Widget> actions = const [],
  Widget? footer,
  bool scrollable = true,
  bool showNavigation = true,
  bool showLibrary = true,
  bool insetBody = true,
  bool captureEnabled = true,
  bool activityBackground = true,
}) => GlacierMobileShell(
  title: title,
  subtitle: subtitle == 'Personal library'
      ? mobileCatalogLibraryLabel(context)
      : subtitle,
  selectedId: selectedId,
  onBack: onBack,
  footer: footer,
  actions: actions,
  scrollable: scrollable,
  showNavigation: showNavigation,
  insetBody: insetBody,
  activityLines: activityBackground ? _referenceActivityLines : const [],
  brand: Image.asset(
    'packages/domabas/assets/branding/domabas-mark.png',
    excludeFromSemantics: true,
  ),
  onLibrary: showLibrary
      ? () => mobileCatalogNavigate(context, 'library')
      : null,
  onSelected: (id) => mobileCatalogNavigate(context, id),
  destinations: [
    const GlacierMobileDestination(
      id: 'documents',
      label: 'Documents',
      icon: Icons.description_outlined,
    ),
    const GlacierMobileDestination(
      id: 'invoices',
      label: 'Invoices',
      icon: Icons.receipt_long_outlined,
    ),
    GlacierMobileDestination(
      id: 'capture',
      label: 'Scan',
      icon: Icons.document_scanner_outlined,
      enabled: captureEnabled,
      onAction: () => mobileCatalogNavigate(context, 'capture'),
    ),
    const GlacierMobileDestination(
      id: 'chat',
      label: 'Chat',
      icon: Icons.chat_bubble_outline,
    ),
    const GlacierMobileDestination(
      id: 'more',
      label: 'More',
      icon: Icons.more_horiz,
    ),
  ],
  child: child,
);

const _referenceActivityLines = [
  [
    Offset(-.025, .8),
    Offset(.1, .725),
    Offset(.2375, .775),
    Offset(.375, .575),
    Offset(.5125, .6125),
    Offset(.65, .425),
    Offset(.7875, .4875),
    Offset(1.025, .225),
  ],
  [
    Offset(-.025, .9),
    Offset(.1125, .8375),
    Offset(.25, .85),
    Offset(.3875, .7125),
    Offset(.525, .7625),
    Offset(.6625, .55),
    Offset(.8, .6125),
    Offset(1.025, .375),
  ],
];

class MobileCatalogEnvironment extends InheritedWidget {
  const MobileCatalogEnvironment({
    super.key,
    this.platform = TargetPlatform.iOS,
    this.safe = true,
    this.keyboard = false,
    required super.child,
  });
  final TargetPlatform platform;
  final bool safe, keyboard;
  static MobileCatalogEnvironment? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileCatalogEnvironment>();
  @override
  bool updateShouldNotify(MobileCatalogEnvironment oldWidget) =>
      platform != oldWidget.platform ||
      safe != oldWidget.safe ||
      keyboard != oldWidget.keyboard;
}

class MobileCatalogHost extends StatelessWidget {
  const MobileCatalogHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final environment = MobileCatalogEnvironment.maybeOf(context);
    final platform = environment?.platform ?? TargetPlatform.iOS;
    final keyboard = environment?.keyboard == true ? 280.0 : 0.0;
    final safe = environment?.safe != false
        ? EdgeInsets.only(
            top: platform == TargetPlatform.iOS ? 44 : 24,
            bottom: platform == TargetPlatform.iOS ? 34 : 24,
          )
        : EdgeInsets.zero;
    return Theme(
      data: glacierMobileTheme(Theme.of(context), platform: platform),
      child: LayoutBuilder(
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: constraints.biggest,
            viewPadding: safe,
            padding: EdgeInsets.only(
              top: safe.top,
              bottom: keyboard > 0 ? 0 : safe.bottom,
            ),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child,
        ),
      ),
    );
  }
}
