import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

final class DocumentPdfSizing extends PdfViewerSizeDelegateProvider {
  const DocumentPdfSizing(this.controlsHeight);

  final double Function() controlsHeight;

  @override
  PdfViewerSizeDelegate create() => _DocumentPdfSizeDelegate(controlsHeight);

  Matrix4 fit(PdfViewerController controller, int pageNumber) {
    final page = controller.layout.pageLayouts[pageNumber - 1];
    final height = controlsHeight();
    final margin = controller.params.margin;
    final zoom = math.min(
      controller.viewSize.width / (page.width + margin * 2),
      math.max(1, controller.viewSize.height - height) /
          (page.height + margin * 2),
    );
    return controller.calcMatrixFor(
      page.center.translate(0, height / (2 * zoom)),
      zoom: zoom,
    );
  }
}

final class _DocumentPdfSizeDelegate extends PdfViewerSizeDelegateLegacy {
  _DocumentPdfSizeDelegate(this.controlsHeight)
    : super(
        maxScale: 8,
        minScale: .1,
        useAlternativeFitScaleAsMinScale: true,
        onePassRenderingScaleThreshold: 200 / 72,
        calculateInitialZoom: _initialPageFit,
      );

  final double Function() controlsHeight;

  static double _initialPageFit(
    PdfDocument document,
    PdfViewerController controller,
    double pageFit,
    double cover,
  ) => pageFit;

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) => super.calculateMetrics(
    viewSize: Size(
      viewSize.width,
      math.max(1, viewSize.height - controlsHeight()),
    ),
    layout: layout,
    pageNumber: pageNumber,
    pageMargin: pageMargin,
    boundaryMargin: boundaryMargin,
  );
}
