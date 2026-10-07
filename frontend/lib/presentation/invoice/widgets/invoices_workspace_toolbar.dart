import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/invoice/models/invoice_search.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/invoices_cubit.dart';
import 'invoice_filter_controls.dart';
import 'invoice_filter_dialog.dart';

final class InvoicesWorkspaceToolbar extends StatefulWidget {
  const InvoicesWorkspaceToolbar({
    super.key,
    required this.cubit,
    this.libraryPicker,
    this.workspaceActions,
  });
  final InvoicesCubit cubit;
  final Widget? libraryPicker, workspaceActions;
  @override
  State<InvoicesWorkspaceToolbar> createState() =>
      _InvoicesWorkspaceToolbarState();
}

final class _InvoicesWorkspaceToolbarState
    extends State<InvoicesWorkspaceToolbar> {
  late final TextEditingController _term;
  RawDialogRoute<InvoiceFilters>? _filterRoute;
  NavigatorState? _filterNavigator;
  InvoicesCubit get cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: cubit.state.rawTerm)
      ..addListener(_edited);
  }

  @override
  void didUpdateWidget(InvoicesWorkspaceToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != cubit) {
      _dismissFilters();
      _term.removeListener(_edited);
      _term.text = cubit.state.rawTerm;
      _term.addListener(_edited);
    }
  }

  void _edited() {
    final value = _term.value;
    cubit.editTerm(
      value.text,
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
  }

  void _clear() {
    _term.clear();
    unawaited(cubit.clearSearch());
  }

  @override
  void dispose() {
    _dismissFilters();
    _term.dispose();
    super.dispose();
  }

  void _dismissFilters() {
    final route = _filterRoute;
    final navigator = _filterNavigator;
    _filterRoute = null;
    _filterNavigator = null;
    if (route != null &&
        navigator != null &&
        navigator.mounted &&
        route.navigator == navigator) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.navigator == navigator) {
          navigator.removeRoute(route);
        }
      });
    }
  }

  Future<void> _filters() async {
    if (_filterRoute != null) return;
    final owner = cubit;
    final navigator = _filterNavigator = Navigator.of(context);
    late final RawDialogRoute<InvoiceFilters> route;
    bool owns() =>
        mounted &&
        identical(owner, cubit) &&
        !owner.isClosed &&
        _filterRoute == route &&
        navigator.mounted &&
        route.navigator == navigator &&
        route.isCurrent;
    route = RawDialogRoute<InvoiceFilters>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => InvoiceFilterDialog(
        cubit: owner,
        initial: owner.state.criteria.filters,
        isCurrent: owns,
        onClose: (filters) {
          if (owns()) navigator.pop(filters);
        },
      ),
    );
    _filterRoute = route;
    final selected = await navigator.push(route);
    if (!mounted ||
        !identical(owner, cubit) ||
        owner.isClosed ||
        _filterRoute != route) {
      return;
    }
    _filterRoute = null;
    _filterNavigator = null;
    if (selected != null) await owner.setFilters(selected);
  }

  void _submit() {
    final composing = _term.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    FocusScope.of(context).unfocus();
    unawaited(cubit.submitSearch());
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<InvoicesCubit, InvoicesState>(
        bloc: cubit,
        listenWhen: (before, after) => before.rawTerm != after.rawTerm,
        listener: (_, state) {
          if (_term.text != state.rawTerm) {
            _term.value = TextEditingValue(
              text: state.rawTerm,
              selection: TextSelection.collapsed(offset: state.rawTerm.length),
            );
          }
        },
        builder: (context, state) => AppCollectionToolbar(
          libraryPicker: widget.libraryPicker,
          workspaceActions: widget.workspaceActions,
          search: cubit.allowed
              ? AppSearchField(
                  fieldKey: const Key('invoiceSearchTerm'),
                  submitKey: const Key('applyInvoiceSearch'),
                  clearKey: const Key('clearInvoiceSearch'),
                  controller: _term,
                  hintText: 'Search invoices',
                  errorText: state.termError,
                  submittingBlocked: state.intentBlocked,
                  onSubmitted: (_) => _submit(),
                  onClear: _clear,
                )
              : null,
          actions: cubit.allowed
              ? [
                  OutlinedButton.icon(
                    key: const Key('invoiceFilters'),
                    onPressed: _filters,
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      state.criteria.filters.count == 0
                          ? 'Filters'
                          : 'Filters (${state.criteria.filters.count})',
                    ),
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
                      child: Text(
                        '${switch (state.source) {
                          'structured' => 'E-invoices',
                          'ai' => 'AI extracted',
                          _ => 'All invoices',
                        }} ▾',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ]
              : const [],
          summary: state.criteria.filters.count == 0
              ? null
              : InvoiceFilterControls(
                  criteria: state.criteria,
                  onFilters: _filters,
                  onSort: cubit.setSort,
                  onChanged: cubit.setFilters,
                  showActions: false,
                ),
        ),
      );
}
