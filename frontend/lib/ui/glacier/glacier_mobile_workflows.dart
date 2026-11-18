import 'package:flutter/material.dart';

import '../app_paged_list.dart';
import 'glacier_controls.dart';
import 'glacier_invoices.dart';
import 'glacier_mobile_foundations.dart';
import 'glacier_theme.dart';
import 'glacier_workflows.dart';

class GlacierMobileInvoiceRow extends StatelessWidget {
  const GlacierMobileInvoiceRow({
    super.key,
    required this.invoice,
    this.onOpen,
  });
  final GlacierInvoiceValue invoice;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(15) > 22;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          invoice.supplier.isEmpty ? 'Supplier not recorded' : invoice.supplier,
          style: const TextStyle(
            fontSize: 15.45,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${invoice.type} ${invoice.number.isEmpty ? '· number not recorded' : invoice.number}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final amount = Text(
      invoice.amountLabel ?? invoice.amount,
      style: const TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
    final due = Text(
      'Due ${invoice.dueDate.isEmpty ? 'not recorded' : invoice.dueDate}',
      style: TextStyle(fontSize: 12, color: GlacierTokens.of(context).muted),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: GlacierTokens.of(context).border),
            ),
          ),
          child: large
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: 8),
                    amount,
                    const SizedBox(height: 8),
                    _Badge(invoice.provenance),
                    const SizedBox(height: 8),
                    due,
                  ],
                )
              : Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: amount,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _Badge(invoice.provenance),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: due,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class GlacierMobileInvoiceFilters extends StatelessWidget {
  const GlacierMobileInvoiceFilters({
    super.key,
    required this.values,
    required this.onChanged,
    required this.onApply,
    required this.onCancel,
    this.options = const {},
    this.error,
  });
  final Map<String, String> values;
  final Map<String, List<String>> options;
  final void Function(String field, String value) onChanged;
  final VoidCallback? onApply, onCancel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    Widget field(String name) => options.containsKey(name)
        ? _Select(
            label: name,
            value: values[name] ?? options[name]!.first,
            options: options[name]!,
            onChanged: (value) => onChanged(name, value),
          )
        : GlacierMobileField(
            key: ValueKey(name),
            label: name,
            initialValue: values[name] ?? '',
            onChanged: (value) => onChanged(name, value),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlacierMobileNotice(
          title: 'Invoice filters',
          message: 'Searches invoice properties. Original document text is searched from Documents.',
          attention: false,
        ),
        _GlacierMobileWorkflowSection(
          'Properties',
          Column(
            children: [
              for (final name in [
                'Invoice number',
                'Supplier',
                'Customer',
                'Currency',
                'Invoice type',
                'Format',
                'Payment method',
              ])
                field(name),
            ],
          ),
        ),
        _GlacierMobileWorkflowSection(
          'Dates',
          Column(
            children: [
              for (final name in [
                'Added from',
                'Added to',
                'Issued from',
                'Issued to',
                'Due from',
                'Due to',
              ])
                field(name),
            ],
          ),
        ),
        _GlacierMobileWorkflowSection(
          'Gross total',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Muted(
                'Choose a currency before adding a total range. Decimal values are kept exactly.',
              ),
              const SizedBox(height: 12),
              field('Minimum total'),
              field('Maximum total'),
            ],
          ),
        ),
        if (error != null)
          GlacierMobileNotice(title: 'Check the filters', message: error!),
        GlacierMobileActionBar(
          children: [
            GlacierButton(label: 'Cancel', onPressed: onCancel),
            GlacierButton(
              label: 'Apply filters',
              onPressed: onApply,
              kind: GlacierButtonKind.primary,
            ),
          ],
        ),
      ],
    );
  }
}

