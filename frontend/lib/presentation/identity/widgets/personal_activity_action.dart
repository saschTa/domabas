import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/identity/models/personal_activity.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/personal_activity_cubit.dart';

final class PersonalActivityAction extends StatefulWidget {
  const PersonalActivityAction({
    super.key,
    required this.cubit,
    required this.namespaceId,
    required this.onOpen,
    this.builder,
  });
  final PersonalActivityCubit cubit;
  final String namespaceId;
  final Future<void> Function(PersonalActivityItem) onOpen;
  final AppWorkspaceActionBuilder? builder;
  @override
  State<PersonalActivityAction> createState() =>
      _IdentityPersonalActivityActionState();
}

final class _IdentityPersonalActivityActionState
    extends State<PersonalActivityAction> {
  DialogRoute<void>? _route;
  @override
  void dispose() {
    final route = _route;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
    super.dispose();
  }

  void _close() {
    final route = _route;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  Future<void> _openItem(PersonalActivityItem item) async {
    _close();
    if (mounted) {
      await widget.onOpen(item);
    }
  }

  Future<void> _show() async {
    if (_route != null) {
      return;
    }
    unawaited(widget.cubit.refresh());
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: BlocBuilder<PersonalActivityCubit, PersonalActivityState>(
            bloc: widget.cubit,
            builder: (context, state) => AppRefreshable(
              onRefresh: state.loading ? null : widget.cubit.refresh,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(20),
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Your jobs',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        key: const Key('personal-activity-close'),
                        tooltip: 'Close jobs',
                        onPressed: _close,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Text(
                    'Your work across libraries you can access. Automatic work without a recorded owner is not listed.',
                  ),
                  AppProgressSlot(active: state.loading),
                  if (state.error case final error?)
                    AppNotice(
                      message: error,
                      action: TextButton(
                        onPressed: state.loading ? null : widget.cubit.refresh,
                        child: const Text('Retry'),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const AppSectionHeader(title: 'Active'),
                  if (state.activity case final activity?) ...[
                    Text(
                      'Last updated: ${formatLocalDateTime(activity.generatedAt)}${state.error == null ? '' : ' · Refresh failed; statuses may be out of date.'}',
                    ),
                    for (final item in activity.active) _item(item),
                    if (activity.active.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No active jobs.'),
                      ),
                    _pages(
                      page: state.activePage,
                      hasMore: activity.activeNextCursor != null,
                      loading: state.loading,
                      previous: () =>
                          widget.cubit.refresh(previousActive: true),
                      next: () => widget.cubit.refresh(moreActive: true),
                    ),
                    const SizedBox(height: 20),
                    const AppSectionHeader(title: 'Finished jobs'),
                    for (final item in activity.finished) _item(item),
                    _pages(
                      page: state.finishedPage,
                      hasMore: activity.finishedNextCursor != null,
                      loading: state.loading,
                      previous: () =>
                          widget.cubit.refresh(previousFinished: true),
                      next: () => widget.cubit.refresh(moreFinished: true),
                    ),
                    if (activity.finished.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No finished jobs yet.'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _route = route;
    await Navigator.of(context, rootNavigator: true).push(route);
    if (_route == route) {
      _route = null;
    }
  }

  Widget _pages({
    required int page,
    required bool hasMore,
    required bool loading,
    required VoidCallback previous,
    required VoidCallback next,
  }) => page == 1 && !hasMore
      ? const SizedBox.shrink()
      : Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: loading || page == 1 ? null : previous,
              child: const Text('Previous'),
            ),
            Text('Page $page'),
            TextButton(
              onPressed: loading || !hasMore ? null : next,
              child: const Text('Next'),
            ),
          ],
        );

  Widget _item(PersonalActivityItem item) => AppRecordRow(
    key: Key('personal-activity-${item.kind}-${item.id}'),
    leading: Icon(
      item.kind == 'email_retrieval'
          ? Icons.mail_outline
          : item.kind == 'reindex_batch'
          ? Icons.manage_search
          : item.kind == 'document_ai'
          ? Icons.auto_awesome_outlined
          : Icons.description_outlined,
    ),
    title: item.label,
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.namespaceName}${item.kind == 'document_ai' ? ' · AI processing' : ''} · ${item.status}${item.stage == null ? '' : ' · ${item.stage == 'invoicing' ? 'Checking and extracting invoice' : item.stage}'}',
        ),
        if (item.finishedAt case final finished?)
          Text(formatLocalDateTime(finished)),
        if (item.canOpen)
          TextButton(
            onPressed: () => _openItem(item),
            child: Text(
              item.namespaceId == widget.namespaceId
                  ? 'Open'
                  : 'Switch library',
            ),
          ),
      ],
    ),
  );
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PersonalActivityCubit, PersonalActivityState>(
    bloc: widget.cubit,
    builder: (context, state) {
      if (widget.builder case final builder?) {
        final count = state.activity?.active.length ?? 0;
        return builder(
          context,
          AppWorkspaceAction(
            id: 'personal-activity',
            label: 'Your jobs',
            detail: 'Across libraries',
            icon: Icons.work_history_outlined,
            badge: count > 0
                ? '$count${state.activity?.activeTruncated == true ? '+' : ''}'
                : null,
            onPressed: _show,
          ),
        );
      }
      return IconButton(
        key: const Key('personal-activity'),
        tooltip: 'Your jobs across libraries',
        onPressed: _show,
        icon: Badge(
          isLabelVisible: (state.activity?.active.length ?? 0) > 0,
          label: Text(
            '${state.activity?.active.length ?? 0}${state.activity?.activeTruncated == true ? '+' : ''}',
          ),
          child: const Icon(Icons.work_history_outlined),
        ),
      );
    },
  );
}
