import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'desktop_cases.dart';
import 'native_reference_cases.dart';
export 'native_reference_cases.dart';

List<CatalogCase> nativeCases() => [
  CatalogCase(
    id: 'native-linux-leading-close-only',
    domain: 'Native platform preferences',
    component: 'Linux caption layout',
    name: 'Leading Close only',
    widgetType: 'GlacierNativeFrame',
    builder: (_) => const _NativeExample(
      spec: {
        'platform': 'linux',
        'query': {'platform': 'linux', 'layout': 'close-only-left'},
      },
    ),
  ),
  for (final spec in nativeReferenceCases)
    CatalogCase(
      id: spec['id']! as String,
      domain: 'Native ${spec['platform']}',
      component: 'Dedicated native frame',
      name: spec['state']! as String,
      widgetType: 'GlacierNativeFrame',
      nativeCase: spec['id']! as String,
      builder: (_) => _NativeExample(spec: spec),
    ),
  for (final entry in const <(String, String)>[
    ('window-frame', 'GlacierNativeFrame'),
    ('caption-controls', 'GlacierNativeCaptionControls'),
    ('drag-layout', 'GlacierNativeDragRegion'),
    ('compact-navigation', 'GlacierNativeCompactNavigation'),
    ('window-command-state', 'GlacierNativeCommandFeedback'),
    ('preview-controls', 'NativePreviewControls'),
  ])
    CatalogCase(
      id: 'native-component-${entry.$1}',
      domain: 'Native components',
      component: entry.$1,
      name: 'Contract',
      widgetType: entry.$2,
      nativeComponent: entry.$1,
      builder: (context) => _NativeComponent(id: entry.$1),
    ),
  for (final entry in const <(String, String)>[
    ('titlebar', 'GlacierNativeTitleBar'),
    ('workspace-geometry', 'GlacierWorkspaceGeometry'),
    ('presentation-scope', 'GlacierNativePresentationScope'),
    ('content-insets', 'GlacierNativeContentInsets'),
  ])
    CatalogCase(
      id: 'native-context-${entry.$1}',
      domain: 'Native contexts',
      component: entry.$2,
      name: 'Frame and toolbar integration',
      widgetType: entry.$2,
      builder: (_) => entry.$1 == 'titlebar'
          ? const _NativeComponent(id: 'titlebar')
          : _NativeExample(
              spec: nativeReferenceCases.firstWhere(
                (s) => s['id'] == 'native-linux-left-controls',
              ),
            ),
    ),
  for (final entry in const <(String, String)>[
    ('native-compact-navigation-open', 'native-windows-minimum-330'),
    ('native-caption-maximize-focus', 'native-windows-compact-800'),
    ('native-modal-close-request', 'native-windows-reader'),
  ])
    CatalogCase(
      id: entry.$1,
      domain: 'Native interactions',
      component: 'Window and app ownership',
      name: entry.$1,
      widgetType: 'GlacierNativeFrame',
      nativeInteraction: entry.$1,
      builder: (_) => _NativeExample(
        spec: nativeReferenceCases.firstWhere((s) => s['id'] == entry.$2),
        initialDrawerOpen: entry.$1 == 'native-compact-navigation-open',
      ),
    ),
];

class _NativeExample extends StatefulWidget {
  const _NativeExample({required this.spec, this.initialDrawerOpen = false});
  final Map<String, Object> spec;
  final bool initialDrawerOpen;
  @override
  State<_NativeExample> createState() => _NativeExampleState();
}

