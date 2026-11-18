import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/server/models/server_address.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/server_configuration_cubit.dart';

final class ServerConfigurationScreen extends StatefulWidget {
  const ServerConfigurationScreen({
    super.key,
    required this.cubit,
    this.onConnected,
  });

  final ServerConfigurationCubit cubit;
  final VoidCallback? onConnected;

  @override
  State<ServerConfigurationScreen> createState() =>
      _ServerConfigurationScreenState();
}

final class _ServerConfigurationScreenState
    extends State<ServerConfigurationScreen> {
  final _form = GlobalKey<FormState>();
  late final _address = TextEditingController(
    text: widget.cubit.state.address?.value ?? widget.cubit.initialAddress,
  );

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ServerConfigurationCubit, ServerConfigurationState>(
        bloc: widget.cubit,
        builder: (context, state) => AppPage(
          glacier: true,
          insetBody: false,
          showHeading: true,
          title: state.address == null ? 'Connect to your server' : 'Server',
          description: 'Enter the address of your Domabas installation.',
          child: SingleChildScrollView(
            padding: GlacierSettingsPage.scrollPadding(context),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AppSurface(
                  glacier: true,
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('serverAddress'),
                          controller: _address,
                          enabled: !state.busy && !state.loading,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.go,
                          decoration: const InputDecoration(
                            labelText: 'Server address',
                            hintText: 'https://documents.example.com',
                            helperText: 'Use HTTP or HTTPS. Include a port or base path if needed.',
                            helperMaxLines: 3,
                            errorMaxLines: 4,
                          ),
                          validator: (value) {
                            try {
                              ServerAddress.parse(value ?? '');
                              return null;
                            } on FormatException catch (failure) {
                              return failure.message;
                            }
                          },
                          onFieldSubmitted: (_) => _connect(),
                        ),
                        const SizedBox(height: 20),
                        if (state.address != null) ...[
                          const Text(
                            'Changing servers closes this workspace. Your sign-in and saved scans stay with their server.',
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (state.error case final error?) ...[
                          AppNotice(message: error),
                          const SizedBox(height: 16),
                        ],
                        if (state.busy) ...[
                          const AppStripedProgressIndicator(),
                          const SizedBox(height: 12),
                        ],
                        if (state.message case final message?) ...[
                          Semantics(liveRegion: true, child: Text(message)),
                          const SizedBox(height: 16),
                        ],
                        GlacierButton(
                          key: const Key('connectServer'),
                          onPressed: state.busy || state.loading
                              ? null
                              : _connect,
                          label: state.busy ? 'Connecting…' : 'Connect',
                          icon: Icons.dns_outlined,
                          kind: GlacierButtonKind.primary,
                        ),
                        if (state.address == null && state.error != null)
                          GlacierButton(
                            onPressed: state.busy ? null : widget.cubit.restore,
                            label: 'Reload saved server',
                            kind: GlacierButtonKind.quiet,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _connect() async {
    if (!_form.currentState!.validate()) return;
    final connected = await widget.cubit.connect(_address.text);
    if (mounted && connected) widget.onConnected?.call();
  }
}
