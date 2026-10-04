import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_scan/document_scan.dart' as scan;
import 'package:image/image.dart' as img;

import '../models/scan_image_limits.dart';

scan.CameraFrameScanInput? prepareScanDetectionContrast(
  scan.ScanInput input, {
  Uint8List? uprightPreview,
}) {
  final scan.CameraFrameScanInput frame;
  if (input is scan.CameraFrameScanInput) {
    frame = input;
  } else {
    final Uint8List bytes;
    if (uprightPreview != null) {
      bytes = uprightPreview;
    } else if (input is scan.FileScanInput) {
      final file = File(input.path);
      if (file.lengthSync() > ScanImageLimits.maxInputBytes) return null;
      bytes = file.readAsBytesSync();
    } else {
      bytes = (input as scan.BytesScanInput).bytes;
    }
    if (bytes.length > ScanImageLimits.maxInputBytes) return null;
    final decoder = img.findDecoderForData(bytes);
    final header = decoder?.startDecode(bytes);
    if (header == null ||
        header.width <= 0 ||
        header.height <= 0 ||
        header.width * header.height > ScanImageLimits.maxPixels) {
      return null;
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) return null;
    final upright = img.bakeOrientation(decoded);
    final scale = math.min(1.0, 720 / math.max(upright.width, upright.height));
    final reduced = img.copyResize(
      upright,
      width: math.max(1, (upright.width * scale).round()),
      height: math.max(1, (upright.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    frame = scan.ScanInput.bgraFrame(
      width: reduced.width,
      height: reduced.height,
      bytes: reduced.getBytes(order: img.ChannelOrder.bgra),
      bytesPerRow: reduced.width * 4,
    ) as scan.CameraFrameScanInput;
  }
  final width = frame.width, height = frame.height;
  if (width < 16 || height < 16 || width * height > 20000000) return null;
  final bgra = frame.format == scan.ScanImageFormat.bgra8888;
  final bytes = bgra ? frame.bytes : frame.yBytes;
  final pixelStride = bgra ? 4 : 1;
  final declaredStride = bgra ? frame.bytesPerRow : frame.yRowStride;
  final stride = declaredStride == 0 ? width * pixelStride : declaredStride;
  if (bytes == null ||
      stride < width * pixelStride ||
      bytes.length < (height - 1) * stride + width * pixelStride) {
    return null;
  }
  final scale = math.min(1.0, 720 / math.max(width, height));
  final outWidth = math.max(1, (width * scale).round());
  final outHeight = math.max(1, (height * scale).round());
  if (outWidth < 16 || outHeight < 16) return null;
  final luminance = Uint8List(outWidth * outHeight);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < outHeight; y++) {
    final top = y * height ~/ outHeight;
    final bottom = (y + 1) * height ~/ outHeight;
    for (var x = 0; x < outWidth; x++) {
      final left = x * width ~/ outWidth;
      final right = (x + 1) * width ~/ outWidth;
      var sum = 0;
      for (var sy = top; sy < bottom; sy++) {
        for (var sx = left; sx < right; sx++) {
          final offset = sy * stride + sx * pixelStride;
          sum += bgra
              ? (29 * bytes[offset] +
                        150 * bytes[offset + 1] +
                        77 * bytes[offset + 2]) >>
                    8
              : bytes[offset];
        }
      }
      final value = (sum / ((right - left) * (bottom - top))).round();
      luminance[y * outWidth + x] = value;
      histogram[value]++;
    }
  }
  int percentile(double fraction) {
    final target = (luminance.length * fraction).ceil();
    var count = 0;
    for (var i = 0; i < 256; i++) {
      count += histogram[i];
      if (count >= target) return i;
    }
    return 255;
  }

  final low = percentile(.10), high = percentile(.90);
  if (high - low < 6) return null;
  return scan.ScanInput.bgraFrame(
    width: outWidth,
    height: outHeight,
    bytes: _thresholdLocalContrast(luminance, outWidth, outHeight),
    bytesPerRow: outWidth * 4,
    rotation: frame.rotation,
  ) as scan.CameraFrameScanInput;
}

Uint8List _thresholdLocalContrast(Uint8List input, int width, int height) {
  final smooth = Float64List(input.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0, count = 0;
      for (
        var sy = math.max(0, y - 1);
        sy <= math.min(height - 1, y + 1);
        sy++
      ) {
        for (
          var sx = math.max(0, x - 1);
          sx <= math.min(width - 1, x + 1);
          sx++
        ) {
          sum += input[sy * width + sx];
          count++;
        }
      }
      smooth[y * width + x] = sum / count;
    }
  }
  final stride = width + 1;
  final sums = Float64List(stride * (height + 1));
  for (var y = 0; y < height; y++) {
    var row = 0.0;
    for (var x = 0; x < width; x++) {
      row += smooth[y * width + x];
      sums[(y + 1) * stride + x + 1] = sums[y * stride + x + 1] + row;
    }
  }
  final radius = math.max(8, (math.min(width, height) * .02).round());
  final output = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final top = math.max(0, y - radius);
    final bottom = math.min(height, y + radius + 1);
    for (var x = 0; x < width; x++) {
      final left = math.max(0, x - radius);
      final right = math.min(width, x + radius + 1);
      final sum =
          sums[bottom * stride + right] -
          sums[top * stride + right] -
          sums[bottom * stride + left] +
          sums[top * stride + left];
      final mean = sum / ((right - left) * (bottom - top));
      final value = smooth[y * width + x] < mean - 1 ? 0 : 255;
      final offset = (y * width + x) * 4;
      output[offset] = output[offset + 1] = output[offset + 2] = value;
      output[offset + 3] = 255;
    }
  }
  return output;
}
