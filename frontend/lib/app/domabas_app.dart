import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/appearance/interfaces/appearance_repository.dart';
import '../domain/appearance/models/appearance_preference.dart';
import '../presentation/appearance/cubits/appearance_cubit.dart';
import '../presentation/appearance/widgets/appearance_action.dart';
import '../presentation/server/cubits/server_configuration_cubit.dart';
import '../presentation/server/views/server_configuration_screen.dart';

import '../domain/identity/models/identity.dart';
import '../domain/identity/interfaces/identity_repository.dart';
import '../presentation/identity/views/auth_screen.dart';
import '../presentation/document/widgets/document_route_scope.dart';
import '../presentation/identity/cubits/session_cubit.dart';
import '../ui/domabas_ui.dart';
import 'account_workspace.dart';
import 'app_dependencies.dart';
import 'document_upload_coordinator.dart';
import 'public_licenses_access.dart';
import '../presentation/document/widgets/document_upload_host.dart';

final class DomabasApp extends StatefulWidget {
  const DomabasApp({
    super.key,
    required this.auth,
    required this.authenticate,
    required this.appearance,
    this.appearanceCubit,
    this.serverConfiguration,
    this.uploads,
  });

  final AuthRepository auth;
  final DocumentUploadCoordinator? uploads;
  final AppearanceRepository appearance;
  final AppearanceCubit? appearanceCubit;
  final ServerConfigurationCubit? serverConfiguration;
  final AuthenticatedDependencies Function(AuthSession, VoidCallback)
  authenticate;

  @override
  State<DomabasApp> createState() => _DomabasAppState();
}

