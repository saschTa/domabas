import 'package:flutter/material.dart';

import 'email_pipeline_diagram.dart';

final class EmailPipeline extends StatelessWidget {
  const EmailPipeline({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: ExpansionTile(
      key: const PageStorageKey('emailPipeline'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Email import pipeline'),
      subtitle: const Text(
        'Mailbox checks → email and attachments → document ingestion',
      ),
      children: const [SizedBox(height: 16), EmailPipelineDiagram()],
    ),
  );
}