class GlacierMobileInvoicesScreen extends StatelessWidget {
  const GlacierMobileInvoicesScreen({
    super.key,
    required this.queryController,
    required this.invoices,
    required this.source,
    required this.sort,
    required this.sortOptions,
    required this.onOpen,
    this.onSearch,
    this.onSource,
    this.onSort,
    this.onFilters,
    this.onMore,
    this.onPrevious,
    this.onOpenDocuments,
    this.onClear,
    this.notice,
    this.continuationNotice,
    this.empty = false,
    this.appliedFilters = const [],
    this.loadedLabel,
  });
  final TextEditingController queryController;
  final List<GlacierInvoiceValue> invoices;
  final String source, sort;
  final List<String> sortOptions;
  final ValueChanged<GlacierInvoiceValue>? onOpen;
  final ValueChanged<String>? onSource, onSort;
  final VoidCallback? onSearch,
      onFilters,
      onMore,
      onPrevious,
      onOpenDocuments,
      onClear;
  final Widget? notice, continuationNotice;
  final bool empty;
  final List<Widget> appliedFilters;
  final String? loadedLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, size) {
          final field = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Search invoice properties',
                style: TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 7),
              Semantics(
                label: 'Search invoice properties',
                child: TextField(
                  controller: queryController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    if (!queryController.value.composing.isValid ||
                        queryController.value.composing.isCollapsed) {
                      onSearch?.call();
                    }
                  },
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(12),
                    constraints: BoxConstraints(minHeight: 50),
                  ),
                ),
              ),
            ],
          );
          final search = GlacierButton(
            label: 'Search',
            onPressed: onSearch,
            kind: GlacierButtonKind.primary,
          );
          if (MediaQuery.textScalerOf(context).scale(15) > 22) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [field, const SizedBox(height: 8), search],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: field),
              const SizedBox(width: 8),
              search,
            ],
          );
        },
      ),
      const SizedBox(height: 22),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final value in ['All invoices', 'E-invoices', 'AI extracted'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  onPressed: onSource == null ? null : () => onSource!(value),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    backgroundColor: source == value
                        ? GlacierTokens.of(context).selectedNavigation
                        : GlacierTokens.of(context).glass,
                    foregroundColor: source == value
                        ? GlacierTokens.of(context).onSelectedNavigation
                        : Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(
                      color: source == value
                          ? Colors.transparent
                          : GlacierTokens.of(context).border,
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13.05,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  child: Text(value),
                ),
              ),
            GlacierButton(label: 'Filters', onPressed: onFilters),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _Select(
        label: 'Sort',
        value: sort,
        options: sortOptions,
        onChanged: onSort,
      ),
      if (appliedFilters.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: appliedFilters),
      ?notice,
      if (empty || invoices.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: GlacierTokens.of(context).accent,
                size: 36,
              ),
              const SizedBox(height: 18),
              Text(
                empty ? 'No invoices yet' : 'No matching invoices',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                empty
                    ? 'Invoices appear when structured or AI invoice data is extracted from your documents.'
                    : 'Try a shorter query or clear a filter.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              GlacierButton(
                label: empty ? 'Open Documents' : 'Clear search',
                onPressed: empty ? onOpenDocuments : onClear,
              ),
            ],
          ),
        )
      else
        for (final invoice in invoices)
          GlacierMobileInvoiceRow(
            invoice: invoice,
            onOpen: onOpen == null ? null : () => onOpen!(invoice),
          ),
      ?continuationNotice,
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              loadedLabel ??
                  '${empty ? 0 : invoices.length} invoices loaded · Personal library',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            GlacierMobileActionBar(
              children: [
                GlacierButton(label: 'Previous', onPressed: onPrevious),
                GlacierButton(label: 'Next', onPressed: onMore),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class GlacierMobileInvoiceSection extends StatefulWidget {
  const GlacierMobileInvoiceSection({
    super.key,
    required this.title,
    this.child,
    this.values = const {},
    this.records = const [],
    this.pageSize = 20,
    this.hasMore = false,
    this.onLoadMore,
    this.initiallyExpanded = false,
  });
  final String title;
  final Widget? child;
  final Map<String, String> values;
  final List<GlacierInvoiceDetailRecord> records;
  final int pageSize;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final bool initiallyExpanded;
  @override
  State<GlacierMobileInvoiceSection> createState() =>
      _GlacierMobileInvoiceSectionState();
}

class _GlacierMobileInvoiceSectionState
    extends State<GlacierMobileInvoiceSection> {
  late bool expanded = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: GlacierTokens.of(context).border),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          button: true,
          child: InkWell(
            onTap: () => setState(() => expanded = !expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded ? Icons.remove : Icons.add,
                      color: GlacierTokens.of(context).accent,
                      size: 21,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final content = expanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.values.isNotEmpty) _Values(widget.values),
                        if (widget.records.isNotEmpty)
                          AppPagedList(
                            itemCount: widget.records.length,
                            pageSize: widget.pageSize,
                            hasMore: widget.hasMore,
                            onLoadMore: widget.onLoadMore,
                            itemBuilder: (context, index) {
                              final record = widget.records[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      record.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const SizedBox(height: 5),
                                    _Values(record.values),
                                    ?record.action,
                                  ],
                                ),
                              );
                            },
                          ),
                        ?widget.child,
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity);
            if (MediaQuery.disableAnimationsOf(context)) return content;
            return AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: content,
            );
          },
        ),
      ],
    ),
  );
}

