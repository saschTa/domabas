import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:domabas_api/api.dart' as api;

import '../../../domain/document/models/document.dart';
import '../../../domain/document/models/document_limits.dart';

void validateDocumentThumbnailJson(Map<String, dynamic> document) {
  final value = document['thumbnail'];
  if (value == null) return;
  final original = document['original'] ?? document['file'];
  if (value is! Map<String, dynamic> ||
      original is! Map<String, dynamic> ||
      value['sourceSha256'] != original['sha256'] ||
      value['sourceSha256'] is! String ||
      !_hash(value['sourceSha256'] as String) ||
      value['sha256'] is! String ||
      !_hash(value['sha256'] as String) ||
      value['mediaType'] != 'image/jpeg' ||
      !_boundedInteger(value['width'], documentThumbnailWidthLimit) ||
      !_boundedInteger(value['height'], documentThumbnailHeightLimit) ||
      !_boundedInteger(value['size'], documentThumbnailByteLimit) ||
      value['rendererRevision'] is! int ||
      (value['rendererRevision'] as int) < 1) {
    throw const FormatException('Invalid thumbnail descriptor');
  }
}

bool _boundedInteger(Object? value, int maximum) =>
    value is int && value > 0 && value <= maximum;

bool _hash(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

DocumentThumbnail? documentThumbnailMapper(
  api.DocumentThumbnail? value,
  String? sourceSha256,
) {
  if (value == null) return null;
  final thumbnail = DocumentThumbnail(
    sha256: value.sha256,
    sourceSha256: value.sourceSha256,
    rendererRevision: value.rendererRevision,
    mediaType: value.mediaType.toString(),
    width: value.width,
    height: value.height,
    size: value.size,
  );
  validateDocumentThumbnail(thumbnail);
  if (thumbnail.sourceSha256 != sourceSha256) {
    throw const FormatException('Thumbnail source does not match the original');
  }
  return thumbnail;
}

void validateDocumentThumbnail(DocumentThumbnail value) {
  if (!_hash(value.sha256) ||
      !_hash(value.sourceSha256) ||
      value.mediaType != 'image/jpeg' ||
      !_boundedInteger(value.width, documentThumbnailWidthLimit) ||
      !_boundedInteger(value.height, documentThumbnailHeightLimit) ||
      !_boundedInteger(value.size, documentThumbnailByteLimit) ||
      value.rendererRevision < 1) {
    throw const FormatException('Invalid thumbnail descriptor');
  }
}

void validateDocumentThumbnailBytes(
  Uint8List bytes,
  DocumentThumbnail thumbnail,
) {
  validateDocumentThumbnail(thumbnail);
  if (bytes.length != thumbnail.size ||
      bytes.length > documentThumbnailByteLimit ||
      crypto.sha256.convert(bytes).toString() != thumbnail.sha256) {
    throw const FormatException(
      'Thumbnail content does not match its identity',
    );
  }
  _validateThumbnailJpeg(bytes, thumbnail);
}

void _validateThumbnailJpeg(Uint8List bytes, DocumentThumbnail thumbnail) {
  Never invalid() => throw const FormatException('Invalid thumbnail JPEG');
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) invalid();
  var offset = 2;
  var components = 0;
  while (offset < bytes.length) {
    if (bytes[offset++] != 0xff) invalid();
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) invalid();
    final marker = bytes[offset++];
    if (offset + 2 > bytes.length) invalid();
    final length = bytes[offset] * 256 + bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) invalid();
    if (marker == 0xc0) {
      if (components != 0 || length < 8 || bytes[offset + 2] != 8) invalid();
      final height = bytes[offset + 3] * 256 + bytes[offset + 4];
      final width = bytes[offset + 5] * 256 + bytes[offset + 6];
      components = bytes[offset + 7];
      if ((components != 1 && components != 3) ||
          length != 8 + 3 * components ||
          width != thumbnail.width ||
          height != thumbnail.height) {
        invalid();
      }
      for (var index = 0; index < components; index++) {
        final sampling = bytes[offset + 9 + index * 3];
        final horizontal = sampling >> 4;
        final vertical = sampling & 15;
        if (horizontal < 1 || horizontal > 4 || vertical < 1 || vertical > 4) {
          invalid();
        }
      }
    } else if (marker == 0xda) {
      if (components == 0 ||
          length != 6 + 2 * components ||
          bytes[offset + 2] != components) {
        invalid();
      }
      offset += length;
      while (offset < bytes.length) {
        if (bytes[offset++] != 0xff) continue;
        while (offset < bytes.length && bytes[offset] == 0xff) {
          offset++;
        }
        if (offset >= bytes.length) invalid();
        final entropyMarker = bytes[offset++];
        if (entropyMarker == 0 ||
            (entropyMarker >= 0xd0 && entropyMarker <= 0xd7)) {
          continue;
        }
        if (entropyMarker == 0xd9 && offset == bytes.length) return;
        invalid();
      }
      invalid();
    } else if (marker != 0xc4 &&
        marker != 0xdb &&
        marker != 0xdd &&
        marker != 0xfe &&
        (marker < 0xe0 || marker > 0xef || marker == 0xe1)) {
      invalid();
    }
    offset += length;
  }
  invalid();
}
