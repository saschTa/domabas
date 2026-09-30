import 'dart:math' as math;

import 'package:flutter/material.dart';

final class InvoiceSearchControls extends StatelessWidget {
  const InvoiceSearchControls({
    super.key,
    required this.term,
    required this.onSubmit,
    required this.onClear,
    this.error,
    this.blocked = false,
  });

  final TextEditingController term;
  final VoidCallback onSubmit, onClear;
  final String? error;
  final bool blocked;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outline,
        width: 1.5,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          double buttonWidth(String label) {
            final painter = TextPainter(
              text: TextSpan(
                text: label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              textScaler: MediaQuery.textScalerOf(context),
              textDirection: Directionality.of(context),
            )..layout();
            final width = painter.width + 64;
            painter.dispose();
            return width;
          }

          final actionWidth =
              buttonWidth('Search') + buttonWidth('Clear search') + 16;
          final wide =
              constraints.maxWidth >= 720 &&
              constraints.maxWidth - actionWidth >= 280;
          final width = math.min(
            560.0,
            constraints.maxWidth - (wide ? actionWidth : 0),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: width,
                    child: TextField(
                      key: const Key('invoiceSearchTerm'),
                      controller: term,
                      textInputAction: TextInputAction.search,
                      onEditingComplete: () {
                        final composing = term.value.composing;
                        if (!composing.isValid || composing.isCollapsed) {
                          FocusScope.of(context).unfocus();
                        }
                      },
                      onSubmitted: (_) => onSubmit(),
                      decoration: InputDecoration(
                        labelText: 'Search invoices',
                        prefixIcon: const Tooltip(
                          message: 'Search invoice numbers, parties, line items, payment details, references and notes',
                          child: Icon(Icons.search),
                        ),
                        suffixIcon: term.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search text',
                                onPressed: onClear,
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                  if (wide)
                    FilledButton.icon(
                      key: const Key('applyInvoiceSearch'),
                      onPressed: blocked ? null : onSubmit,
                      icon: const Icon(Icons.search),
                      label: const Text('Search'),
                    )
                  else
                    IconButton.filled(
                      key: const Key('applyInvoiceSearch'),
                      tooltip: 'Search',
                      onPressed: blocked ? null : onSubmit,
                      icon: const Icon(Icons.search),
                    ),
                  if (wide)
                    TextButton(
                      key: const Key('clearInvoiceSearch'),
                      onPressed: term.text.isEmpty ? null : onClear,
                      child: const Text('Clear search'),
                    )
                  else
                    IconButton(
                      key: const Key('clearInvoiceSearch'),
                      tooltip: 'Clear search',
                      onPressed: term.text.isEmpty ? null : onClear,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                    ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
