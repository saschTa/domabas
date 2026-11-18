import 'package:flutter/material.dart';

import '../app_presenters.dart';
import '../app_job_progress.dart';
import '../app_theme.dart';
import 'glacier_controls.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';
import 'glacier_native_values.dart';
import 'glacier_workspace_geometry.dart';
import 'glacier_interaction.dart';
import 'glacier_preview_placeholder.dart';

@immutable
final class GlacierDocumentValue {
  const GlacierDocumentValue({
    required this.id,
    required this.title,
    this.sender = '',
    this.date = '',
    this.type = 'PDF',
    this.tags = const [],
    this.status = '',
    this.busy = false,
    this.failed = false,
    this.statusIcon = Icons.info_outline,
    this.pages = 0,
    this.snippet,
  });
  final String id, title, sender, date, type, status;
  final List<String> tags;
  final bool busy, failed;
  final IconData statusIcon;
  final int pages;
  final String? snippet;
}

final class GlacierDocumentCard extends StatelessWidget {
  const GlacierDocumentCard({
    super.key,
    required this.document,
    required this.preview,
    this.onOpen,
    this.onRetry,
    this.onRetryPreview,
    this.focusNode,
    this.previewOverlay,
    this.semanticLabel,
    this.titleLines = 1,
  });
  final FocusNode? focusNode;
  final Widget? previewOverlay;
  final String? semanticLabel;
  final int titleLines;
  final GlacierDocumentValue document;
  final Widget preview;
  final VoidCallback? onOpen, onRetry, onRetryPreview;
  @override
  Widget build(BuildContext context) => glacierInteractionOutline(
    enabled: onOpen != null,
    radius: 15,
    builder: (states, hovered) => GlacierSurface(
      borderColor: hovered ? GlacierTokens.of(context).accent : null,
      padding: const EdgeInsets.all(8),
      radius: 15,
      surface: true,
      blur: false,
      child: SizedBox(
        height:
            (GlacierNativePresentationScope.maybeOf(context)?.viewport.width ??
                    1000) <=
                420
            ? 310 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 5
            : 280 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 5,
        child: Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  focusNode: focusNode,
                  statesController: states,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  onTap: onOpen,
                  excludeFromSemantics: true,
                  borderRadius: BorderRadius.circular(16),
                  child: Semantics(
                    container: true,
                    button: true,
                    enabled: onOpen != null,
                    onTap: onOpen,
                    value: semanticLabel == null
                        ? null
                        : [
                            document.sender,
                            document.date,
                            document.tags.join(', '),
                            document.status,
                            document.snippet ?? '',
                          ].where((value) => value.isNotEmpty).join('. '),
                    label:
                        semanticLabel ??
                        'Open ${document.title}. ${document.sender}. ${document.date}. ${document.tags.join(', ')}. ${document.status}',
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            flex:
                                GlacierNativePresentationScope.maybeOf(
                                      context,
                                    ) ==
                                    null
                                ? 1
                                : 0,
                            fit: FlexFit.tight,
                            child: SizedBox(
                              height:
                                  GlacierNativePresentationScope.maybeOf(
                                        context,
                                      ) ==
                                      null
                                  ? null
                                  : GlacierNativePresentationScope.maybeOf(
                                          context,
                                        )!.viewport.width <=
                                        420
                                  ? 210
                                  : 180,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ExcludeSemantics(
                                      child:
                                          GlacierNativePresentationScope.maybeOf(
                                                context,
                                              ) ==
                                              null
                                          ? preview
                                          : MediaQuery.withNoTextScaling(
                                              child: preview,
                                            ),
                                    ),
                                    Positioned(
                                      top: 9,
                                      left: 9,
                                      child: _DocumentPreviewLabel(
                                        document.type,
                                      ),
                                    ),
                                    ?previewOverlay,
                                    if (document.pages > 0)
                                      Positioned(
                                        bottom: 8,
                                        right: 9,
                                        child: _DocumentPreviewLabel(
                                          '${document.pages} ${document.pages == 1 ? 'page' : 'pages'}',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Flexible(
                            flex:
                                GlacierNativePresentationScope.maybeOf(
                                      context,
                                    ) ==
                                    null
                                ? 0
                                : 1,
                            fit: FlexFit.tight,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(7, 9, 7, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    document.title,
                                    maxLines:
                                        GlacierNativePresentationScope.maybeOf(
                                                  context,
                                                ) !=
                                                null &&
                                            MediaQuery.textScalerOf(context)
                                                    .scale(14) >
                                                20
                                        ? 2
                                        : titleLines,
                                    overflow:
                                        GlacierNativePresentationScope.maybeOf(
                                                  context,
                                                ) !=
                                                null &&
                                            MediaQuery.textScalerOf(context)
                                                    .scale(14) >
                                                20
                                        ? TextOverflow.clip
                                        : TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    document.sender.isEmpty
                                        ? document.type
                                        : document.sender,
                                    maxLines:
                                        GlacierNativePresentationScope.maybeOf(
                                                  context,
                                                ) !=
                                                null &&
                                            MediaQuery.textScalerOf(context)
                                                    .scale(14) >
                                                20
                                        ? 2
                                        : 1,
                                    overflow:
                                        GlacierNativePresentationScope.maybeOf(
                                                  context,
                                                ) !=
                                                null &&
                                            MediaQuery.textScalerOf(context)
                                                    .scale(14) >
                                                20
                                        ? TextOverflow.clip
                                        : TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if (document.snippet case final snippet?) ...[
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      height:
                                          MediaQuery.textScalerOf(context)
                                              .scale(12) *
                                          2.6,
                                      child: Text(
                                        snippet,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ],
                                  if (GlacierNativePresentationScope.maybeOf(
                                        context,
                                      ) !=
                                      null)
                                    const Spacer()
                                  else
                                    const SizedBox(height: 14),
                                  Row(
                                    crossAxisAlignment:
                                        GlacierNativePresentationScope.maybeOf(
                                              context,
                                            ) ==
                                            null
                                        ? CrossAxisAlignment.center
                                        : CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            for (final tag
                                                in document.tags.take(3))
                                              Flexible(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                  child: Tooltip(
                                                    message: tag,
                                                    child:
                                                        DefaultTextStyle.merge(
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          child: GlacierTag(
                                                            label: tag,
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            if (document.tags.length > 3)
                                              Text(
                                                '+${document.tags.length - 3}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          document.date,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 7,
              right: 7,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                child: document.failed
                    ? Tooltip(
                        message: 'Retry processing ${document.title}',
                        excludeFromSemantics: true,
                        child: glacierInteractionOutline(
                          enabled: onRetry != null,
                          radius: 8,
                          builder: (retryStates, _) => TextButton.icon(
                            statesController: retryStates,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(28, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: AppSemanticColors.of(context)
                                  .warningContainer,
                              foregroundColor: AppSemanticColors.of(context)
                                  .onWarningContainer,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: Text(
                              'Retry',
                              semanticsLabel:
                                  'Retry processing ${document.title}',
                            ),
                            onPressed: onRetry,
                          ),
                        ),
                      )
                    : document.busy
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: AppJobSpinner(
                          label: document.status.isEmpty
                              ? 'Processing'
                              : document.status,
                        ),
                      )
                    : document.status.isNotEmpty
                    ? Tooltip(
                        message: document.status,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(document.statusIcon, size: 16),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (onRetryPreview != null)
              Positioned(
                right: 7,
                top: 47,
                child: GlacierPreviewRetry(
                  onPressed: onRetryPreview!,
                  semanticLabel: 'Retry preview ${document.title}',
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

final class _DocumentPreviewLabel extends StatelessWidget {
  const _DocumentPreviewLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: GlacierTokens.of(context).solid.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.25,
          color: GlacierTokens.of(context).muted,
        ),
      ),
    ),
  );
}

final class GlacierDocumentRow extends StatelessWidget {
  const GlacierDocumentRow({
    super.key,
    required this.document,
    this.onOpen,
    this.onRetry,
    this.onRetryPreview,
    this.preview,
    this.focusNode,
  });
  final Widget? preview;
  final FocusNode? focusNode;
  final GlacierDocumentValue document;
  final VoidCallback? onOpen, onRetry, onRetryPreview;
  @override
  Widget build(BuildContext context) => GlacierSurface(
    surface: true,
    blur: false,
    radius: 10,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final information = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              document.title,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            if (document.sender.isNotEmpty)
              Text(
                document.sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (document.snippet case final snippet?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (constraints.maxWidth < 650) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ...document.tags
                      .take(2)
                      .map(
                        (tag) => DefaultTextStyle.merge(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: GlacierTag(label: tag),
                        ),
                      ),
                  if (document.tags.length > 2)
                    Text('+${document.tags.length - 2}'),
                  Text(
                    document.date,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (document.status.isNotEmpty)
              Text(
                document.status,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );
        return Row(
          children: [
            Container(
              width: 56,
              height: 72,
              decoration: BoxDecoration(
                color: GlacierTokens.of(context).preview,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  preview ??
                      Icon(
                        document.type == 'EML'
                            ? Icons.mail_outline
                            : Icons.description_outlined,
                        size: 22,
                        color: GlacierTokens.of(context).muted,
                      ),
                  if (onRetryPreview != null)
                    Positioned(
                      left: 4,
                      bottom: 0,
                      child: GlacierPreviewRetry(
                        compact: true,
                        onPressed: onRetryPreview!,
                        semanticLabel: 'Retry preview ${document.title}',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: InkWell(
                focusNode: focusNode,
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: information,
                ),
              ),
            ),
            if (constraints.maxWidth >= 650) ...[
              SizedBox(
                width: 180,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: document.tags
                      .map((tag) => GlacierTag(label: tag))
                      .toList(),
                ),
              ),
              SizedBox(
                width: 65,
                child: Text(
                  document.date,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (document.busy)
              AppJobSpinner(
                label: document.status.isEmpty ? 'Processing' : document.status,
              ),
            if (document.failed)
              GlacierIconButton(
                label: 'Retry processing ${document.title}',
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            GlacierIconButton(
              label: 'Open ${document.title}',
              icon: Icons.chevron_right,
              onPressed: onOpen,
            ),
          ],
        );
      },
    ),
  );
}

final class GlacierDocumentCollection extends StatelessWidget {
  const GlacierDocumentCollection({
    super.key,
    required this.documents,
    required this.previewBuilder,
    this.onOpen,
    this.onRetry,
    this.toolbar,
    this.feedback,
    this.pagination,
    this.list = false,
    this.empty,
  });
  final List<GlacierDocumentValue> documents;
  final Widget Function(GlacierDocumentValue) previewBuilder;
  final ValueChanged<String>? onOpen, onRetry;
  final Widget? toolbar, feedback, pagination, empty;
  final bool list;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?toolbar,
      if (feedback != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: feedback,
        ),
      Expanded(
        child: documents.isEmpty
            ? Center(
                child:
                    empty ??
                    const AppEmptyState(
                      icon: Icons.description_outlined,
                      title: 'No documents yet',
                      message:
                          'Upload an original or create a document to begin.',
                    ),
              )
            : LayoutBuilder(
                builder: (context, size) {
                  final native = GlacierNativePresentationScope.maybeOf(
                    context,
                  );
                  final columns = native == null
                      ? (size.maxWidth / 265).floor().clamp(1, 5)
                      : native.viewport.width <= 420 ||
                            native.compact &&
                                MediaQuery.textScalerOf(context).scale(14) > 20
                      ? 1
                      : native.compact ||
                            MediaQuery.textScalerOf(context).scale(14) > 20
                      ? 2
                      : native.viewport.width >= 1650
                      ? 5
                      : native.viewport.width <= 1300
                      ? 3
                      : 4;
                  double? nativeExtent;
                  if (native != null) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final styles = Theme.of(context).textTheme;
                    final textWidth =
                        (size.maxWidth -
                                (native.compact ? 0 : 40) -
                                17 * (columns - 1)) /
                            columns -
                        32;
                    double measure(
                      String text,
                      TextStyle? style,
                      double width, {
                      int? maxLines,
                    }) {
                      final painter = TextPainter(
                        text: TextSpan(text: text, style: style),
                        textDirection: Directionality.of(context),
                        textScaler: scaler,
                        maxLines: maxLines,
                      )..layout(maxWidth: width.clamp(1, double.infinity));
                      final height = painter.height;
                      painter.dispose();
                      return height;
                    }

                    var bodyHeight = 0.0;
                    for (final document in documents) {
                      final lines = scaler.scale(14) > 20 ? 2 : 1;
                      final titleHeight = measure(
                        document.title,
                        styles.titleSmall,
                        textWidth,
                        maxLines: lines,
                      );
                      final senderHeight = measure(
                        document.sender.isEmpty
                            ? document.type
                            : document.sender,
                        styles.bodySmall,
                        textWidth,
                        maxLines: lines,
                      );
                      final tags = document.tags.take(2).toList();
                      var footerHeight = measure(
                        document.date,
                        styles.labelSmall,
                        textWidth,
                      );
                      final datePainter = TextPainter(
                        text: TextSpan(
                          text: document.date,
                          style: styles.labelSmall,
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: scaler,
                      )..layout();
                      final tagWidth = tags.isEmpty
                          ? textWidth
                          : (textWidth - datePainter.width - 4) / tags.length -
                                16;
                      datePainter.dispose();
                      for (final tag in tags) {
                        final height =
                            measure(
                              tag,
                              DefaultTextStyle.of(context).style
                                  .copyWith(fontSize: 11, height: 1.2),
                              tagWidth,
                            ) +
                            8;
                        if (height > footerHeight) footerHeight = height;
                      }
                      final height =
                          17 +
                          titleHeight +
                          3 +
                          senderHeight +
                          14 +
                          footerHeight;
                      if (height > bodyHeight) bodyHeight = height;
                    }
                    nativeExtent =
                        (native.viewport.width <= 420 ? 210 : 180) +
                        18 +
                        bodyHeight.ceilToDouble();
                  }
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: native?.compact == true ? 0 : 20,
                          vertical: 20,
                        ),
                        sliver: list
                            ? SliverList.separated(
                                itemCount: documents.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) => GlacierDocumentRow(
                                  document: documents[i],
                                  onOpen: onOpen == null
                                      ? null
                                      : () => onOpen!(documents[i].id),
                                  onRetry: onRetry == null
                                      ? null
                                      : () => onRetry!(documents[i].id),
                                ),
                              )
                            : SliverGrid.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent:
                                          nativeExtent ??
                                          (native != null &&
                                                      native.viewport.width <=
                                                          420
                                                  ? 328
                                                  : 298) +
                                              (MediaQuery.textScalerOf(context)
                                                          .scale(14) -
                                                      14) *
                                                  5,
                                      crossAxisSpacing: 17,
                                      mainAxisSpacing: 17,
                                    ),
                                itemCount: documents.length,
                                itemBuilder: (_, i) => GlacierDocumentCard(
                                  document: documents[i],
                                  preview: previewBuilder(documents[i]),
                                  onOpen: onOpen == null
                                      ? null
                                      : () => onOpen!(documents[i].id),
                                  onRetry: onRetry == null
                                      ? null
                                      : () => onRetry!(documents[i].id),
                                ),
                              ),
                      ),
                      if (pagination != null)
                        SliverToBoxAdapter(
                          child: GlacierWorkspaceGeometry.measureEndActions(
                            context,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
                              child: pagination,
                            ),
                          ),
                        ),
                      if (GlacierWorkspaceGeometry.maybeOf(context) != null)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: GlacierWorkspaceGeometry.trailingOf(
                              context,
                              existingBottom: 20,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    ],
  );
}

final class GlacierPropertyGrid extends StatelessWidget {
  const GlacierPropertyGrid({
    super.key,
    required this.values,
    this.minimumWidth = 145,
  });
  final Map<String, String> values;
  final double minimumWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / minimumWidth).floor().clamp(1, 3);
      final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 16,
        children: values.entries
            .map(
              (entry) => SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: GlacierTokens.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      entry.value.isEmpty ? 'Not recorded' : entry.value,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

@immutable
final class GlacierRelatedDocument {
  const GlacierRelatedDocument({
    required this.title,
    required this.relationship,
    this.onOpen,
  });
  final String title, relationship;
  final VoidCallback? onOpen;
}

final class GlacierRelatedDocuments extends StatelessWidget {
  const GlacierRelatedDocuments({
    super.key,
    required this.documents,
    this.pagination,
    this.feedback,
  });
  final List<GlacierRelatedDocument> documents;
  final Widget? pagination, feedback;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Related documents', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 12),
      ?feedback,
      if (documents.isEmpty && feedback == null)
        const Text('No related documents.'),
      ...documents.map(
        (document) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          minVerticalPadding: 9,
          horizontalTitleGap: 12,
          leading: Icon(
            document.relationship == 'Source email'
                ? Icons.mail_outline
                : Icons.description_outlined,
            size: 20,
          ),
          title: Text(
            document.title,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          subtitle: Text(
            document.relationship,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: GlacierTokens.of(context).muted,
            ),
          ),
          trailing: document.onOpen == null
              ? null
              : const Icon(Icons.chevron_right, size: 18),
          onTap: document.onOpen,
        ),
      ),
      ?pagination,
    ],
  );
}

@immutable
final class GlacierUploadReceipt {
  const GlacierUploadReceipt({
    required this.filename,
    required this.status,
    this.detail = '',
    this.busy = false,
    this.tone = AppTone.neutral,
    this.action,
  });
  final String filename, status, detail;
  final bool busy;
  final AppTone tone;
  final Widget? action;
}

final class GlacierUploadQueue extends StatelessWidget {
  const GlacierUploadQueue({
    super.key,
    required this.library,
    required this.receipts,
    this.pagination,
  });
  final String library;
  final List<GlacierUploadReceipt> receipts;
  final Widget? pagination;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Uploads · $library',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Accepted files continue processing after this window closes.',
      ),
      const SizedBox(height: 20),
      ...receipts.map(
        (receipt) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 12),
                child: receipt.busy
                    ? AppJobSpinner(label: receipt.status)
                    : const Icon(Icons.description_outlined, size: 20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.filename,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    AppStatusBadge(label: receipt.status, tone: receipt.tone),
                    if (receipt.detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(receipt.detail),
                      ),
                    if (receipt.action != null) receipt.action!,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ?pagination,
    ],
  );
}

final class GlacierDocumentPropertiesForm extends StatelessWidget {
  const GlacierDocumentPropertiesForm({
    super.key,
    required this.controllers,
    required this.tags,
    this.onAddTag,
    this.onRemoveTag,
    this.enabled = true,
    this.feedback,
  });
  final Map<String, TextEditingController> controllers;
  final List<String> tags;
  final VoidCallback? onAddTag;
  final ValueChanged<String>? onRemoveTag;
  final bool enabled;
  final Widget? feedback;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (feedback != null)
        Padding(padding: const EdgeInsets.only(bottom: 16), child: feedback),
      ...controllers.entries.map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlacierField(
            label: entry.key,
            controller: entry.value,
            enabled: enabled,
            maxLines: entry.key == 'Description' ? 3 : 1,
          ),
        ),
      ),
      Text('Tags', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in tags)
            GlacierTag(
              label: tag,
              onDeleted: !enabled || onRemoveTag == null
                  ? null
                  : () => onRemoveTag!(tag),
            ),
          GlacierButton(
            label: 'Add tag',
            icon: Icons.add,
            onPressed: enabled ? onAddTag : null,
          ),
        ],
      ),
    ],
  );
}
