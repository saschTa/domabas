import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../domain/document/models/document_limits.dart';
import '../../../domain/document/interfaces/document_repository.dart';
import '../../../domain/document/models/document.dart';

Future<ui.Image> decodeDocumentImage(
  Uint8List bytes, {
  required int longestEdge,
}) async {
  final (width, height) = _imageDimensions(bytes);
  if (width > documentImagePixelLimit ||
      height > documentImagePixelLimit ||
      width > documentImagePixelLimit ~/ height) {
    throw const FormatException(
      'Images must contain at most 50 million pixels.',
    );
  }
  ui.Codec? codec;
  try {
    final scale = math.min(1.0, longestEdge / math.max(width, height));
    codec = await ui.instantiateImageCodec(
      Uint8List.fromList(bytes),
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
      allowUpscaling: false,
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
  }
}

(int, int) _imageDimensions(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length >= 24 &&
      data.getUint32(0) == 0x89504e47 &&
      data.getUint32(4) == 0x0d0a1a0a &&
      data.getUint32(12) == 0x49484452) {
    final width = data.getUint32(16);
    final height = data.getUint32(20);
    if (width > 0 && height > 0) return (width, height);
  }
  if (bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    var offset = 2;
    var orientation = 1;
    int? width;
    int? height;
    while (offset + 3 < bytes.length) {
      if (bytes[offset++] != 0xff) break;
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 0xda || marker == 0xd9) break;
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue;
      if (offset + 2 > bytes.length) break;
      final length = data.getUint16(offset);
      if (length < 2 || offset + length > bytes.length) break;
      if (marker == 0xe1) {
        orientation =
            _jpegOrientation(
              ByteData.sublistView(bytes, offset + 2, offset + length),
            ) ??
            orientation;
      }
      if (marker >= 0xc0 &&
          marker <= 0xcf &&
          marker != 0xc4 &&
          marker != 0xc8 &&
          marker != 0xcc &&
          length >= 8) {
        height = data.getUint16(offset + 3);
        width = data.getUint16(offset + 5);
      }
      offset += length;
    }
    if (width != null && height != null && width > 0 && height > 0) {
      return orientation >= 5 && orientation <= 8
          ? (height, width)
          : (width, height);
    }
  }
  throw const FormatException('Invalid PNG or JPEG dimensions');
}

int? _jpegOrientation(ByteData segment) {
  if (segment.lengthInBytes < 14 ||
      segment.getUint32(0) != 0x45786966 ||
      segment.getUint16(4) != 0) {
    return null;
  }
  final endian = switch (segment.getUint16(6)) {
    0x4949 => Endian.little,
    0x4d4d => Endian.big,
    _ => null,
  };
  if (endian == null || segment.getUint16(8, endian) != 42) return null;
  final directory = 6 + segment.getUint32(10, endian);
  if (directory < 14 || directory + 2 > segment.lengthInBytes) return null;
  final count = segment.getUint16(directory, endian);
  for (var index = 0; index < count; index++) {
    final entry = directory + 2 + index * 12;
    if (entry + 12 > segment.lengthInBytes) return null;
    if (segment.getUint16(entry, endian) == 0x112 &&
        segment.getUint16(entry + 2, endian) == 3 &&
        segment.getUint32(entry + 4, endian) == 1) {
      return segment.getUint16(entry + 8, endian);
    }
  }
  return null;
}

final class DocumentPreviewRequest {
  DocumentPreviewRequest(this.document);
  final DocumentThumbnailRef? document;
  final result = Completer<ui.Image?>();
  final cancellation = Completer<void>();
  bool get cancelled => cancellation.isCompleted;
  void cancel() {
    if (!cancelled) cancellation.complete();
    if (!result.isCompleted) result.complete(null);
  }
}

final class DocumentPreviewCoordinator {
  DocumentPreviewCoordinator(this.repository);
  final DocumentRepository repository;
  final _cache = <String, ui.Image>{};
  final _queue = Queue<DocumentPreviewRequest>();
  final _running = <DocumentPreviewRequest>{};
  int _cacheBytes = 0;
  bool _closed = false;
  bool _paused = false;
  static const maximumCacheBytes = 8 * 1024 * 1024;
  static const maximumJobs = 2;

  String _key(DocumentThumbnailRef document) => document.identity;

  DocumentPreviewRequest request(DocumentThumbnailRef? document) {
    final request = DocumentPreviewRequest(document);
    if (_closed || _paused || document == null) {
      request.cancel();
      return request;
    }
    final key = _key(document);
    final image = _cache.remove(key);
    if (image != null &&
        image.width == document.thumbnail.width &&
        image.height == document.thumbnail.height) {
      _cache[key] = image;
      request.result.complete(image.clone());
    } else {
      if (image != null) {
        _cacheBytes -= image.width * image.height * 4;
        image.dispose();
      }
      _queue.add(request);
      _drain();
    }
    return request;
  }

  void pause() {
    _paused = true;
    for (final request in [..._queue, ..._running]) {
      request.cancel();
    }
    _queue.clear();
  }

  void resume() {
    if (!_closed) {
      _paused = false;
      _drain();
    }
  }

  void evict(String id) {
    final keys = _cache.keys.where((key) => key.startsWith('$id/')).toList();
    for (final key in keys) {
      _remove(key);
    }
  }

  void _remove(String key) {
    final image = _cache.remove(key)!;
    _cacheBytes -= image.width * image.height * 4;
    image.dispose();
  }

  void close() {
    _closed = true;
    pause();
    for (final key in _cache.keys.toList()) {
      _remove(key);
    }
  }

  void _drain() {
    while (!_closed &&
        !_paused &&
        _running.length < maximumJobs &&
        _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      if (request.cancelled) continue;
      _running.add(request);
      unawaited(_render(request));
    }
  }

  Future<void> _render(DocumentPreviewRequest request) async {
    ui.Image? thumbnail;
    try {
      final bytes = await repository.thumbnail(
        request.document!,
        cancel: request.cancellation.future,
      );
      if (request.cancelled) return;
      final descriptor = request.document!.thumbnail;
      final dimensions = _imageDimensions(bytes);
      if (bytes.length != descriptor.size ||
          bytes.length > documentThumbnailByteLimit ||
          bytes.length < 2 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8 ||
          dimensions != (descriptor.width, descriptor.height) ||
          dimensions.$1 > documentThumbnailWidthLimit ||
          dimensions.$2 > documentThumbnailHeightLimit) {
        throw const FormatException('Invalid thumbnail dimensions');
      }
      thumbnail = await decodeDocumentImage(
        bytes,
        longestEdge: documentThumbnailHeightLimit,
      );
      if (request.cancelled || _closed) return;
      final key = _key(request.document!);
      if (_cache.containsKey(key)) _remove(key);
      final image = thumbnail;
      final size = image.width * image.height * 4;
      while (_cacheBytes + size > maximumCacheBytes && _cache.isNotEmpty) {
        _remove(_cache.keys.first);
      }
      _cache[key] = image;
      _cacheBytes += size;
      thumbnail = null;
      if (!request.result.isCompleted) request.result.complete(image.clone());
    } catch (_) {
      if (!request.result.isCompleted) request.result.complete(null);
    } finally {
      thumbnail?.dispose();
      if (!request.result.isCompleted) request.result.complete(null);
      await request.result.future;
      _running.remove(request);
      _drain();
    }
  }
}
