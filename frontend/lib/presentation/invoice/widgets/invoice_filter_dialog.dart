import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/invoice/models/invoice_search.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/invoice_filter_values_cubit.dart';
import '../cubits/invoices_cubit.dart';
import 'invoice_labels.dart';

final class InvoiceFilterDialog extends StatefulWidget {
  const InvoiceFilterDialog({
    super.key,
    required this.cubit,
    required this.initial,
    required this.isCurrent,
    required this.onClose,
  });
  final InvoicesCubit cubit;
  final InvoiceFilters initial;
  final bool Function() isCurrent;
  final ValueChanged<InvoiceFilters?> onClose;

  @override
  State<InvoiceFilterDialog> createState() => _InvoiceFilterDialogState();
}

final class _InvoiceFilterDialogState extends State<InvoiceFilterDialog> {
  late InvoiceFilters _draft = widget.initial;
  late final _dates = [
    TextEditingController(text: _draft.createdFrom),
    TextEditingController(text: _draft.createdTo),
    TextEditingController(text: _draft.issueFrom),
    TextEditingController(text: _draft.issueTo),
    TextEditingController(text: _draft.dueFrom),
    TextEditingController(text: _draft.dueTo),
  ];
  late final _minimum = TextEditingController(text: _draft.totalMin);
  late final _maximum = TextEditingController(text: _draft.totalMax);
  InvoiceFilterField? _selecting;
  String? _error;
  final _errorAnchor = GlobalKey();

  bool get _owns => mounted && !widget.cubit.isClosed && widget.isCurrent();

