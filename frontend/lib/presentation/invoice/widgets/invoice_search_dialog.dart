import 'package:flutter/material.dart';

import '../../../domain/invoice/models/invoice_search.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/invoices_cubit.dart';
import 'invoice_filter_dialog.dart';

final class InvoiceSearchDialog extends StatefulWidget {
  const InvoiceSearchDialog({
    super.key,
    required this.cubit,
    required this.isCurrent,
    required this.onApply,
    required this.onCancel,
    this.libraryName = '',
  });

  final InvoicesCubit cubit;
  final bool Function() isCurrent;
  final void Function(InvoiceCriteria, String) onApply;
  final VoidCallback onCancel;
  final String libraryName;

  @override
  State<InvoiceSearchDialog> createState() => _InvoiceSearchDialogState();
}

final class _InvoiceSearchDialogState extends State<InvoiceSearchDialog> {
  late final _query = TextEditingController(text: widget.cubit.state.rawTerm);
  late InvoiceCriteria _draft = widget.cubit.state.criteria;
  final _filters = GlobalKey<InvoiceFilterDialogState>();
  String? _error;
  bool get _owns => mounted && !widget.cubit.isClosed && widget.isCurrent();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clear() {
    if (!_owns) return;
    _query.clear();
    _filters.currentState?.clearDraft();
    setState(() {
      _draft = const InvoiceCriteria();
      _error = null;
    });
  }

  void _apply() {
    if (!_owns ||
        (_query.value.composing.isValid && !_query.value.composing.isCollapsed)) {
      return;
    }
    if (_query.text.trim().runes.length > 200) {
      setState(() => _error = 'Use 200 characters or fewer.');
      return;
    }
    final filters = _filters.currentState?.validatedFilters();
    if (filters == null) return;
    widget.onApply(
      _draft.copyWith(query: _query.text.trim(), filters: filters),
      _query.text,
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('invoiceSearchDialog'),
    backgroundColor: Colors.transparent,
    insetPadding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
    ),
    constraints: const BoxConstraints(maxWidth: 640),
    child: GlacierSearchDialog(
      controller: _query,
      fieldKey: const Key('invoiceSearchTerm'),
      applyKey: const Key('applyInvoiceSearch'),
      placeholder: 'Search invoices…',
      contextLabel: widget.libraryName.isEmpty
          ? 'Invoices'
          : '${widget.libraryName} · Invoices',
      summary:
          _draft.filters.count > 0 ||
              _draft.source != null ||
              _draft.sort != InvoiceSort.automatic
          ? 'Filters ready to apply'
          : '',
      error: _error,
      onChanged: (_) => setState(() => _error = null),
      onClear: _clear,
      onCancel: widget.onCancel,
      onApply: _apply,
      filters: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlacierSearchFilterGroup(
            label: 'Extraction source',
            options: const ['All invoices', 'E-invoices', 'AI extracted'],
            selected: [
              switch (_draft.source) {
                'structured' => 'E-invoices',
                'ai' => 'AI extracted',
                _ => 'All invoices',
              },
            ],
            onChanged: (label, selected) {
              if (!_owns || !selected) return;
              setState(
                () => _draft = _draft.copyWith(
                  source: switch (label) {
                    'E-invoices' => 'structured',
                    'AI extracted' => 'ai',
                    _ => null,
                  },
                  clearSource: label == 'All invoices',
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<InvoiceSort>(
            key: ValueKey(_draft.sort),
            initialValue: _draft.sort,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sort'),
            items: [
              for (final sort in InvoiceSort.values)
                DropdownMenuItem(
                  value: sort,
                  child: Text(
                    sort.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (sort) {
              if (_owns && sort != null) {
                setState(() => _draft = _draft.copyWith(sort: sort));
              }
            },
          ),
          const SizedBox(height: 16),
          InvoiceFilterDialog(
            key: _filters,
            cubit: widget.cubit,
            initial: _draft.filters,
            embedded: true,
            isCurrent: () => _owns,
            onClose: (_) {},
            onDraftChanged: (filters) {
              if (_owns) {
                setState(() => _draft = _draft.copyWith(filters: filters));
              }
            },
          ),
        ],
      ),
    ),
  );
}