class _NativeExampleState extends State<_NativeExample> {
  late final query = Map<String, String>.from(widget.spec['query']! as Map);
  late GlacierNativeWindowState state = GlacierNativeWindowState(
    platform: GlacierNativePlatform.values.byName(
      widget.spec['platform']! as String,
    ),
    mode: GlacierNativeWindowMode.values.byName(query['mode'] ?? 'restored'),
    active: query['active'] != 'false',
    controlsRevealed: query['revealed'] == 'true',
    supportedCommands: query['disabled'] == 'true'
        ? {GlacierNativeCommand.close}
        : GlacierNativeCommand.values.toSet(),
    decoration: query['decoration'] == 'host'
        ? GlacierNativeDecoration.host
        : GlacierNativeDecoration.client,
    controlLayout: query['layout'] == 'close-only-left'
        ? GlacierNativeControlLayout.closeOnlyLeft
        : query['layout'] == 'left'
        ? GlacierNativeControlLayout.left
        : widget.spec['platform'] == 'linux' && query['layout'] != 'kde'
        ? GlacierNativeControlLayout.closeOnly
        : GlacierNativeControlLayout.standard,
    devicePixelRatio: double.tryParse(query['dpi'] ?? '') ?? 1,
    reduceMotion: query['motion'] == 'reduced',
    opaque: query['opaque'] == 'true',
  );
  String? feedback;
  GlacierNativeWindowLayout? layout;
  bool highlight = false;
  late final Widget workspace = desktopWorkspace(
    initialSelected: switch (query['view']) {
      'invoices' => 'invoice-collection',
      'jobs' => 'jobs-history',
      'chat' => 'chat-conversation',
      'settings' => 'settings-members',
      'admin' => 'settings-workload',
      _ => 'documents-grid',
    },
    initiallyCollapsed: query['sidebar'] == 'collapsed',
    initialDialog: query['screen'],
    onLibraryChanged: (library) =>
        setState(() => state = state.copyWith(library: library)),
  );
  void request(GlacierNativeCommand command) {
    setState(() {
      feedback = switch (command) {
        GlacierNativeCommand.close => 'Close requested. Review the open task before the host closes this window. This preview stays open.',
        GlacierNativeCommand.minimize =>
          'Minimize requested. Only the native host can minimize a window.',
        GlacierNativeCommand.titlebarDoubleClick =>
          'Native titlebar double-click requested; host preferences apply.',
        GlacierNativeCommand.systemMenu => 'System window menu requested; native event handling remains host-owned.',
        _ => '${glacierNativeCommandLabel(command)} callback received.',
      };
      if (command == GlacierNativeCommand.maximize) {
        state = state.copyWith(mode: GlacierNativeWindowMode.maximized);
      }
      if (command == GlacierNativeCommand.restore) {
        state = state.copyWith(mode: GlacierNativeWindowMode.restored);
      }
      if (command == GlacierNativeCommand.enterFullscreen) {
        state = state.copyWith(
          mode: GlacierNativeWindowMode.fullscreen,
          controlsRevealed: false,
        );
      }
      if (command == GlacierNativeCommand.exitFullscreen) {
        state = state.copyWith(
          mode: GlacierNativeWindowMode.restored,
          controlsRevealed: false,
        );
      }
    });
  }

  GlacierNativeWindowCommands get commands => GlacierNativeWindowCommands(
    onClose: () => request(GlacierNativeCommand.close),
    onMinimize: () => request(GlacierNativeCommand.minimize),
    onMaximize: () => request(GlacierNativeCommand.maximize),
    onRestore: () => request(GlacierNativeCommand.restore),
    onEnterFullscreen: () => request(GlacierNativeCommand.enterFullscreen),
    onExitFullscreen: () => request(GlacierNativeCommand.exitFullscreen),
    onTitlebarDoubleClick: () =>
        request(GlacierNativeCommand.titlebarDoubleClick),
    onSystemMenu: () => request(GlacierNativeCommand.systemMenu),
    onLayoutChanged: (value) => layout = value,
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: query['appearance'] == 'dark'
        ? GlacierTheme.dark(opaque: state.opaque)
        : GlacierTheme.light(opaque: state.opaque),
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
          double.tryParse(query['textScale'] ?? '') ??
              MediaQuery.textScalerOf(context).scale(1),
        ),
        disableAnimations: state.reduceMotion,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GlacierNativeFrame(
            state: state,
            commands: commands,
            feedback: feedback,
            initialDrawerOpen: widget.initialDrawerOpen,
            windowOverlay: Uri.base.queryParameters['preview'] == 'true'
                ? Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: NativePreviewControls(
                        state: state,
                        onPlatform: (value) => setState(
                          () => state = state.copyWith(
                            platform: value,
                            controlLayout: value == GlacierNativePlatform.linux
                                ? GlacierNativeControlLayout.closeOnly
                                : GlacierNativeControlLayout.standard,
                          ),
                        ),
                        onMode: (value) =>
                            setState(() => state = state.copyWith(mode: value)),
                        onActive: (value) => setState(
                          () => state = state.copyWith(active: value),
                        ),
                        onRegions: () => setState(() => highlight = !highlight),
                        onSystemMenu: () =>
                            request(GlacierNativeCommand.systemMenu),
                      ),
                    ),
                  )
                : null,
            child: workspace,
          ),
          if (highlight)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: GlacierNativeTitleBar.heightFor(
                context,
                state,
                MediaQuery.sizeOf(context).width,
              ),
              child: const IgnorePointer(
                child: ColoredBox(color: Color(0x3332A79E)),
              ),
            ),
        ],
      ),
    ),
  );
}

