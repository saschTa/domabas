abstract final class ScanImageLimits {
  static const maxPixels = 50000000;
  static const maxInputBytes = 40 * 1024 * 1024;
  static const maxPageBytes = 18 * 1024 * 1024;
  static const maxPdfBytes = 100 * 1024 * 1024;
  static const maxDraftPageBytes = maxPdfBytes - 2 * 1024 * 1024;
  static const maxDraftStorageBytes = 2 * maxPdfBytes;
  static const maxPreviewBytes = 512 * 1024;
  static const maxThumbnailBytes = 64 * 1024;
  static const captureReservationBytes = maxInputBytes + maxPreviewBytes;
  static const correctionReservationBytes = maxPageBytes + maxThumbnailBytes;
  static const scratchReservationBytes =
      captureReservationBytes + correctionReservationBytes;

  static bool validDimensions(int width, int height) =>
      width > 0 && height > 0 && width * height <= maxPixels;
}