class GlacierMobileInvoiceDetails extends StatelessWidget {
  const GlacierMobileInvoiceDetails({
    super.key,
    required this.invoice,
    required this.sections,
    this.onBack,
    this.onOpenOriginal,
    this.unavailable = false,
  });
  final GlacierInvoiceValue invoice;
  final List<Widget> sections;
  final VoidCallback? onBack, onOpenOriginal;
  final bool unavailable;
  @override
  Widget build(BuildContext context) => unavailable
      ? GlacierMobileNotice(
          title: 'Invoice details are unavailable',
          message: 'This invoice may have been removed or your access changed. The collection remains available.',
          action: GlacierButton(label: 'Back to invoices', onPressed: onBack),
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlacierMobileActionBar(
              children: [
                GlacierButton(label: 'Back to invoices', onPressed: onBack),
                GlacierButton(
                  label: 'Open original',
                  onPressed: onOpenOriginal,
                  kind: GlacierButtonKind.primary,
                ),
              ],
            ),
            _GlacierMobileWorkflowSection(
              invoice.supplier,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Muted(invoice.number),
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      invoice.amount,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.6,
                      ),
                    ),
                  ),
                  _Badge(invoice.provenance),
                  if (invoice.aiExtracted)
                    const GlacierMobileNotice(
                      title: 'Review extracted values',
                      message: 'These values were generated from the original. Check the document before using them.',
                    )
                  else
                    const _Muted('Data extracted from embedded invoice XML.'),
                  _Values({
                    'Invoice type': invoice.type,
                    'Currency': invoice.currency,
                    'Issue date': invoice.issueDate,
                    'Due date': invoice.dueDate,
                  }),
                ],
              ),
            ),
            ...sections,
          ],
        );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.7,
        height: 1.2,
        color: GlacierTokens.of(context).accent,
      ),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: GlacierTokens.of(context).muted));
}

class _GlacierMobileWorkflowSection extends StatelessWidget {
  const _GlacierMobileWorkflowSection(
    this.title,
    this.child, {
    this.first = false,
  });
  final String title;
  final Widget child;
  final bool first;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: first ? 12 : 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _Values extends StatelessWidget {
  const _Values(this.values);
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in values.entries)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: GlacierTokens.of(context).border),
            ),
          ),
          child: MediaQuery.textScalerOf(context).scale(15) > 22
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: GlacierTokens.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(entry.value.isEmpty ? 'Not recorded' : entry.value),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 35,
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          color: GlacierTokens.of(context).muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 65,
                      child: Text(
                        entry.value.isEmpty ? 'Not recorded' : entry.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13.95, height: 1.3),
                      ),
                    ),
                  ],
                ),
        ),
    ],
  );
}

class _Select extends StatelessWidget {
  const _Select({
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
  });
  final String label, value;
  final List<String> options;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 13.5)),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (value) {
                  if (value != null) onChanged!(value);
                },
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.all(12),
            constraints: BoxConstraints(minHeight: 50),
          ),
        ),
      ],
    ),
  );
}

class GlacierMobileActivitySummary extends StatelessWidget {
  const GlacierMobileActivitySummary({
    super.key,
    required this.label,
    required this.detail,
    this.onOpen,
    this.running = false,
  });
  final String label, detail;
  final VoidCallback? onOpen;
  final bool running;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    glass: true,
    radius: 13,
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(13),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                running ? Icons.sync : Icons.check_circle_outline,
                color: GlacierTokens.of(context).accent,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (onOpen != null) const Icon(Icons.chevron_right, size: 21),
            ],
          ),
        ),
      ),
    ),
  );
}

class GlacierMobileJobRow extends StatelessWidget {
  const GlacierMobileJobRow({
    super.key,
    required this.title,
    required this.status,
    required this.stage,
    this.onOpen,
    this.onRetry,
    this.running = false,
  });
  final String title, status, stage;
  final VoidCallback? onOpen, onRetry;
  final bool running;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: GlacierTokens.of(context).border),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  onRetry != null
                      ? Icons.error_outline
                      : running
                      ? Icons.sync
                      : Icons.check,
                  color: GlacierTokens.of(context).accent,
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      Text(stage, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            );
            if (MediaQuery.textScalerOf(context).scale(15) > 22 ||
                constraints.maxWidth < 330) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: 10),
                  _Badge(status),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: identity),
                const SizedBox(width: 12),
                _Badge(status),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        GlacierMobileActionBar(
          children: [
            GlacierButton(label: 'Details', onPressed: onOpen),
            if (onRetry != null)
              GlacierButton(label: 'Retry', onPressed: onRetry),
          ],
        ),
      ],
    ),
  );
}

