import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';

const _resources = {
  'pipeline:document_ingestion': (label: 'Document ingestion', initial: 4),
  'pipeline:invoice': (label: 'Invoice extraction', initial: 2),
  'pipeline:tags': (label: 'Tags and properties', initial: 2),
  'pipeline:document_ai': (label: 'Document enrichment', initial: 4),
  'pipeline:document_thumbnail': (label: 'Document thumbnails', initial: 2),
  'pipeline:chat': (label: 'AI chat', initial: 4),
  'pipeline:email': (label: 'Email retrieval', initial: 2),
  'pipeline:paperless': (label: 'Paperless imports', initial: 2),
  'worker': (label: 'Worker', initial: 8),
  'stage:thumbnail': (label: 'Thumbnail rendering', initial: 2),
  'stage:ocr': (label: 'Text recognition', initial: 2),
  'stage:embedding': (label: 'Embeddings', initial: 2),
  'stage:llm': (label: 'Language model calls', initial: 2),
  'stage:paperless': (label: 'Paperless downloads', initial: 2),
  'ollama': (label: 'Ollama', initial: 1),
  'external': (
    label: 'https://ai.example.test (external API provider)',
    initial: 1,
  ),
};

class SampleWorkload {
  SampleWorkload({this.ingestions = 3, int workerLimit = 8})
    : limits = {
        for (final entry in _resources.entries) entry.key: entry.value.initial,
        'worker': workerLimit,
      };

  int ingestions;
  final Map<String, int> limits;

  String label(String id) => _resources[id]!.label;

  int maximum(String id) => switch (id) {
    'worker' => 16,
    'ollama' => 4,
    'external' => 8,
    'stage:paperless' => 10,
    _ => 256,
  };

  String? validate(String id, String draft) {
    final value = int.tryParse(draft);
    return value == null || value < 1 || value > maximum(id)
        ? 'Enter a whole number from 1 to ${maximum(id)}.'
        : null;
  }

  Map<String, Map<String, int>> get _shares {
    final embedding = ingestions > 0 ? 1 : 0;
    final ocr = (ingestions - embedding).clamp(0, 2);
    final preview = (ingestions - embedding - ocr).clamp(0, 2);
    final inference = 1 - embedding;
    return {
      'document_ingestion': {
        'worker': ingestions,
        'stage:thumbnail': preview,
        'stage:ocr': ocr,
        'stage:embedding': embedding,
        'ollama': embedding,
      },
      'invoice': {'stage:llm': inference, 'ollama': inference},
      'tags': {'stage:llm': 0, 'ollama': 0},
      'document_ai': {'worker': 3, 'pipeline:invoice': 3, 'pipeline:tags': 0},
      'document_thumbnail': {'worker': 0, 'stage:thumbnail': 0},
      'chat': {'stage:llm': 0, 'external': 0},
      'email': {'worker': 0},
      'paperless': {'worker': 1, 'stage:paperless': 2},
    };
  }

  int active(String id) => switch (id) {
    'pipeline:document_ingestion' => ingestions,
    'pipeline:document_ai' => 3,
    'pipeline:paperless' => 1,
    _ => _shares.values.fold(0, (sum, slots) => sum + (slots[id] ?? 0)),
  };

  List<GlacierFlowPipeline> get pipelines => [
    for (final pipeline in _shares.entries)
      (
        id: pipeline.key,
        label: label('pipeline:${pipeline.key}'),
        active: active('pipeline:${pipeline.key}'),
        limit: limits['pipeline:${pipeline.key}'],
        resources: [
          for (final slot in pipeline.value.entries)
            (
              id: slot.key,
              label: label(slot.key),
              active: active(slot.key),
              limit: limits[slot.key]!,
              fromPipeline: slot.value,
            ),
        ],
      ),
  ];
}

class WorkloadFlowPreview extends StatelessWidget {
  const WorkloadFlowPreview({
    super.key,
    required this.sample,
    required this.onLoad,
  });
  final SampleWorkload sample;
  final ValueChanged<int> onLoad;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierWorkloadFlow(pipelines: sample.pipelines),
      const SizedBox(height: 16),
      Text('Simulated ingestions · ${sample.ingestions}'),
      Slider(
        value: sample.ingestions.toDouble(),
        max: 8,
        divisions: 8,
        semanticFormatterCallback: (value) =>
            '${value.round()} active ingestions',
        label: '${sample.ingestions}',
        onChanged: (value) => onLoad(value.round()),
      ),
    ],
  );
}

class WorkloadFlowExample extends StatefulWidget {
  const WorkloadFlowExample({super.key, this.phone = false});
  final bool phone;
  @override
  State<WorkloadFlowExample> createState() => _WorkloadFlowExampleState();
}

class _WorkloadFlowExampleState extends State<WorkloadFlowExample> {
  final sample = SampleWorkload();
  @override
  Widget build(BuildContext context) => Material(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.phone ? 358 : 900),
          child: WorkloadFlowPreview(
            sample: sample,
            onLoad: (value) => setState(() => sample.ingestions = value),
          ),
        ),
      ),
    ),
  );
}
