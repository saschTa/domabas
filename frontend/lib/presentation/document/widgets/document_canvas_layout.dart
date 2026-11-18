import 'package:flutter/material.dart';

import '../../../ui/glacier.dart';

final class DocumentCanvasLayout extends StatelessWidget {
  const DocumentCanvasLayout({
    super.key,
    required this.canvas,
    required this.controls,
    this.search,
    this.onControlsHeight,
  });

  final Widget canvas;
  final Widget controls;
  final Widget? search;
  final ValueChanged<double>? onControlsHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        if (search case final search?)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .4),
            child: SingleChildScrollView(child: search),
          ),
        Expanded(
          child: ClipRect(
            child: CustomMultiChildLayout(
              delegate: _DocumentCanvasOverlayLayout(onControlsHeight),
              children: [
                LayoutId(
                  id: 'canvas',
                  child: SizedBox.expand(
                    key: const Key('documentCanvasViewport'),
                    child: canvas,
                  ),
                ),
                LayoutId(
                  id: 'controls',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: GlacierSurface(
                      key: const Key('documentCanvasControls'),
                      radius: 14,
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: controls,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

final class _DocumentCanvasOverlayLayout extends MultiChildLayoutDelegate {
  _DocumentCanvasOverlayLayout(this.onControlsHeight);

  final ValueChanged<double>? onControlsHeight;

  @override
  void performLayout(Size size) {
    final controls = layoutChild(
      'controls',
      BoxConstraints(maxWidth: size.width, maxHeight: size.height * .35),
    );
    onControlsHeight?.call(controls.height);
    layoutChild('canvas', BoxConstraints.tight(size));
    positionChild('canvas', Offset.zero);
    positionChild(
      'controls',
      Offset((size.width - controls.width) / 2, size.height - controls.height),
    );
  }

  @override
  bool shouldRelayout(_DocumentCanvasOverlayLayout oldDelegate) => true;
}