class GlacierMobilePipelineEvidence extends StatelessWidget {
  const GlacierMobilePipelineEvidence({super.key, required this.stages});
  final List<GlacierPipelineStage> stages;
  @override
  Widget build(BuildContext context) => stages.isEmpty
      ? const _Muted(
          'No checkpoint evidence is available. A later stage is not proof that an earlier step succeeded.',
        )
      : Column(
          children: [
            for (final stage in stages)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: GlacierTokens.of(context).border),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (stage.state) {
                        GlacierStageState.complete => Icons.check,
                        GlacierStageState.running => Icons.sync,
                        GlacierStageState.failed => Icons.error_outline,
                        GlacierStageState.waiting => Icons.schedule,
                        GlacierStageState.skipped =>
                          Icons.remove_circle_outline,
                        GlacierStageState.unknown => Icons.help_outline,
                      },
                      color: GlacierTokens.of(context).accent,
                      size: 21,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stage.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            stage.detail ?? 'Not recorded',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
}

class GlacierMobileJobDetails extends StatelessWidget {
  const GlacierMobileJobDetails({
    super.key,
    required this.title,
    required this.name,
    required this.status,
    required this.stage,
    required this.stages,
    required this.requestDetails,
    this.values = const {},
    this.onBack,
    this.onOpenDocument,
    this.notice,
    this.library = 'Personal library',
    this.disclaimer,
  });
  final String title, name, status, stage, library;
  final Map<String, String> values, requestDetails;
  final List<GlacierPipelineStage> stages;
  final VoidCallback? onBack, onOpenDocument;
  final Widget? notice;
  final String? disclaimer;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierMobileActionBar(
        children: [
          GlacierButton(label: 'All jobs', onPressed: onBack),
          if (onOpenDocument != null)
            GlacierButton(label: 'Open document', onPressed: onOpenDocument),
        ],
      ),
      _GlacierMobileWorkflowSection(
        title,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Muted(name),
            const SizedBox(height: 4),
            _Badge(status),
            _Values({'Current stage': stage, 'Library': library, ...values}),
          ],
        ),
      ),
      ?notice,
      _GlacierMobileWorkflowSection(
        'Recorded steps',
        GlacierMobilePipelineEvidence(stages: stages),
      ),
      _GlacierMobileWorkflowSection(
        'Request details',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Values(requestDetails),
            if (disclaimer != null) _Muted(disclaimer!),
          ],
        ),
      ),
    ],
  );
}

class GlacierMobileJobsScreen extends StatelessWidget {
  const GlacierMobileJobsScreen({
    super.key,
    required this.activeJobs,
    required this.recentJobs,
    this.onReindex,
    this.onSettings,
    this.onFilter,
    this.onMore,
    this.notice,
    this.activityNotice,
    this.pageError,
    this.onRetryPage,
    this.library = 'Personal library',
  });
  final List<Widget> activeJobs, recentJobs;
  final VoidCallback? onReindex, onSettings, onMore, onRetryPage;
  final ValueChanged<String>? onFilter;
  final Widget? notice, activityNotice;
  final String? pageError;
  final String library;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierMobileActionBar(
        children: [
          GlacierButton(label: 'Reindex library', onPressed: onReindex),
          GlacierButton(label: 'Processing settings', onPressed: onSettings),
        ],
      ),
      ?notice,
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final label in ['All jobs', 'Running', 'Needs attention'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlacierButton(
                    label: label,
                    onPressed: onFilter == null ? null : () => onFilter!(label),
                  ),
                ),
            ],
          ),
        ),
      ),
      _GlacierMobileWorkflowSection(
        'Activity in $library',
        Column(children: activeJobs),
      ),
      ?activityNotice,
      _GlacierMobileWorkflowSection(
        'Recent jobs',
        Column(children: recentJobs),
      ),
      if (pageError != null)
        GlacierMobileNotice(
          title: 'Older jobs could not load',
          message: pageError!,
          action: GlacierButton(
            label: 'Retry next page',
            onPressed: onRetryPage,
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: onMore == null
            ? const Center(child: _Muted('All example records are shown.'))
            : GlacierButton(label: 'Load older jobs', onPressed: onMore),
      ),
    ],
  );
}

