import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/invoice/models/invoice.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/invoices_cubit.dart';
import 'invoice_labels.dart';

Future<String?> showInvoiceDetails(
  BuildContext context, {
  required InvoiceDetailCubit cubit,
  required bool canOpenDocument,
}) async {
  unawaited(cubit.load());
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) =>
          InvoiceDetailsDialog(cubit: cubit, canOpenDocument: canOpenDocument),
    );
  } finally {
    await cubit.close();
  }
}

final class InvoiceDetailsDialog extends StatelessWidget {
  const InvoiceDetailsDialog({
    super.key,
    required this.cubit,
    required this.canOpenDocument,
  });
  final InvoiceDetailCubit cubit;
  final bool canOpenDocument;

  Future<void> _reference(BuildContext context, String id) async {
    final documentId = await showInvoiceDetails(
      context,
      cubit: cubit.reference(id),
      canOpenDocument: canOpenDocument,
    );
    if (context.mounted && documentId != null) {
      Navigator.of(context).pop(documentId);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<InvoiceDetailCubit, InvoiceDetailState>(
    bloc: cubit,
    builder: (context, state) {
      final invoice = state.invoice;
      return AppDialog(
        width: 860,
        title: invoice == null || invoice.number.isEmpty
            ? 'Invoice details'
            : '${invoiceType(invoice.typeCode)} ${invoice.number}',
        description: invoice?.documentTitle,
        actions: [
          TextButton(
            key: const Key('closeInvoiceDetails'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (canOpenDocument && invoice != null)
            FilledButton.icon(
              key: const Key('openInvoiceDocument'),
              onPressed: () => Navigator.of(context).pop(invoice.documentId),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Open original'),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppProgressSlot(active: state.loading),
            const SizedBox(height: 12),
            if (state.error case final error?) ...[
              AppNotice(
                message: error,
                action: TextButton(
                  onPressed: state.loading ? null : cubit.load,
                  child: const Text('Try again'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (invoice != null) ...[
              AppNotice(
                tone: invoice.structured ? AppTone.neutral : AppTone.warning,
                message: invoice.structured
                    ? 'E-invoice · ${invoiceFormat(invoice.format)}. These values come from structured invoice data. This does not confirm the invoice’s legal validity.'
                    : 'AI extracted · Review these details against the original document before using them. Missing or incorrect values are possible.',
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _InvoiceDetailFields([
                  (
                    'Total including tax',
                    invoiceAmount(invoice.totalGross, invoice.currency),
                  ),
                  (
                    'Amount due',
                    invoiceAmount(invoice.amountDue, invoice.currency),
                  ),
                  ('Invoice date', invoice.issueDate),
                  ('Due date', invoice.dueDate),
                ], prominent: true),
              ),
              _InvoiceDetailSection(
                title: 'Supplier',
                child: _InvoicePartyView(invoice.seller),
              ),
              _InvoiceDetailSection(
                title: 'Customer',
                child: _InvoicePartyView(invoice.buyer),
              ),
              _InvoiceDetailSection(
                title: 'Amounts',
                child: _InvoiceDetailFields([
                  (
                    'Net total',
                    invoiceAmount(invoice.totalNet, invoice.currency),
                  ),
                  (
                    'Tax total',
                    invoiceAmount(invoice.totalTax, invoice.currency),
                  ),
                  (
                    'Paid amount',
                    invoiceAmount(invoice.paidAmount, invoice.currency),
                  ),
                  (
                    'Rounding',
                    invoiceAmount(invoice.roundingAmount, invoice.currency),
                  ),
                  if (invoice.taxAccountingAmount.isNotEmpty ||
                      invoice.taxCurrency.isNotEmpty)
                    (
                      'Tax in accounting currency',
                      invoiceAmount(
                        invoice.taxAccountingAmount,
                        invoice.taxCurrency,
                      ),
                    ),
                ]),
              ),
              if (invoice.references.isNotEmpty)
                _InvoiceDetailSection(
                  title: 'Referenced invoices',
                  child: AppPagedList(
                    key: ValueKey('invoiceReferences-${invoice.id}'),
                    itemCount: invoice.references.length,
                    itemBuilder: (context, index) {
                      final reference = invoice.references[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reference.number.isEmpty
                                  ? 'Invoice number not recorded'
                                  : reference.number,
                            ),
                            if (reference.issueDate.isNotEmpty)
                              Text(reference.issueDate),
                            if (reference.invoiceId case final id?
                                when id != invoice.id)
                              TextButton.icon(
                                key: ValueKey('openInvoiceReference-$index'),
                                onPressed: () => _reference(context, id),
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: const Text('Open referenced invoice'),
                              )
                            else if (canOpenDocument &&
                                reference.documentId != null)
                              TextButton.icon(
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pop(reference.documentId),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Open referenced document'),
                              )
                            else
                              Text(
                                'No linked invoice in this library',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              if (invoice.lines.isNotEmpty)
                _InvoiceDetailSection(
                  title: 'Line items',
                  child: AppPagedList(
                    key: ValueKey('invoiceLines-${invoice.id}'),
                    itemCount: invoice.lines.length,
                    itemBuilder: (context, index) {
                      final line = invoice.lines[index];
                      return _InvoiceDetailRecord(
                        title: line.description.isEmpty
                            ? 'Line ${index + 1}'
                            : line.description,
                        fields: [
                          ('Line', line.id),
                          (
                            'Quantity',
                            '${line.quantity} ${line.unitCode}'.trim(),
                          ),
                          (
                            'Unit price',
                            invoiceAmount(line.unitPrice, invoice.currency),
                          ),
                          (
                            'Net amount',
                            invoiceAmount(line.netAmount, invoice.currency),
                          ),
                          ('Tax category', line.taxCategory),
                          (
                            'Tax rate',
                            line.taxRate.isEmpty ? '' : '${line.taxRate}%',
                          ),
                        ],
                      );
                    },
                  ),
                ),
              if (invoice.taxes.isNotEmpty)
                _InvoiceDetailSection(
                  title: 'Tax breakdown',
                  child: AppPagedList(
                    key: ValueKey('invoiceTaxes-${invoice.id}'),
                    itemCount: invoice.taxes.length,
                    itemBuilder: (context, index) {
                      final tax = invoice.taxes[index];
                      return _InvoiceDetailRecord(
                        title: tax.category.isEmpty
                            ? 'Tax ${index + 1}'
                            : 'Category ${tax.category}',
                        fields: [
                          ('Rate', tax.rate.isEmpty ? '' : '${tax.rate}%'),
                          (
                            'Taxable amount',
                            invoiceAmount(tax.taxableAmount, invoice.currency),
                          ),
                          (
                            'Tax amount',
                            invoiceAmount(tax.taxAmount, invoice.currency),
                          ),
                          if (tax.exemptionReason.isNotEmpty)
                            ('Exemption reason', tax.exemptionReason),
                        ],
                      );
                    },
                  ),
                ),
              if (invoice.allowances.isNotEmpty)
                _InvoiceDetailSection(
                  title: 'Allowances and charges',
                  child: AppPagedList(
                    key: ValueKey('invoiceAllowances-${invoice.id}'),
                    itemCount: invoice.allowances.length,
                    itemBuilder: (context, index) {
                      final allowance = invoice.allowances[index];
                      return _InvoiceDetailRecord(
                        title: allowance.charge ? 'Charge' : 'Allowance',
                        fields: [
                          ('Reason', allowance.reason),
                          (
                            'Amount',
                            invoiceAmount(allowance.amount, invoice.currency),
                          ),
                          ('Tax category', allowance.taxCategory),
                          (
                            'Tax rate',
                            allowance.taxRate.isEmpty
                                ? ''
                                : '${allowance.taxRate}%',
                          ),
                        ],
                      );
                    },
                  ),
                ),
              _InvoiceDetailSection(
                title: 'Payment details',
                child: _InvoiceDetailFields([
                  ('Payment means code', invoice.payment.meansCode),
                  ('Payment reference', invoice.payment.reference),
                  ('IBAN', invoice.payment.iban),
                  ('BIC', invoice.payment.bic),
                  ('Terms', invoice.payment.terms),
                ]),
              ),
              if (invoice.notes.isNotEmpty)
                _InvoiceDetailSection(
                  title: 'Notes',
                  child: AppPagedList(
                    key: ValueKey('invoiceNotes-${invoice.id}'),
                    itemCount: invoice.notes.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText(
                        invoice.notes[index],
                        semanticsLabel: invoice.notes[index],
                      ),
                    ),
                  ),
                ),
              _InvoiceDetailSection(
                title: 'Source',
                child: _InvoiceDetailFields([
                  ('Document', invoice.documentTitle),
                  ('Format', invoiceFormat(invoice.format)),
                  if (invoice.profile.isNotEmpty) ('Profile', invoice.profile),
                  if (invoice.extractionModel.isNotEmpty)
                    ('Extraction model', invoice.extractionModel),
                ]),
              ),
            ] else if (state.loading)
              const Text('Loading invoice details…'),
          ],
        ),
      );
    },
  );
}

final class _InvoiceDetailSection extends StatelessWidget {
  const _InvoiceDetailSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

final class _InvoicePartyView extends StatelessWidget {
  const _InvoicePartyView(this.party);
  final InvoiceParty party;

  @override
  Widget build(BuildContext context) => _InvoiceDetailFields([
    ('Name', party.name),
    ('Address', party.address),
    ('Country', party.country),
    ('Tax ID', party.taxId),
    ('Registration ID', party.registrationId),
    ('Email', party.email),
  ]);
}

final class _InvoiceDetailFields extends StatelessWidget {
  const _InvoiceDetailFields(this.values, {this.prominent = false});
  final List<(String, String)> values;
  final bool prominent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 520 &&
              MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 16,
        children: [
          for (final (label, value) in values)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value.isEmpty ? 'Not recorded' : value,
                    semanticsLabel:
                        '$label: ${value.isEmpty ? 'Not recorded' : value}',
                    style: prominent
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

final class _InvoiceDetailRecord extends StatelessWidget {
  const _InvoiceDetailRecord({required this.title, required this.fields});
  final String title;
  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            title,
            semanticsLabel: title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          _InvoiceDetailFields(fields),
        ],
      ),
    ),
  );
}
