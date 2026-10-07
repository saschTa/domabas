import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/document_collection_item.dart';

String documentSupplementalDetails(
  BuildContext context,
  DocumentCollectionItem document,
) {
  final original = document.original?.original;
  final type = switch (original?.mediaType) {
    'application/pdf' => 'PDF document',
    'image/png' => 'PNG image',
    'image/jpeg' => 'JPEG image',
    'message/rfc822' => 'Email',
    _ =>
      document.kind == 'email'
          ? 'Email'
          : document.knownNoOriginal
          ? 'Metadata only'
          : 'Document',
  };
  final bytes = original?.size;
  final size = bytes == null
      ? ''
      : bytes < 1024
      ? ' · $bytes B'
      : bytes < 1024 * 1024
      ? ' · ${(bytes / 1024).toStringAsFixed(0)} KB'
      : ' · ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  final date = MaterialLocalizations.of(context)
      .formatMediumDate(document.createdAt.toLocal());
  return '$type$size\n${document.documentDate.isEmpty ? 'Added $date' : 'Dated ${document.documentDate}'}';
}

final class DocumentCardMetadata extends StatelessWidget {
  const DocumentCardMetadata({
    super.key,
    required this.document,
    required this.list,
  });

  final DocumentCollectionItem document;
  final bool list;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final wide = list && constraints.maxWidth >= scaler.scale(420);
      final title = _DocumentTextSlot(
        text: document.title,
        lines: wide ? 1 : 2,
        style: theme.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
      );
      final tags = _DocumentTagRail(tags: document.tags);
      final footer = _DocumentFooter(document: document, inline: !wide);
      final body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (document.snippet != null) ...[
            SizedBox(height: list ? 4 : 8),
            _DocumentTextSlot(
              text: document.snippet!,
              lines: wide ? 1 : 2,
              style: theme.textTheme.bodySmall!,
            ),
          ],
          SizedBox(height: list ? 4 : 10),
          tags,
          if (!wide) ...[SizedBox(height: list ? 6 : 12), footer],
        ],
      );
      if (!wide) return body;
      return Row(
        children: [
          Expanded(child: body),
          const SizedBox(width: 24),
          SizedBox(width: scaler.scale(128), child: footer),
        ],
      );
    },
  );
}

final class _DocumentTextSlot extends StatelessWidget {
  const _DocumentTextSlot({
    required this.text,
    required this.lines,
    required this.style,
  });
  final String text;
  final int lines;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final painter = _measure(
      context,
      List.filled(lines, 'Ag').join('\n'),
      style,
    );
    final height = painter.height.ceilToDouble();
    painter.dispose();
    return SizedBox(
      height: height,
      child: Tooltip(
        message: text,
        child: Text(
          text,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

TextPainter _measure(BuildContext context, String text, TextStyle style) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();

final class _DocumentTagRail extends StatelessWidget {
  const _DocumentTagRail({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final style = theme.textTheme.labelSmall!.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      final line = _measure(context, 'Ag', style);
      final height = line.height.ceilToDouble() + 8;
      line.dispose();
      double width(String value) {
        final painter = _measure(context, value, style);
        final result = painter.width.ceilToDouble();
        painter.dispose();
        return result;
      }

      final widths = tags
          .take(3)
          .map((tag) => math.min(width(tag) + 16, 128.0))
          .toList();
      var count = widths.length;
      double counterWidth() =>
          count < tags.length ? width('+${tags.length - count}') + 8 : 0;
      while (count > 1 &&
          widths.take(count).fold(0.0, (a, b) => a + b) +
                  (count - 1) * 6 +
                  counterWidth() +
                  (count < tags.length ? 6 : 0) >
              constraints.maxWidth) {
        count--;
      }
      return SizedBox(
        height: height,
        child: tags.isEmpty
            ? null
            : Tooltip(
                message: tags.join(', '),
                child: Semantics(
                  label: 'Tags: ${tags.join(', ')}',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      for (var index = 0; index < count; index++) ...[
                        if (index > 0) const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: widths[index],
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tags[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                          ),
                        ),
                      ],
                      if (count < tags.length) ...[
                        const SizedBox(width: 6),
                        Text('+${tags.length - count}', style: style),
                      ],
                    ],
                  ),
                ),
              ),
      );
    },
  );
}

final class _DocumentFooter extends StatelessWidget {
  const _DocumentFooter({required this.document, required this.inline});
  final DocumentCollectionItem document;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final status = Row(
      children: [
        if (document.requiresPassword) ...[
          Tooltip(
            message: 'PDF password required',
            child: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.error,
              semanticLabel: 'PDF password required',
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: _DocumentTextSlot(
            text: document.status,
            lines: 1,
            style: style,
          ),
        ),
      ],
    );
    final date = _DocumentTextSlot(
      text: MaterialLocalizations.of(context)
          .formatMediumDate(document.createdAt.toLocal()),
      lines: 1,
      style: style,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (inline &&
            constraints.maxWidth >=
                MediaQuery.textScalerOf(context).scale(200)) {
          return Row(
            children: [
              Expanded(flex: 3, child: status),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: date),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [status, const SizedBox(height: 4), date],
        );
      },
    );
  }
}

final class DocumentCardDetailsPill extends StatelessWidget {
  const DocumentCardDetailsPill({
    super.key,
    required this.pillKey,
    required this.details,
    required this.visible,
    required this.reduceMotion,
  });
  final Key pillKey;
  final String details;
  final bool visible, reduceMotion;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey(reduceMotion),
      tween: Tween(end: visible ? 1 : 0),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => value == 0
          ? const SizedBox.shrink()
          : Opacity(opacity: value, child: child),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: IgnorePointer(
          child: ExcludeSemantics(
            excluding: !visible,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                key: pillKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in details.split('\n'))
                            Text(
                              line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
