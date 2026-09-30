import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/appearance/models/appearance_preference.dart';
import '../../../ui/app_appearance_menu.dart';
import '../../../ui/app_workspace_action.dart';
import '../cubits/appearance_cubit.dart';

final class AppearanceAction extends StatefulWidget {
  const AppearanceAction({super.key, required this.cubit, this.builder});

  final AppearanceCubit cubit;
  final AppWorkspaceActionBuilder? builder;

  @override
  State<AppearanceAction> createState() => _AppearanceActionState();
}

final class _AppearanceActionState extends State<AppearanceAction> {
  final FocusNode _focus = FocusNode();
  bool _open = false;

  Future<void> _show() async {
    if (_open) return;
    _open = true;
    final cubit = widget.cubit;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) =>
            BlocBuilder<AppearanceCubit, AppearanceState>(
              bloc: cubit,
              builder: (context, state) => AppAppearanceMenu(
                selectedId: state.preference.name,
                options: const [
                  AppAppearanceOption(
                    id: 'system',
                    label: 'System',
                    icon: Icons.brightness_auto_outlined,
                  ),
                  AppAppearanceOption(
                    id: 'light',
                    label: 'Light',
                    icon: Icons.light_mode_outlined,
                  ),
                  AppAppearanceOption(
                    id: 'dark',
                    label: 'Dark',
                    icon: Icons.dark_mode_outlined,
                  ),
                ],
                onSelected: (value) {
                  for (final preference in AppearancePreference.values) {
                    if (preference.name == value) {
                      cubit.select(preference);
                      return;
                    }
                  }
                },
                onClose: () => Navigator.of(dialogContext).pop(),
                statusMessage: _status(state),
                busy: state.restoring || state.saving,
                onRetry: state.canRetry ? cubit.retry : null,
              ),
            ),
      );
    } finally {
      _open = false;
      if (mounted &&
          widget.builder == null &&
          _focus.canRequestFocus &&
          ModalRoute.of(context)?.isCurrent == true) {
        _focus.requestFocus();
      }
    }
  }

  String? _status(AppearanceState state) => switch (state.issue) {
    AppearanceIssue.restoreUnavailable => 'Your saved appearance could not be loaded. You can choose a theme or retry.',
    AppearanceIssue.restorePending =>
      'Your saved appearance is still loading. You can choose a theme now.',
    AppearanceIssue.saveUnavailable =>
      'Your appearance could not be saved on this device. Retry to save it.',
    AppearanceIssue.savePending => 'Saving your appearance is still waiting. Your chosen theme stays active.',
    null =>
      state.restoring
          ? 'Loading saved appearance…'
          : state.saving
          ? 'Saving appearance…'
          : null,
  };

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AppearanceCubit, AppearanceState>(
        bloc: widget.cubit,
        builder: (context, state) {
          final (label, icon) = switch (state.preference) {
            AppearancePreference.system => (
              'System',
              Icons.brightness_auto_outlined,
            ),
            AppearancePreference.light => ('Light', Icons.light_mode_outlined),
            AppearancePreference.dark => ('Dark', Icons.dark_mode_outlined),
          };
          final status = state.issue == null ? null : _status(state);
          if (widget.builder case final builder?) {
            return builder(
              context,
              AppWorkspaceAction(
                id: 'appearance-action',
                label: 'Appearance',
                detail: status == null ? label : '$label. $status',
                icon: icon,
                badge: state.issue == null ? null : '!',
                onPressed: _show,
              ),
            );
          }
          return IconButton(
            key: const Key('appearance-action'),
            focusNode: _focus,
            tooltip: status == null
                ? 'Appearance: $label'
                : 'Appearance: $label. $status',
            onPressed: () => unawaited(_show()),
            icon: Badge(
              isLabelVisible: state.issue != null,
              label: const Text('!'),
              child: Icon(icon),
            ),
          );
        },
      );
}
