import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/invoice/models/invoice.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/invoices_cubit.dart';
import '../widgets/invoice_details_dialog.dart';
import '../widgets/invoice_labels.dart';
import '../widgets/invoices_workspace_toolbar.dart';

final class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({
    super.key,
    required this.cubit,
    this.onOpenDocument,
    this.shellToolbar = false,
  });

  final InvoicesCubit cubit;
  final bool shellToolbar;
  final Future<void> Function(String)? onOpenDocument;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

final class _InvoicesScreenState extends State<InvoicesScreen> {
  InvoicesCubit get cubit => widget.cubit;

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
      onRefresh: cubit.allowed && !state.intentBlocked ? cubit.refresh : null,
      child: cubit.allowed
          ? LayoutBuilder(
              builder: (context, constraints) {
                final showStatus =
                    state.loading ||
                    state.debouncing ||
                    state.intentBlocked ||
                    state.error != null;
                final previousResults =
                    state.loaded &&
                    (!state.matchesSnapshot ||
                        state.loading ||
                        state.debouncing ||
                        state.intentBlocked);
                final bottomClearance = MediaQuery.paddingOf(context).bottom
                    .clamp(0.0, constraints.maxHeight);
                final count = Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '${state.items.length} ${state.items.length == 1 ? 'invoice' : 'invoices'} loaded',
                      key: const Key('invoiceCount'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                );
                final padding = AppLayout.cardListPadding(context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        key: const PageStorageKey('invoiceWorkspaceScroll'),
                        padding: showStatus
                            ? padding.copyWith(
                                bottom: padding.bottom - bottomClearance,
                              )
                            : padding,
                        children: [
                          if (!widget.shellToolbar) ...[
                            InvoicesWorkspaceToolbar(cubit: cubit),
                            const SizedBox(height: 12),
                          ],
                          AppProgressSlot(active: state.loading),
                          const SizedBox(height: 8),
                          if (state.items.isEmpty)
                            AppEmptyState(
                              key: const ValueKey('invoiceCollection'),
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
                            )
                          else
                            KeyedSubtree(
                              key: const ValueKey('invoiceCollection'),
                              child: AppPagedList(
                                key: ValueKey(
                                  'invoices-${state.snapshotVersion}',
                                ),
                                itemCount: state.items.length,
                                hasMore: state.cursor != null,
                                loading: !state.canPaginate,
                                onLoadMore: () => cubit.load(more: true),
                                loadMoreLabel: 'Next',
                                loadMoreKey: const Key('nextInvoices'),
                                footer: count,
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: AppSurface(
                                    padding: EdgeInsets.zero,
                                    child: _InvoiceRow(
                                      invoice: state.items[index],
                                      onOpen: () =>
                                          _open(context, state.items[index]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (state.items.isEmpty && state.loaded) count,
                        ],
                      ),
                    ),
                    if (showStatus)
                      Padding(
                        padding: EdgeInsets.only(bottom: bottomClearance),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                (constraints.maxHeight - bottomClearance) * .35,
                          ),
                          child: SingleChildScrollView(
                            primary: false,
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    '${state.status}${previousResults ? '\nShowing previous results' : ''}',
                                    key: const Key('invoiceCollectionStatus'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                                if (state.error case final error?)
                                  AppNotice(
                                    message: error,
                                    action: TextButton(
                                      onPressed:
                                          state.loading || state.intentBlocked
                                          ? null
                                          : cubit.refresh,
                                      child: const Text('Try again'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
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
