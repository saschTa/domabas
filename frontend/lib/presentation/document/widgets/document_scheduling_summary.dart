import 'package:flutter/material.dart';

import '../../../domain/document/models/document_processing.dart';
import '../../../ui/domabas_ui.dart';

final class DocumentSchedulingSummary extends StatelessWidget {
  const DocumentSchedulingSummary({
    super.key,
    this.scheduling,
    this.initiallyExpanded = false,
  });

  final DocumentProcessingScheduling? scheduling;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => AppSurface(
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Shared resource limits',
            description: 'Background jobs wait for shared worker and AI provider capacity. New imports do not interrupt running jobs.',
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            key: const PageStorageKey('processingSchedulingDetails'),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: initiallyExpanded,
            title: const Text('Resource requirements'),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paperless imports, email retrievals and thumbnail generation need workers. Document ingestion and full reindexing also need Ollama for embeddings. Document AI and chat share their configured provider.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Administrators manage shared capacity and view pipeline resource requirements in Admin settings → Workload limits.',
              ),
              if (scheduling case final policy?) ...[
                const SizedBox(height: 12),
                Text(
                  'Provider steps in new workflows retry temporary Ollama or external provider failures up to ${policy.providerStepRetries} times after the first request, with waits between attempts. Retries stay within the current job attempt.',
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}
