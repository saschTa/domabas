import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/invoice/models/invoice_search.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/invoices_cubit.dart';
import 'invoice_labels.dart';

final class InvoiceFilterControls extends StatelessWidget {
  const InvoiceFilterControls({
    super.key,
    required this.criteria,
    required this.onFilters,
    required this.onSort,
    required this.onChanged,
    this.showActions = true,
  });
  final InvoiceCriteria criteria;
  final bool showActions;
  final VoidCallback onFilters;
  final Future<void> Function(InvoiceSort) onSort;
  final Future<void> Function(InvoiceFilters) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showActions)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('invoiceFilters'),
              onPressed: onFilters,
              icon: const Icon(Icons.tune),
              label: Text(
                criteria.filters.count == 0
                    ? 'Filters'
                    : 'Filters (${criteria.filters.count})',
              ),
            ),
            InvoiceSortControl(criteria: criteria, onSort: onSort),
          ],
        ),
      if (criteria.filters.count > 0) ...[
        if (showActions) const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final field in InvoiceFilterField.values)
              if (criteria.filters.value(field).isNotEmpty)
                _InvoiceActiveFilter(
                  label:
                      '${field.label}: ${invoiceFilterValueLabel(field, criteria.filters.value(field))}',
                  onRemove: () {
                    var filters = criteria.filters.withValue(field, '');
                    if (field == InvoiceFilterField.currency) {
                      filters = filters.copyWith(totalMin: '', totalMax: '');
                    }
                    unawaited(onChanged(filters));
                  },
                ),
            for (final (label, from, to, cleared) in [
              (
                'Added (UTC)',
                criteria.filters.createdFrom,
                criteria.filters.createdTo,
                criteria.filters.copyWith(createdFrom: '', createdTo: ''),
              ),
              (
                'Issue date',
                criteria.filters.issueFrom,
                criteria.filters.issueTo,
                criteria.filters.copyWith(issueFrom: '', issueTo: ''),
              ),
              (
                'Due date',
                criteria.filters.dueFrom,
                criteria.filters.dueTo,
                criteria.filters.copyWith(dueFrom: '', dueTo: ''),
              ),
              (
                'Total',
                criteria.filters.totalMin,
                criteria.filters.totalMax,
                criteria.filters.copyWith(totalMin: '', totalMax: ''),
              ),
            ])
              if (from.isNotEmpty || to.isNotEmpty)
                _InvoiceActiveFilter(
                  label:
                      '$label: ${from.isEmpty ? 'Any' : from} – ${to.isEmpty ? 'Any' : to}',
                  onRemove: () => unawaited(onChanged(cleared)),
                ),
            TextButton(
              key: const Key('clearInvoiceFilters'),
              onPressed: () => unawaited(onChanged(const InvoiceFilters())),
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ],
    ],
  );
}

final class _InvoiceActiveFilter extends StatelessWidget {
  const _InvoiceActiveFilter({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Tooltip(
                message: label,
                excludeFromSemantics: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth - 80).clamp(80, 280),
                  ),
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove $label',
            onPressed: onRemove,
            color: Theme.of(context).colorScheme.onSurface,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );
}

final class InvoiceSortControl extends StatelessWidget {
  const InvoiceSortControl({
    super.key,
    required this.criteria,
    required this.onSort,
  });
  final InvoiceCriteria criteria;
  final Future<void> Function(InvoiceSort) onSort;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: true,
    label: 'Sort invoices: ${criteria.sort.label}',
    child: Tooltip(
      message: 'Sort invoices: ${criteria.sort.label}',
      excludeFromSemantics: true,
      child: PopupMenuButton<InvoiceSort>(
        key: const Key('sortInvoices'),
        tooltip: '',
        initialValue: criteria.sort,
        onSelected: (sort) => unawaited(onSort(sort)),
        itemBuilder: (_) => [
          for (final sort in InvoiceSort.values)
            PopupMenuItem(
              key: Key('invoiceSort-${sort.name}'),
              value: sort,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sort.label),
                    if (sort == InvoiceSort.automatic)
                      const Text(
                        'Relevance for searches; newest added otherwise.',
                      ),
                  ],
                ),
              ),
            ),
        ],
        child: ExcludeSemantics(
          child: MediaQuery.sizeOf(context).width < AppLayout.mobileBreakpoint
              ? const SizedBox.square(dimension: 48, child: Icon(Icons.sort))
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Text('Sort: ${criteria.sort.label} ▾'),
                ),
        ),
      ),
    ),
  );
}
