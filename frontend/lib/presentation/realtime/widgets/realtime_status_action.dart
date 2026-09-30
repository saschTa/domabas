import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/realtime/models/realtime.dart';
import '../../../ui/app_workspace_action.dart';
import '../cubits/realtime_cubit.dart';

final class RealtimeStatusAction extends StatelessWidget {
  const RealtimeStatusAction({super.key, required this.cubit, this.builder});
  final RealtimeCubit cubit;
  final AppWorkspaceActionBuilder? builder;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RealtimeCubit, RealtimeState>(
        bloc: cubit,
        builder: (context, state) {
          final message = switch (state.status) {
            RealtimeStatus.healthy => 'Live updates connected.',
            RealtimeStatus.connecting => 'Connecting live updates…',
            RealtimeStatus.inactive => 'Live updates paused.',
            _ => 'Live updates unavailable. Job progress will resume when reconnected.',
          };
          if (builder case final presenter?) {
            return presenter(
              context,
              AppWorkspaceAction(
                id: 'liveUpdatesStatus',
                label: 'Live updates',
                detail: message,
                icon: state.healthy
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                onPressed: () async {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(message)));
                },
              ),
            );
          }
          return IconButton(
            key: const Key('liveUpdatesStatus'),
            tooltip: message,
            icon: Icon(
              state.healthy
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
            onPressed: () =>
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message))),
          );
        },
      );
}