  void _apply() {
    if (!_owns) return;
    final filters = _draft.copyWith(
      createdFrom: _dates[0].text.trim(),
      createdTo: _dates[1].text.trim(),
      issueFrom: _dates[2].text.trim(),
      issueTo: _dates[3].text.trim(),
      dueFrom: _dates[4].text.trim(),
      dueTo: _dates[5].text.trim(),
      totalMin: _minimum.text.trim(),
      totalMax: _maximum.text.trim(),
    );
    final error = filters.validation;
    if (error != null) {
      setState(() => _error = error);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _errorAnchor.currentContext;
        if (_owns && context != null) {
          unawaited(Scrollable.ensureVisible(context));
        }
      });
      return;
    }
    widget.onClose(filters);
  }

  void _clear() {
    if (!_owns) return;
    for (final controller in [..._dates, _minimum, _maximum]) {
      controller.clear();
    }
    setState(() {
      _draft = const InvoiceFilters();
      _error = null;
    });
  }

  @override
  void dispose() {
    for (final controller in [..._dates, _minimum, _maximum]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selecting case final field?) {
      return _InvoiceFilterValuePicker(
        key: ValueKey(field),
        cubit: widget.cubit,
        field: field,
        selected: _draft.value(field),
        isCurrent: () => _owns,
        onBack: () {
          if (_owns) setState(() => _selecting = null);
        },
        onSelected: (value) {
          if (_owns) {
            setState(() {
              _draft = _draft.withValue(field, value);
              _selecting = null;
              _error = null;
            });
          }
        },
      );
    }
    return AppDialog(
      title: 'Filter invoices',
      description:
          'Choose exact invoice properties and optional date or total ranges.',
      actions: [
        TextButton(
          key: const Key('cancelInvoiceFilters'),
          onPressed: () {
            if (_owns) widget.onClose(null);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('applyInvoiceFilters'),
          onPressed: _apply,
          child: const Text('Apply filters'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('resetInvoiceFilterDraft'),
              onPressed: _clear,
              child: const Text('Clear filters'),
            ),
          ),
          const SizedBox(height: 8),
          for (final field in InvoiceFilterField.values) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('invoiceFilterField-${field.name}'),
                    onPressed: () {
                      if (_owns) setState(() => _selecting = field);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: _draft.value(field).isEmpty
                                  ? 'Any ${field.label.toLowerCase()}'
                                  : _draft.value(field),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    field.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                  Text(
                                    _draft.value(field).isEmpty
                                        ? 'Any'
                                        : invoiceFilterValueLabel(
                                            field,
                                            _draft.value(field),
                                          ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.search, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_draft.value(field).isNotEmpty)
                  IconButton(
                    tooltip: 'Clear ${field.label.toLowerCase()}',
                    onPressed: () {
                      if (_owns) {
                        setState(() => _draft = _draft.withValue(field, ''));
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          Text('Dates', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Ranges include both dates. Added dates use UTC. Leave an end blank for an open range.',
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < 3; index++) ...[
            _InvoiceRangeFields(
              first: TextField(
                key: Key('invoiceDateFrom-$index'),
                controller: _dates[index * 2],
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText:
                      '${['Added', 'Issue date', 'Due date'][index]} from',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
              second: TextField(
                key: Key('invoiceDateTo-$index'),
                controller: _dates[index * 2 + 1],
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText:
                      '${['Added', 'Issue date', 'Due date'][index]} through',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('Gross total', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _draft.currency.isEmpty
                ? 'Choose a currency above to filter totals.'
                : 'Amounts in ${_draft.currency}, including negative credit notes.',
          ),
          const SizedBox(height: 12),
          _InvoiceRangeFields(
            first: TextField(
              key: const Key('invoiceTotalMin'),
              controller: _minimum,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Minimum total',
                hintText: '0.00',
              ),
            ),
            second: TextField(
              key: const Key('invoiceTotalMax'),
              controller: _maximum,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Maximum total',
                hintText: '119.00',
              ),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            Semantics(
              key: _errorAnchor,
              liveRegion: true,
              child: AppNotice(message: error, tone: AppTone.danger),
            ),
          ],
        ],
      ),
    );
  }
}

final class _InvoiceRangeFields extends StatelessWidget {
  const _InvoiceRangeFields({required this.first, required this.second});
  final Widget first, second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide =
          constraints.maxWidth >= 480 &&
          MediaQuery.textScalerOf(context).scale(16) <= 24;
      final width = sideBySide
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(width: width, child: first),
          SizedBox(width: width, child: second),
        ],
      );
    },
  );
}

final class _InvoiceFilterValuePicker extends StatefulWidget {
  const _InvoiceFilterValuePicker({
    super.key,
    required this.cubit,
    required this.field,
    required this.selected,
    required this.isCurrent,
    required this.onBack,
    required this.onSelected,
  });
  final InvoicesCubit cubit;
  final InvoiceFilterField field;
  final String selected;
  final bool Function() isCurrent;
  final VoidCallback onBack;
  final ValueChanged<String> onSelected;

  @override
  State<_InvoiceFilterValuePicker> createState() =>
      _InvoiceFilterValuePickerState();
}

final class _InvoiceFilterValuePickerState
    extends State<_InvoiceFilterValuePicker> {
  late final _lookup = widget.cubit.filterValues(widget.field);
  final _query = TextEditingController();
  final _firstRow = GlobalKey();
  bool get _owns => mounted && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _query.addListener(_edited);
    unawaited(_lookup.submit());
  }

  void _edited() {
    if (!_owns) return;
    final value = _query.value;
    _lookup.editQuery(
      value.text,
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
  }

  @override
  void dispose() {
    _query.dispose();
    unawaited(_lookup.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<InvoiceFilterValuesCubit, InvoiceFilterValuesState>(
        bloc: _lookup,
        listenWhen: (before, after) => before.page != after.page,
        listener: (_, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final context = _firstRow.currentContext;
            if (_owns && context != null) {
              unawaited(Scrollable.ensureVisible(context));
            }
          });
        },
        builder: (context, state) => AppDialog(
          title: 'Choose ${widget.field.label.toLowerCase()}',
          description: 'Search all existing values in this library.',
          actions: [
            TextButton(
              key: const Key('backInvoiceFilterValues'),
              onPressed: widget.onBack,
              child: const Text('Back to filters'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('invoiceFilterValueSearch'),
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (_owns) unawaited(_lookup.submit());
                },
                decoration: InputDecoration(
                  labelText:
                      'Search ${widget.field.label.toLowerCase()} values',
                  errorText: state.validation,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Clear value search',
                    onPressed: () {
                      if (_owns) _query.clear();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('anyInvoiceFilterValue'),
                  onPressed: () {
                    if (_owns) widget.onSelected('');
                  },
                  child: const Text('Any value'),
                ),
              ),
              AppProgressSlot(active: state.loading || state.debouncing),
              if (state.error case final error?)
                AppNotice(
                  message: error,
                  action: TextButton(
                    onPressed: state.busy
                        ? null
                        : () {
                            if (_owns) unawaited(_lookup.retry());
                          },
                    child: const Text('Retry'),
                  ),
                ),
              if (state.items.isEmpty &&
                  state.loaded &&
                  !state.busy &&
                  state.error == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No matching values. Try another search.'),
                ),
              SizedBox(key: _firstRow),
              for (var index = 0; index < state.items.length; index++)
                Tooltip(
                  message: state.items[index],
                  child: ListTile(
                    key: Key('invoiceFilterValue-$index'),
                    title: Text(
                      invoiceFilterValueLabel(widget.field, state.items[index]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: state.items[index] == widget.selected,
                    leading: Icon(
                      state.items[index] == widget.selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: state.busy
                        ? null
                        : () {
                            if (_owns) widget.onSelected(state.items[index]);
                          },
                  ),
                ),
              if (state.loaded)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      key: const Key('firstInvoiceFilterValues'),
                      onPressed: state.busy || state.page == 1
                          ? null
                          : () {
                              if (_owns) unawaited(_lookup.submit());
                            },
                      child: const Text('First'),
                    ),
                    TextButton(
                      key: const Key('previousInvoiceFilterValues'),
                      onPressed: state.busy || !state.hasPrevious
                          ? null
                          : () {
                              if (_owns) unawaited(_lookup.previous());
                            },
                      child: const Text('Previous'),
                    ),
                    Text('Page ${state.page}'),
                    TextButton(
                      key: const Key('nextInvoiceFilterValues'),
                      onPressed: state.busy || state.nextCursor == null
                          ? null
                          : () {
                              if (_owns) unawaited(_lookup.next());
                            },
                      child: const Text('Next'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
}
