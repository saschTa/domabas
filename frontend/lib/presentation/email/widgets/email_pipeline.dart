import 'package:flutter/material.dart';

import '../../../ui/domabas_ui.dart';
import 'email_pipeline_diagram.dart';

final class EmailPipeline extends StatelessWidget {
  const EmailPipeline({super.key});

  @override
  Widget build(BuildContext context) => AppSurface(
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
