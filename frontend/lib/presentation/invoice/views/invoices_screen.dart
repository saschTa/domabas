import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/invoice/models/invoice.dart';
import '../../../domain/invoice/models/invoice_search.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/invoices_cubit.dart';
import '../widgets/invoice_details_dialog.dart';
import '../widgets/invoice_filter_controls.dart';
import '../widgets/invoice_filter_dialog.dart';
import '../widgets/invoice_labels.dart';
import '../widgets/invoice_search_controls.dart';

final class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, required this.cubit, this.onOpenDocument});

  final InvoicesCubit cubit;
  final Future<void> Function(String)? onOpenDocument;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

final class _InvoicesScreenState extends State<InvoicesScreen> {
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
  void didUpdateWidget(InvoicesScreen oldWidget) {
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

  Future<void> _open(BuildContext context, Invoice invoice) async {
    final documentId = await showInvoiceDetails(
      context,
      cubit: cubit.details(invoice.id, initial: invoice),
      canOpenDocument: widget.onOpenDocument != null,
    );
    if (context.mounted && documentId != null) {
      await widget.onOpenDocument?.call(documentId);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<InvoicesCubit, InvoicesState>(
    bloc: cubit,
    builder: (context, state) => AppPage(
      insetBody: false,
      title: 'Invoices',
      description: 'Invoice details from documents in your library.',
      actions: [
        IconButton(
          key: const Key('refreshInvoices'),
          tooltip: 'Refresh invoices',
          onPressed: state.loading || state.intentBlocked
              ? null
              : () => cubit.load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: cubit.allowed
          ? ListView(
              key: const PageStorageKey('invoiceWorkspaceScroll'),
              padding: AppLayout.cardListPadding(context),
              children: [
                InvoiceSearchControls(
                  term: _term,
                  onSubmit: () => unawaited(cubit.submitSearch()),
                  onClear: _clear,
                  blocked: state.intentBlocked,
                  error: state.termError,
                ),
                const SizedBox(height: 12),
                InvoiceFilterControls(
                  criteria: state.criteria,
                  onFilters: _filters,
                  onSort: cubit.setSort,
                  onChanged: cubit.setFilters,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label, icon) in const [
                      (null, 'All invoices', Icons.receipt_long_outlined),
                      ('structured', 'E-invoices', Icons.description_outlined),
                      ('ai', 'AI extracted', Icons.auto_awesome_outlined),
                    ])
                      ChoiceChip(
                        key: ValueKey('invoiceFilter-${value ?? 'all'}'),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        showCheckmark: false,
                        avatar: Icon(
                          state.source == value ? Icons.check : icon,
                          size: 18,
                        ),
                        label: Text(label),
                        selected: state.source == value,
                        onSelected: (_) => cubit.filter(value),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                AppProgressSlot(active: state.loading),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${state.status}\n${state.loaded && (!state.matchesSnapshot || state.loading || state.debouncing || state.intentBlocked) ? 'Showing previous results' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                if (state.error case final error?) ...[
                  AppNotice(
                    message: error,
                    action: TextButton(
                      onPressed: state.loading || state.intentBlocked
                          ? null
                          : () => cubit.load(),
                      child: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (state.items.isEmpty)
                  AppSurface(
                    key: const ValueKey('invoiceCollection'),
                    child: AppEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: !state.loaded && state.loading
                          ? 'Loading invoices…'
                          : state.loaded
                          ? state.snapshot!.query.isNotEmpty ||
                                    state.snapshot!.source != null ||
                                    state.snapshot!.filters.count > 0
                                ? 'No matching invoices'
                                : 'No invoices yet'
                          : 'Invoices are unavailable',
                      message: !state.loaded && state.loading
                          ? 'Reading invoice details from this library.'
                          : state.snapshot?.query.isNotEmpty == true
                          ? 'Try another invoice number, party or invoice detail, or clear the search.'
                          : (state.snapshot?.filters.count ?? 0) > 0
                          ? 'Adjust the invoice properties or clear the filters.'
                          : state.snapshot?.source == null
                          ? 'Recognized invoices appear here after document processing.'
                          : 'No invoices match this source. Choose All invoices to see other results.',
                    ),
                  )
                else
                  AppSurface(
                    key: const ValueKey('invoiceCollection'),
                    padding: EdgeInsets.zero,
                    child: AppPagedList(
                      key: ValueKey('invoices-${state.snapshotVersion}'),
                      itemCount: state.items.length,
                      hasMore: state.cursor != null,
                      loading: !state.canPaginate,
                      onLoadMore: () => cubit.load(more: true),
                      loadMoreLabel: 'Next',
                      loadMoreKey: const Key('nextInvoices'),
                      itemBuilder: (context, index) => Column(
                        children: [
                          if (index > 0) const Divider(height: 1),
                          _InvoiceRow(
                            invoice: state.items[index],
                            onOpen: () => _open(context, state.items[index]),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : const AppEmptyState(
              icon: Icons.lock_outline,
              title: 'Invoice access is limited',
              message: 'Ask a library manager for permission to view invoices.',
            ),
    ),
  );
}

final class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice, required this.onOpen});
  final Invoice invoice;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppRecordRow(
    key: ValueKey('invoice-${invoice.id}'),
    title: invoice.seller.name.isEmpty
        ? 'Supplier not recorded'
        : invoice.seller.name,
    subtitle: Text(
      '${invoiceType(invoice.typeCode)} ${invoice.number.isEmpty ? '· number not recorded' : invoice.number}',
    ),
    metadata: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppStatusBadge(
          label: invoice.structured
              ? 'E-invoice · ${invoiceFormat(invoice.format)}'
              : 'AI extracted · Review details',
          tone: invoice.structured ? AppTone.neutral : AppTone.warning,
        ),
        Text(
          invoice.issueDate.isEmpty ? 'Date not recorded' : invoice.issueDate,
        ),
        if (invoice.dueDate.isNotEmpty) Text('Due ${invoice.dueDate}'),
      ],
    ),
    trailing: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          invoiceAmount(invoice.totalGross, invoice.currency),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: ValueKey('invoiceDetails-${invoice.id}'),
          onPressed: onOpen,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Details'),
        ),
      ],
    ),
  );
}