final class _DomabasAppState extends State<DomabasApp>
    with WidgetsBindingObserver {
  late final AppearanceCubit _appearance;
  late final SessionCubit _sessions;
  late final StreamSubscription<SessionState> _sessionSubscription;
  AuthSession? _session;
  AuthenticatedDependencies? _scope;
  final Set<AuthenticatedDependencies> _retiring = {};
  RouteObserver<ModalRoute<void>> _documentRoutes =
      RouteObserver<ModalRoute<void>>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.uploads?.lifecycleChanged(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
    _appearance =
        widget.appearanceCubit ??
        (AppearanceCubit(widget.appearance)..restore());
    _sessions = SessionCubit(widget.auth);
    _sessionSubscription = _sessions.stream.listen(_changed);
    unawaited(_sessions.restore());
  }

  void _changed(SessionState state) {
    if (!mounted) return;
    final session = state.session;
    if (!identical(_session, session)) {
      final previous = _scope;
      if (previous != null && !_retiring.contains(previous)) previous.dispose();
      _session = session;
      _documentRoutes = RouteObserver<ModalRoute<void>>();
      _scope = session == null
          ? null
          : widget.authenticate(session, () {
              if (identical(_session, session)) _scope?.cancelDocuments();
              _sessions.endSession(
                session,
                'Your session ended. Please sign in again.',
              );
            });
    }
    widget.uploads?.attach(_scope?.uploads, busy: state.busy);
    setState(() {});
  }

  Future<void> _logout() async {
    final scope = _scope;
    if (scope == null) return;
    scope.cancelDocuments();
    _retiring.add(scope);
    try {
      await _sessions.logout(scope.identity);
    } finally {
      _retiring.remove(scope);
      scope.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.uploads?.lifecycleChanged(state);

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.appearanceCubit == null) unawaited(_appearance.close());
    unawaited(_sessionSubscription.cancel());
    unawaited(_sessions.close());
    _scope?.dispose();
    for (final scope in _retiring) {
      scope.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessibility =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final reduceMotion =
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
        accessibility.disableAnimations ||
        accessibility.reduceMotion;
    return BlocBuilder<AppearanceCubit, AppearanceState>(
      bloc: _appearance,
      builder: (context, state) => DocumentRouteScope(
        observer: _documentRoutes,
        child: MaterialApp(
          key: ObjectKey(_session),
          title: 'Domabas',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [_documentRoutes],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: switch (state.preference) {
            AppearancePreference.system => ThemeMode.system,
            AppearancePreference.light => ThemeMode.light,
            AppearancePreference.dark => ThemeMode.dark,
          },
          themeAnimationStyle: reduceMotion
              ? AnimationStyle.noAnimation
              : const AnimationStyle(duration: Duration(milliseconds: 200)),
          builder: (context, child) => DocumentUploadHost(
            cubit: _scope?.uploads,
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(builder: _home),
        ),
      ),
    );
  }

  Widget _home(BuildContext context) {
    if (_sessions.restoring || _sessions.restoreFailed) {
      return Scaffold(
        appBar: AppBar(
          actions: [
            ?_serverAction(context),
            AppearanceAction(cubit: _appearance),
          ],
        ),
        body: AppPaperCanvas(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: AppSurface(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _sessions.restoring
                                    ? 'Opening your library…'
                                    : _sessions.forgetFailed
                                    ? 'Finish signing out'
                                    : 'Reconnect to your library',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              if (_sessions.restoring)
                                const AppStripedProgressIndicator()
                              else ...[
                                Text(_sessions.error ?? 'Please try again.'),
                                const SizedBox(height: 24),
                                FilledButton(
                                  key: const Key('retrySession'),
                                  onPressed: _sessions.busy
                                      ? null
                                      : _sessions.forgetFailed
                                      ? _sessions.forgetSavedSession
                                      : _sessions.restore,
                                  child: const Text('Try again'),
                                ),
                                if (!_sessions.forgetFailed)
                                  TextButton(
                                    key: const Key('forgetSession'),
                                    onPressed: _sessions.busy
                                        ? null
                                        : _sessions.forgetSavedSession,
                                    child: const Text(
                                      'Sign out on this device',
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const PublicLicensesFooter(),
              ],
            ),
          ),
        ),
      );
    }
    final session = _session;
    return session == null
        ? AuthScreen(
            cubit: _sessions,
            appearanceAction: AppearanceAction(cubit: _appearance),
            serverAction: _serverAction(context),
            serverAddress: widget.serverConfiguration?.state.address?.value,
            footer: const PublicLicensesFooter(),
          )
        : AppearanceAction(
            cubit: _appearance,
            builder: (context, action) => AccountWorkspace(
              appearanceWorkspaceAction: action,
              appearanceAction: AppearanceAction(cubit: _appearance),
              serverAction: _serverAction(context),
              serverSettings: widget.serverConfiguration == null
                  ? null
                  : ServerConfigurationScreen(
                      cubit: widget.serverConfiguration!,
                    ),
              onUpload: _scope?.uploads == null
                  ? null
                  : () => widget.uploads?.choose(_scope!.uploads!),
              session: session,
              dependencies: _scope!,
              onLogout: _logout,
              onSessionEnded: (message) =>
                  _sessions.endSession(session, message),
              onSwitch: (id) async {
                final scope = _scope;
                if (scope == null || !identical(_session, session)) {
                  return 'Your session ended.';
                }
                final switched = await _sessions.switchAccount(
                  scope.identity,
                  id,
                );
                return switched
                    ? null
                    : _sessions.error ??
                          'Unable to switch libraries. Please sign in again.';
              },
            ),
          );
  }

  Widget? _serverAction(BuildContext context) {
    final configuration = widget.serverConfiguration;
    if (configuration == null) return null;
    return TextButton.icon(
      key: const Key('configureServer'),
      icon: const Icon(Icons.dns_outlined),
      label: const Text('Server'),
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (routeContext) =>
              BlocBuilder<ServerConfigurationCubit, ServerConfigurationState>(
                bloc: configuration,
                builder: (context, state) => PopScope(
                  canPop: !state.busy,
                  child: Scaffold(
                    appBar: AppBar(
                      title: const Text('Server'),
                      automaticallyImplyLeading: !state.busy,
                    ),
                    body: AppPaperCanvas(
                      child: SafeArea(
                        child: ServerConfigurationScreen(
                          cubit: configuration,
                          onConnected: () {
                            if (routeContext.mounted) {
                              Navigator.of(routeContext).pop();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
