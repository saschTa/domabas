import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/appearance/datasources/preferences_appearance_data_source.dart';
import '../data/appearance/repos/local_appearance_repository.dart';
import '../data/server/datasources/preferences_server_data_source.dart';
import '../data/server/datasources/readiness_server_data_source.dart';
import '../data/server/repos/local_server_repository.dart';
import '../domain/appearance/interfaces/appearance_repository.dart';
import '../domain/appearance/models/appearance_preference.dart';
import '../domain/server/interfaces/server_repository.dart';
import '../domain/server/models/server_address.dart';
import '../presentation/appearance/cubits/appearance_cubit.dart';
import '../presentation/appearance/widgets/appearance_action.dart';
import '../presentation/server/cubits/server_configuration_cubit.dart';
import '../presentation/server/views/server_configuration_screen.dart';
import '../ui/domabas_ui.dart';
import 'app_dependencies.dart';
import 'domabas_app.dart';
import 'http_client.dart';
import 'public_licenses_access.dart';

typedef ServerApplicationBuilder = Widget Function(
  ServerAddress address,
  ServerConfigurationCubit configuration,
  AppearanceCubit appearance,
);

final class NativeServerApp extends StatefulWidget {
  const NativeServerApp({
    super.key,
    required this.repository,
    required this.appearance,
    required this.applicationBuilder,
    this.initialAddress = '',
  });

  factory NativeServerApp.production() => NativeServerApp(
    repository: LocalServerRepository(
      PreferencesServerDataSource(),
      ReadinessServerDataSource(clientFactory: createHttpClient),
    ),
    appearance: LocalAppearanceRepository(PreferencesAppearanceDataSource()),
    initialAddress: const String.fromEnvironment('API_BASE_URL'),
    applicationBuilder: (address, configuration, appearance) =>
        _ServerApplication(
          address: address,
          configuration: configuration,
          appearance: appearance,
        ),
  );

  final ServerRepository repository;
  final AppearanceRepository appearance;
  final String initialAddress;
  final ServerApplicationBuilder applicationBuilder;

  @override
  State<NativeServerApp> createState() => _NativeServerAppState();
}

final class _NativeServerAppState extends State<NativeServerApp> {
  late final _configuration = ServerConfigurationCubit(
    widget.repository,
    initialAddress: widget.initialAddress,
  );
  late final _appearance = AppearanceCubit(widget.appearance);

  @override
  void initState() {
    super.initState();
    _appearance.restore();
    unawaited(_configuration.restore());
  }

  @override
  void dispose() {
    unawaited(_configuration.close());
    unawaited(_appearance.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ServerConfigurationCubit, ServerConfigurationState>(
        bloc: _configuration,
        buildWhen: (previous, current) =>
            previous.address != current.address ||
            previous.loading != current.loading,
        builder: (context, state) {
          if (state.address case final address?) {
            return KeyedSubtree(
              key: ValueKey(address),
              child: widget.applicationBuilder(
                address,
                _configuration,
                _appearance,
              ),
            );
          }
          return BlocBuilder<AppearanceCubit, AppearanceState>(
            bloc: _appearance,
            builder: (context, appearance) => MaterialApp(
              title: 'Domabas',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: switch (appearance.preference) {
                AppearancePreference.system => ThemeMode.system,
                AppearancePreference.light => ThemeMode.light,
                AppearancePreference.dark => ThemeMode.dark,
              },
              home: Scaffold(
                appBar: AppBar(
                  title: const Text('domabas'),
                  actions: [AppearanceAction(cubit: _appearance)],
                ),
                body: AppPaperCanvas(
                  child: SafeArea(
                    child: Column(
                      children: [
                        Expanded(
                          child: state.loading
                              ? const Center(child: CircularProgressIndicator())
                              : ServerConfigurationScreen(
                                  cubit: _configuration,
                                ),
                        ),
                        const PublicLicensesFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

final class _ServerApplication extends StatefulWidget {
  const _ServerApplication({
    required this.address,
    required this.configuration,
    required this.appearance,
  });

  final ServerAddress address;
  final ServerConfigurationCubit configuration;
  final AppearanceCubit appearance;

  @override
  State<_ServerApplication> createState() => _ServerApplicationState();
}

final class _ServerApplicationState extends State<_ServerApplication> {
  late final _dependencies = AppDependencies.production(
    baseUrl: widget.address.value,
  );

  @override
  void dispose() {
    _dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DomabasApp(
    appearance: _dependencies.appearance,
    appearanceCubit: widget.appearance,
    serverConfiguration: widget.configuration,
    auth: _dependencies.auth,
    uploads: _dependencies.uploads,
    shares: _dependencies.shares,
    authenticate: _dependencies.authenticate,
  );
}