enum GlacierMobileReindexStatus { ready, enumerating, partial, uncertain }

enum GlacierMobileReindexScope { library, installation }

class GlacierMobileReindexScreen extends StatelessWidget {
  const GlacierMobileReindexScreen({
    super.key,
    required this.scope,
    required this.libraryStatus,
    required this.installationStatus,
    required this.onScopeChanged,
    this.onStart,
    this.onCheck,
    this.onReviewJobs,
    this.onMore,
    this.history = const [],
    this.library = 'Personal library',
    this.partialMessage = 'Requests were partially accepted. Review the recorded outcome before retrying.',
    this.installationAllowed = true,
  });
  final GlacierMobileReindexScope scope;
  final GlacierMobileReindexStatus libraryStatus, installationStatus;
  final ValueChanged<GlacierMobileReindexScope>? onScopeChanged;
  final VoidCallback? onStart, onCheck, onReviewJobs, onMore;
  final List<Widget> history;
  final String library, partialMessage;
  final bool installationAllowed;
  @override
  Widget build(BuildContext context) {
    final installation = scope == GlacierMobileReindexScope.installation;
    final status = installation ? installationStatus : libraryStatus;
    final locked =
        status == GlacierMobileReindexStatus.enumerating ||
        status == GlacierMobileReindexStatus.uncertain;
    String label(GlacierMobileReindexStatus status) => switch (status) {
      GlacierMobileReindexStatus.ready => 'No active request',
      GlacierMobileReindexStatus.enumerating => 'Finding originals',
      GlacierMobileReindexStatus.partial => 'Partially completed',
      GlacierMobileReindexStatus.uncertain => 'Outcome unknown',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlacierMobileWorkflowSection(
          'Reindex originals',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Muted(
                'Start a new processing request for existing originals. Library and installation requests are tracked independently.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GlacierButton(
                    label: library,
                    onPressed: onScopeChanged == null
                        ? null
                        : () => onScopeChanged!(
                            GlacierMobileReindexScope.library,
                          ),
                    kind: !installation
                        ? GlacierButtonKind.primary
                        : GlacierButtonKind.secondary,
                  ),
                  if (installationAllowed)
                    GlacierButton(
                      label: 'All libraries',
                      onPressed: onScopeChanged == null
                          ? null
                          : () => onScopeChanged!(
                              GlacierMobileReindexScope.installation,
                            ),
                      kind: installation
                          ? GlacierButtonKind.primary
                          : GlacierButtonKind.secondary,
                    ),
                ],
              ),
              GlacierMobileNotice(
                title: installation ? 'Installation scope' : '$library only',
                message: installation
                    ? 'Includes originals in every library. Requires installation permission.'
                    : 'Only originals in the selected library are included.',
                attention: false,
              ),
              const _Muted(
                'Uses the saved document-processing configuration. Existing originals pass through the configured pipeline.',
              ),
              const SizedBox(height: 12),
              GlacierButton(
                label: 'Start reindex',
                onPressed: locked || (installation && !installationAllowed)
                    ? null
                    : onStart,
                kind: GlacierButtonKind.primary,
              ),
            ],
          ),
          first: true,
        ),
        if (status == GlacierMobileReindexStatus.enumerating)
          GlacierMobileNotice(
            title: 'Finding originals…',
            message: 'The total is not known yet. Existing documents remain available. No percentage is estimated.',
            action: GlacierButton(label: 'Check request', onPressed: onCheck),
          ),
        if (status == GlacierMobileReindexStatus.partial)
          GlacierMobileNotice(
            title: 'Partially completed',
            message: partialMessage,
            action: GlacierButton(
              label: 'Review jobs',
              onPressed: onReviewJobs,
            ),
          ),
        if (status == GlacierMobileReindexStatus.uncertain)
          GlacierMobileNotice(
            title: 'Request outcome unknown',
            message: 'Check the same request before starting another. Your chosen scope and request are retained.',
            action: GlacierButton(label: 'Check request', onPressed: onCheck),
          ),
        _GlacierMobileWorkflowSection(
          'Independent scope status',
          _Values({
            library: label(libraryStatus),
            'Installation': label(installationStatus),
          }),
        ),
        _GlacierMobileWorkflowSection(
          'Request history',
          Column(
            children: [
              for (final item in history)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: item),
            ],
          ),
        ),
        if (onMore != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: GlacierButton(
              label: 'Load older requests',
              onPressed: onMore,
            ),
          ),
      ],
    );
  }
}
