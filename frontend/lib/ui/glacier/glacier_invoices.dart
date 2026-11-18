import 'package:flutter/material.dart';

import '../app_paged_list.dart';
import '../app_presenters.dart';
import 'glacier_controls.dart';
import 'glacier_documents.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';

@immutable
final class GlacierInvoiceValue {
  const GlacierInvoiceValue({
    required this.number,
    required this.supplier,
    required this.amount,
    required this.currency,
    this.issueDate = '',
    this.dueDate = '',
    this.provenance = 'E-invoice',
    this.type = 'Invoice',
    this.aiExtracted = false,
    this.amountLabel,
  });
  final String number,
      supplier,
      amount,
      currency,
      issueDate,
      dueDate,
      provenance,
      type;
  final bool aiExtracted;
  final String? amountLabel;
}

final class GlacierInvoiceRow extends StatelessWidget {
  const GlacierInvoiceRow({
    super.key,
    required this.invoice,
    this.onOpen,
    this.openKey,
  });
  final Key? openKey;
  final GlacierInvoiceValue invoice;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: GlacierTokens.of(context).border),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, size) {
            final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.supplier.isEmpty
                      ? 'Supplier not recorded'
                      : invoice.supplier,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${invoice.type} ${invoice.number.isEmpty ? '· number not recorded' : invoice.number}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
            final amount = SelectableText(
              invoice.amountLabel ??
                  (invoice.amount.isEmpty
                      ? 'Amount not recorded'
                      : '${invoice.amount} ${invoice.currency}'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: size.maxWidth < 650 ? TextAlign.left : TextAlign.right,
            );
            final provenance = GlacierTag(label: invoice.provenance);
            if (size.maxWidth < 650) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      provenance,
                      Text(
                        'Issued ${invoice.issueDate.isEmpty ? 'not recorded' : invoice.issueDate}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Due ${invoice.dueDate.isEmpty ? 'not recorded' : invoice.dueDate}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  amount,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: identity),
                Expanded(
                  child: Text(
                    invoice.issueDate.isEmpty
                        ? 'Not recorded'
                        : invoice.issueDate,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    invoice.dueDate.isEmpty ? 'Not recorded' : invoice.dueDate,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: provenance,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: amount),
                const SizedBox(width: 8),
                GlacierIconButton(
                  key: openKey,
                  label: 'Open invoice ${invoice.number}',
                  onPressed: onOpen,
                  icon: Icons.chevron_right,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

final class GlacierInvoiceSection extends StatelessWidget {
  const GlacierInvoiceSection({
    super.key,
    required this.title,
    required this.values,
  });
  final String title;
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        GlacierPropertyGrid(values: values, minimumWidth: 220),
      ],
    ),
  );
}

@immutable
final class GlacierInvoiceDetailRecord {
  const GlacierInvoiceDetailRecord({
    required this.title,
    required this.values,
    this.action,
  });
  final String title;
  final Map<String, String> values;
  final Widget? action;
}

final class GlacierInvoiceRecords extends StatelessWidget {
  const GlacierInvoiceRecords({
    super.key,
    required this.title,
    required this.records,
    this.pageSize = 20,
    this.hasMore = false,
    this.onLoadMore,
  });
  final String title;
  final List<GlacierInvoiceDetailRecord> records;
  final int pageSize;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      AppPagedList(
        key: ValueKey(title),
        itemCount: records.length,
        pageSize: pageSize,
        hasMore: hasMore,
        onLoadMore: onLoadMore,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                records[index].title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              GlacierPropertyGrid(
                values: records[index].values,
                minimumWidth: 180,
              ),
              if (records[index].action != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: records[index].action!,
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

final class GlacierInvoiceDetails extends StatelessWidget {
  const GlacierInvoiceDetails({
    super.key,
    required this.title,
    required this.sourceLabel,
    required this.sections,
    this.aiExtracted = false,
    this.onOpenOriginal,
    this.onClose,
    this.feedback,
    this.subtitle,
    this.sourceMessage,
    this.showSourceNotice = true,
    this.closeKey,
    this.openOriginalKey,
  });
  final String title, sourceLabel;
  final List<Widget> sections;
  final bool aiExtracted;
  final VoidCallback? onOpenOriginal, onClose;
  final Widget? feedback;
  final String? subtitle, sourceMessage;
  final bool showSourceNotice;
  final Key? closeKey, openOriginalKey;
  @override
  Widget build(BuildContext context) => GlacierDialog(
    title: title,
    width: 900,
    actions: [
      if (MediaQuery.sizeOf(context).height < 520 && onOpenOriginal != null)
        _openButton(),
      GlacierButton(key: closeKey, label: 'Close', onPressed: onClose),
      if (MediaQuery.sizeOf(context).height >= 520 && onOpenOriginal != null)
        _openButton(),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (showSourceNotice)
          AppNotice(
            tone: aiExtracted ? AppTone.warning : AppTone.neutral,
            message:
                sourceMessage ??
                (aiExtracted
                    ? '$sourceLabel · Review extracted values against the original. Missing or incorrect values are possible.'
                    : '$sourceLabel · Values come from structured invoice data. This does not confirm legal validity.'),
          ),
        const SizedBox(height: 24),
        ?feedback,
        ...sections,
      ],
    ),
  );
  Widget _openButton() => GlacierButton(
    key: openOriginalKey,
    label: 'Open original',
    icon: Icons.description_outlined,
    kind: GlacierButtonKind.primary,
    onPressed: onOpenOriginal,
  );
}
