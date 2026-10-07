import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

Widget? documentPdfSelectionMenuBuilder(
  BuildContext context,
  PdfViewerContextMenuBuilderParams params,
) {
  final selection = params.textSelectionDelegate;
  final items = [
    if (params.isTextSelectionEnabled &&
        selection.isCopyAllowed &&
        selection.hasSelectedText)
      ContextMenuButtonItem(
        type: ContextMenuButtonType.copy,
        onPressed: () => unawaited(selection.copyTextSelection()),
      ),
    if (params.isTextSelectionEnabled && !selection.isSelectingAllText)
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () => unawaited(selection.selectAllText()),
      ),
  ];
  if (items.isEmpty) return null;
  return Align(
    alignment: Alignment.topLeft,
    child: AdaptiveTextSelectionToolbar.buttonItems(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: params.anchorA,
        secondaryAnchor: params.anchorB,
      ),
      buttonItems: items,
    ),
  );
}
