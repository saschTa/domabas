import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared workspace pages fill a 4K viewport with gutters', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AppPage(
            title: 'Jobs',
            child: SizedBox(key: Key('widePageContent')),
          ),
        ),
      ),
    );
    final content = tester.getRect(find.byKey(const Key('widePageContent')));
    expect(content.left, 32);
    expect(content.right, 3808);
    expect(tester.takeException(), isNull);
  });

  Future<void> viewport(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget app(Widget child, {double scale = 1}) => MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    ),
    home: child,
  );

  List<AppNavigationGroup> groups() => [
    AppNavigationGroup(
      id: 'documents',
      label: 'Documents',
      icon: Icons.folder_outlined,
      collapsible: false,
      items: const [
        AppNavigationItem(
          id: 'documents',
          label: 'Documents',
          icon: Icons.description_outlined,
          key: Key('documentsNavigation'),
        ),
      ],
    ),
    AppNavigationGroup(
      id: 'user-settings',
      compactLabel: 'Settings',
      label: 'User settings',
      icon: Icons.settings_outlined,
      items: const [
        AppNavigationItem(
          id: 'libraries',
          label: 'Libraries',
          icon: Icons.folder_outlined,
          key: Key('manageLibraries'),
        ),
        AppNavigationItem(
          id: 'password',
          label: 'Password',
          icon: Icons.password_outlined,
          key: Key('changePassword'),
        ),
      ],
    ),
  ];

  Widget shell({
    ValueChanged<String>? onSelected,
    VoidCallback? onLogout,
    Widget child = const Center(child: Text('Content')),
    String selectedId = 'documents',
    List<AppWorkspaceAction> actions = const [],
  }) => AppWorkspaceShell(
    groups: groups(),
    selectedId: selectedId,
    onSelected: onSelected ?? (_) {},
    libraryPicker: const Text(
      'A very long library name that still fits its workspace',
      key: Key('libraryPicker'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    accountLabel: 'very.long.account.email@example.test',
    onLogout: onLogout ?? () {},
    actions: actions,
    child: child,
  );

  testWidgets(
    'workspace keeps one row and exposes compact actions through More',
    (tester) async {
      await viewport(tester, const Size(320, 640));
      var activated = false;
      var loggedOut = false;
      await tester.pumpWidget(
        app(
          shell(
            onLogout: () => loggedOut = true,
            actions: [
              AppWorkspaceAction(
                id: 'workspaceAction',
                label: 'New document',
                icon: Icons.add,
                onPressed: () async {
                  activated = true;
                },
              ),
            ],
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('workspaceAction')), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('workspaceHeader'))).height,
        lessThanOrEqualTo(80),
      );
      expect(find.byKey(const Key('workspaceMore')), findsNothing);
      await tester.tap(find.byKey(const Key('navigation-more')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('workspaceAction')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('workspaceAction')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('workspaceAction')));
      expect(activated, isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-more')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('logout')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('logout')));
      expect(loggedOut, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop navigation is controlled and groups expand without pages',
    (tester) async {
      await viewport(tester, const Size(1440, 900));
      String? selected;
      var loggedOut = false;
      await tester.pumpWidget(
        app(
          shell(
            onSelected: (id) => selected = id,
            onLogout: () => loggedOut = true,
          ),
        ),
      );

      expect(find.byKey(const Key('openNavigation')), findsNothing);
      await tester.tap(find.byKey(const Key('manageLibraries')));
      expect(selected, 'libraries');
      expect(find.text('Content'), findsOneWidget);
      expect(find.byType(TabBarView), findsNothing);
      await tester.tap(find.text('User settings'));
      await tester.pump();
      expect(find.byKey(const Key('manageLibraries')), findsNothing);
      await tester.tap(find.text('User settings'));
      await tester.pump();
      expect(find.byKey(const Key('manageLibraries')), findsOneWidget);
      await tester.tap(find.byKey(const Key('logout')));
      expect(loggedOut, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet rail exposes nested destinations with selected semantics',
    (tester) async {
      await viewport(tester, const Size(900, 720));
      final semantics = tester.ensureSemantics();
      String? selected;
      await tester.pumpWidget(
        app(shell(selectedId: 'libraries', onSelected: (id) => selected = id)),
      );

      expect(find.byTooltip('User settings'), findsOneWidget);
      expect(find.byKey(const Key('manageLibraries')), findsNothing);
      await tester.tap(find.byTooltip('User settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manageLibraries')), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('changePassword')));
      await tester.pumpAndSettle();
      expect(selected, 'password');
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'mobile bottom navigation and page fit ${width.toInt()} pixels at 2x text',
      (tester) async {
        await viewport(tester, Size(width, 740));
        String? selected;
        await tester.pumpWidget(
          app(
            shell(
              onSelected: (id) => selected = id,
              child: AppPage(
                eyebrow: 'User settings',
                title: 'Library members',
                description: 'Manage people and their access to this library.',
                actions: [
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Invite member'),
                  ),
                ],
                child: AppSurface(
                  padding: EdgeInsets.zero,
                  child: ListView(
                    children: [
                      AppRecordRow(
                        title: 'long.member.email.address@example.test',
                        subtitle: const Text(
                          'A member with access to your documents',
                        ),
                        metadata: const AppStatusBadge(label: 'Viewer'),
                        trailing: OutlinedButton(
                          onPressed: () {},
                          child: const Text('Edit member'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            scale: 2,
          ),
        );

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('navigation-user-settings')),
        );
        await tester.tap(find.byKey(const Key('navigation-user-settings')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('manageLibraries')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('manageLibraries')));
        await tester.tap(find.byKey(const Key('manageLibraries')));
        await tester.pumpAndSettle();
        expect(selected, 'libraries');
        expect(find.byKey(const Key('manageLibraries')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('fixed page controls and empty state fit short windows', (
    tester,
  ) async {
    await viewport(tester, const Size(390, 320));
    await tester.pumpWidget(
      app(
        shell(
          child: AppPage(
            eyebrow: 'User settings',
            title: 'Library members',
            description: 'Manage people and their access to this library.',
            actions: [
              FilledButton(
                onPressed: () {},
                child: const Text('Invite member'),
              ),
            ],
            child: const AppSurface(
              child: AppEmptyState(
                icon: Icons.people_outline,
                title: 'No invitations',
                message: 'Invite someone to share documents in this library.',
              ),
            ),
          ),
        ),
        scale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wide dialog scrolls its body and wraps actions in a narrow viewport',
    (tester) async {
      await viewport(tester, const Size(320, 540));
      var submitted = false;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AppDialog(
                      title: 'Invite to this library',
                      description:
                          'Choose the permissions for this invitation.',
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => submitted = true,
                          child: const Text('Create invitation'),
                        ),
                      ],
                      child: Column(
                        children: [
                          for (var i = 0; i < 15; i++)
                            CheckboxListTile(
                              value: true,
                              onChanged: null,
                              title: Text('Permission $i'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  child: const Text('Open form'),
                ),
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Create invitation'));
      expect(submitted, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    },
  );

  testWidgets('record row keeps action separate from opening the record', (
    tester,
  ) async {
    await viewport(tester, const Size(1200, 600));
    var opened = 0;
    var edited = 0;
    final editFocus = FocusNode();
    addTearDown(editFocus.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: AppSurface(
            child: AppRecordRow(
              title: 'Example record',
              onTap: () => opened++,
              trailing: IconButton(
                focusNode: editFocus,
                tooltip: 'Edit record',
                onPressed: () => edited++,
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Edit record'));
    expect(edited, 1);
    expect(opened, 0);
    await tester.tap(find.text('Example record'));
    expect(opened, 1);
    editFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(edited, 2);
  });
}