class NativePreviewControls extends StatefulWidget {
  const NativePreviewControls({
    super.key,
    required this.state,
    required this.onPlatform,
    required this.onMode,
    required this.onActive,
    required this.onRegions,
    required this.onSystemMenu,
  });
  final GlacierNativeWindowState state;
  final ValueChanged<GlacierNativePlatform> onPlatform;
  final ValueChanged<GlacierNativeWindowMode> onMode;
  final ValueChanged<bool> onActive;
  final VoidCallback onRegions, onSystemMenu;
  @override
  State<NativePreviewControls> createState() => _NativePreviewControlsState();
}

class _NativePreviewControlsState extends State<NativePreviewControls> {
  bool open = false;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (open)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlacierSurface(
            radius: 12,
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 56).clamp(0, 298),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Simulated frame controls · fictional data. Actual window movement, Snap, Spaces and host decoration stay native.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<GlacierNativePlatform>(
                    initialValue: widget.state.platform,
                    decoration: const InputDecoration(labelText: 'Platform'),
                    items: [
                      for (final p in GlacierNativePlatform.values)
                        DropdownMenuItem(value: p, child: Text(p.name)),
                    ],
                    onChanged: (p) {
                      if (p != null) widget.onPlatform(p);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<GlacierNativeWindowMode>(
                    initialValue: widget.state.mode,
                    decoration: const InputDecoration(
                      labelText: 'Window state',
                    ),
                    items: [
                      for (final mode in GlacierNativeWindowMode.values)
                        DropdownMenuItem(value: mode, child: Text(mode.name)),
                    ],
                    onChanged: (mode) {
                      if (mode != null) widget.onMode(mode);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<bool>(
                    initialValue: widget.state.active,
                    decoration: const InputDecoration(labelText: 'Activation'),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Active')),
                      DropdownMenuItem(value: false, child: Text('Inactive')),
                    ],
                    onChanged: (active) {
                      if (active != null) widget.onActive(active);
                    },
                  ),
                  const SizedBox(height: 12),
                  GlacierButton(
                    label: 'Show drag region',
                    onPressed: widget.onRegions,
                  ),
                  const SizedBox(height: 8),
                  GlacierButton(
                    label: 'System window menu',
                    onPressed: widget.onSystemMenu,
                  ),
                ],
              ),
            ),
          ),
        ),
      TextButton(
        onPressed: () => setState(() => open = !open),
        style: TextButton.styleFrom(
          backgroundColor: GlacierTokens.of(context).solid,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          side: BorderSide(color: GlacierTokens.of(context).border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 32),
        ),
        child: const Text('Window preview', style: TextStyle(fontSize: 11)),
      ),
    ],
  );
}

class _NativeComponent extends StatelessWidget {
  const _NativeComponent({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final state = GlacierNativeWindowState(
      platform: GlacierNativePlatform.windows,
    );
    final commands = GlacierNativeWindowCommands(
      onClose: () {},
      onMinimize: () {},
      onMaximize: () {},
      onSystemMenu: () {},
    );
    if (id == 'titlebar') {
      return Theme(
        data: Theme.of(context).copyWith(platform: TargetPlatform.windows),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              GlacierNativeTitleBar(state: state, commands: commands),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      );
    }
    if (id == 'window-frame' || id == 'compact-navigation') {
      return _NativeExample(
        spec: nativeReferenceCases.firstWhere(
          (s) =>
              s['id'] ==
              (id == 'compact-navigation'
                  ? 'native-windows-minimum-330'
                  : 'native-windows-documents-light'),
        ),
        initialDrawerOpen: id == 'compact-navigation',
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (id) {
          'caption-controls' => Align(
            alignment: Alignment.topRight,
            child: GlacierNativeCaptionControls(
              state: state,
              commands: commands,
            ),
          ),
          'drag-layout' => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 16,
                child: GlacierNativeDragRegion(
                  commands: commands,
                  highlight: true,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Blank titlebar candidate. Native resize edges and interactive controls take precedence.',
              ),
            ],
          ),
          'window-command-state' => const Align(
            alignment: Alignment.bottomRight,
            child: GlacierNativeCommandFeedback(
              message: 'Close requested. Review the open task before the host closes this window.',
            ),
          ),
          _ => Align(
            alignment: Alignment.bottomRight,
            child: NativePreviewControls(
              state: state,
              onPlatform: (_) {},
              onMode: (_) {},
              onActive: (_) {},
              onRegions: () {},
              onSystemMenu: () {},
            ),
          ),
        },
      ),
    );
  }
}
