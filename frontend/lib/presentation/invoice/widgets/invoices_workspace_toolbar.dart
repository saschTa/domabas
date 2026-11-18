import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/invoices_cubit.dart';
import 'invoice_filter_controls.dart';
import 'invoice_search_dialog.dart';

final class InvoicesWorkspaceToolbar extends StatefulWidget {
  const InvoicesWorkspaceToolbar({
    super.key,
    required this.cubit,
    this.libraryPicker,
    this.workspaceActions,
    this.libraryName = '',
    this.showSearchButton = false,
  });
  final InvoicesCubit cubit;
  final Widget? libraryPicker, workspaceActions;
  final String libraryName;
  final bool showSearchButton;
  @override
  InvoicesWorkspaceToolbarState createState() =>
      InvoicesWorkspaceToolbarState();
}

final class InvoicesWorkspaceToolbarState
    extends State<InvoicesWorkspaceToolbar> {
  RawDialogRoute<void>? _searchRoute;
  NavigatorState? _searchNavigator;
  int _searchGeneration = 0;
  final _searchFocus = FocusNode();
  InvoicesCubit get cubit => widget.cubit;

  @override
  void didUpdateWidget(InvoicesWorkspaceToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != cubit) _dismissSearch();
  }

  @override
  void dispose() {
    _dismissSearch();
    _searchFocus.dispose();
    super.dispose();
  }

  void _dismissSearch() {
    _searchGeneration++;
    final route = _searchRoute;
    final navigator = _searchNavigator;
    _searchRoute = null;
    _searchNavigator = null;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.navigator == navigator) {
          navigator.removeRoute(route);
        }
      });
    }
  }

  Future<void> openSearch() async {
    final owner = cubit;
    if (_searchRoute != null ||
        owner.isClosed ||
        !owner.allowed ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final generation = ++_searchGeneration;
    final native = GlacierNativePresentationScope.maybeOf(context);
    final navigator = _searchNavigator = Navigator.of(context);
    final returnFocus = FocusManager.instance.primaryFocus;
    late final RawDialogRoute<void> route;
    bool owns() =>
        mounted &&
        identical(owner, cubit) &&
        !owner.isClosed &&
        generation == _searchGeneration &&
        _searchRoute == route &&
        navigator.mounted &&
        route.navigator == navigator &&
        route.isCurrent;
    route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: native == null ? Colors.black26 : Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (routeContext, _, _) => glacierDialogBackdrop(
        routeContext,
        (_) => SafeArea(
          child: InvoiceSearchDialog(
            cubit: owner,
            libraryName: widget.libraryName,
            isCurrent: owns,
            onCancel: () {
              if (owns()) navigator.pop();
            },
            onApply: (criteria, rawTerm) {
              if (!owns()) return;
              unawaited(owner.applySearch(criteria, rawTerm: rawTerm));
              navigator.pop();
            },
          ),
        ),
        native: native,
      ),
    );
    _searchRoute = route;
    await navigator.push(route);
    if (!mounted || generation != _searchGeneration || _searchRoute != route) {
      return;
    }
    _searchRoute = null;
    _searchNavigator = null;
    if (returnFocus?.context != null && returnFocus!.canRequestFocus) {
      returnFocus.requestFocus();
    } else if (_searchFocus.canRequestFocus) {
      _searchFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<InvoicesCubit, InvoicesState>(
        bloc: cubit,
        builder: (context, state) => GlacierToolbar(
          children: [
            Wrap(
              key: const Key('collectionToolbarControls'),
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (cubit.allowed) ...[
                  if (widget.showSearchButton)
                    GlacierButton(
                      label: 'Search invoices',
                      icon: Icons.search,
                      onPressed: openSearch,
                    ),
                  GlacierButton(
                    key: const Key('invoiceFilters'),
                    focusNode: _searchFocus,
                    onPressed: openSearch,
                    icon: Icons.tune,
                    label: state.criteria.filters.count == 0
                        ? 'Filters'
                        : 'Filters (${state.criteria.filters.count})',
                  ),
                  InvoiceSortControl(
                    criteria: state.criteria,
                    onSort: cubit.setSort,
                  ),
                  PopupMenuButton<String>(
                    key: const Key('invoiceSource'),
                    tooltip: 'Invoice source',
                    initialValue: state.source ?? 'all',
                    onSelected: (value) =>
                        cubit.filter(value == 'all' ? null : value),
                    itemBuilder: (_) => [
                      for (final (value, label) in const [
                        ('all', 'All invoices'),
                        ('structured', 'E-invoices'),
                        ('ai', 'AI extracted'),
                      ])
                        PopupMenuItem(
                          key: ValueKey('invoiceFilter-$value'),
                          value: value,
                          child: Text(label),
                        ),
                    ],
                    child: Container(
                      width: MediaQuery.textScalerOf(context).scale(144),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              switch (state.source) {
                                'structured' => 'E-invoices',
                                'ai' => 'AI extracted',
                                _ => 'All invoices',
                              },
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
                ?widget.workspaceActions,
                ?widget.libraryPicker,
              ],
            ),
            if (state.rawTerm.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlacierTag(
                    label: 'Search: ${state.rawTerm}',
                    onDeleted: cubit.clearSearch,
                  ),
                ),
              ),
            if (state.criteria.filters.count != 0)
              InvoiceFilterControls(
                criteria: state.criteria,
                onFilters: openSearch,
                onSort: cubit.setSort,
                onChanged: cubit.setFilters,
                showActions: false,
              ),
          ],
        ),
      );
}
