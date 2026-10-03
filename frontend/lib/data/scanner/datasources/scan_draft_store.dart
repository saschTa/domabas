import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../../../domain/document/models/document.dart';
import '../../../domain/scanner/models/scan.dart';
import '../models/scan_image_limits.dart';
import 'scan_storage_coordinator.dart';

final class ScanDraftStore {
  ScanDraftStore(this.lease);
  final ScanStorageLease lease;
  Map<String, dynamic>? record;
  bool blocked = false;
  ScanReservation? _housekeeping;
  File get _manifest => File('${lease.directory.path}/manifest.json');
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  static DocumentProperties defaults() {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return DocumentProperties(
      title: 'Scan $date',
      description: '',
      tags: const [],
      kind: 'document',
      sender: '',
      recipients: const [],
      cc: const [],
      bcc: const [],
      documentDate: date,
      subject: '',
      messageId: '',
    );
  }

  Future<void> initialize() async {
    if (!await _manifest.exists()) {
      _housekeeping ??= await lease.reserve(0);
      final leftovers = await lease.directory.list(followLinks: false).toList();
      if (leftovers.isNotEmpty) {
        blocked = true;
        return;
      }
      await commit({
        'version': 1,
        'owner': lease.owner,
        'id': newId(),
        'revision': 0,
        'status': 'editable',
        'properties': defaults().values,
        'pages': <dynamic>[],
        'retired': <dynamic>[],
      });
      return;
    }
    try {
      if (await _manifest.length() > 128 * 1024) {
        throw const FormatException('Manifest too large');
      }
      final value =
          jsonDecode(await _manifest.readAsString()) as Map<String, dynamic>;
      if (value['version'] != 1 ||
          value['owner'] != lease.owner ||
          value['id'] is! String ||
          !RegExp(r'^[0-9]+-[0-9]+$').hasMatch(value['id'] as String) ||
          value['revision'] is! int ||
          (value['revision'] as int) < 0 ||
          !const {
            'editable',
            'uncertain',
            'duplicate',
            'accepted',
            'discarded',
          }.contains(value['status'])) {
        throw const FormatException('Invalid manifest identity');
      }
      final pages = value['pages'] as List;
      if (pages.length > 20 ||
          pages.map((p) => (p as Map)['id']).toSet().length != pages.length) {
        throw const FormatException('Invalid page list');
      }
      final captures = <String>{};
      for (final page in pages.cast<Map<String, dynamic>>()) {
        final capture = page['sourceCaptureId'];
        if (capture != null && (capture is! String || !captures.add(capture))) {
          throw const FormatException('Invalid saved capture identity');
        }
      }
      properties(value['properties'] as Map<String, dynamic>);
      var total = 0;
      for (final raw in pages) {
        final page = raw as Map<String, dynamic>;
        if (page['revision'] is! int ||
            (page['revision'] as int) > (value['revision'] as int) ||
            (page['revision'] as int) < 1 ||
            page['id'] is! String) {
          throw const FormatException('Invalid page revision');
        }
        final bytes = await verifyAsset(
          value,
          page,
          'file',
          ScanImageLimits.maxPageBytes,
        );
        total += bytes.length;
        final header = img.JpegDecoder().startDecode(bytes);
        if (header == null ||
            header.width != page['width'] ||
            header.height != page['height'] ||
            !ScanImageLimits.validDimensions(header.width, header.height)) {
          throw const FormatException('Invalid saved page');
        }
        final thumb = await verifyAsset(value, page, 'thumbnail', 64 * 1024);
        final thumbnailHeader = img.JpegDecoder().startDecode(thumb);
        if (thumbnailHeader == null ||
            max(thumbnailHeader.width, thumbnailHeader.height) > 400) {
          throw const FormatException('Invalid saved thumbnail');
        }
      }
      if (total > 18 * 1024 * 1024) {
        throw const FormatException('Page total exceeds limit');
      }
      if (const {'uncertain', 'duplicate'}.contains(value['status'])) {
        await verifyAsset(
          value,
          value['attempt'] as Map<String, dynamic>,
          'pdf',
          20 * 1024 * 1024,
        );
        await verifyAsset(
          value,
          value['attempt'] as Map<String, dynamic>,
          'metadata',
          32768,
        );
      }
      for (final name in value['retired'] as List) {
        asset(value, name as String);
      }
      if (value['status'] == 'accepted' &&
          value['acceptedDocumentId'] is! String) {
        throw const FormatException('Missing accepted identity');
      }
      record = value;
    } on FileSystemException {
      throw const ScanFailure(
        'Saved scan storage is temporarily unavailable. Try again.',
      );
    } catch (_) {
      blocked = true;
    }
    if (!blocked) {
      try {
        await cleanupUnreferenced(includeScratch: true);
      } catch (_) {}
    }
  }

  File asset(Map<String, dynamic> manifest, String name) {
    if (!RegExp('^draft-${manifest['id']}-[A-Za-z0-9-]+\\.(jpg|json|pdf)\$')
        .hasMatch(name)) {
      throw const FormatException('Invalid saved asset path');
    }
    return File('${lease.directory.path}/$name');
  }

  Future<Uint8List> verifyAsset(
    Map<String, dynamic> manifest,
    Map<String, dynamic> entry,
    String key,
    int limit,
  ) async {
    final file = asset(manifest, entry[key] as String);
    if (!await file.exists()) {
      throw const FormatException('Missing saved asset');
    }
    final length = await file.length();
    if (length <= 0 || length > limit || length != entry['${key}Length']) {
      throw const FormatException('Saved asset length changed');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != entry['${key}Hash']) {
      throw const FormatException('Saved asset hash changed');
    }
    return bytes;
  }

  Future<void> commit(Map<String, dynamic> next) async {
    final bytes = utf8.encode(jsonEncode(next));
    if (bytes.length > 128 * 1024) {
      throw const ScanFailure(
        'The draft properties exceed local storage limits.',
      );
    }
    final staged = File('${lease.directory.path}/manifest.stage');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(_manifest.path);
    } catch (_) {
      var committed = false;
      try {
        if (await _manifest.length() == bytes.length) {
          final primary = await _manifest.readAsBytes();
          committed = sha256.convert(primary) == sha256.convert(bytes);
        }
      } catch (_) {}
      if (!committed) {
        rethrow;
      }
    }
    record = next;
  }

  Map<String, dynamic> copy() =>
      jsonDecode(jsonEncode(record!)) as Map<String, dynamic>;
  Future<String> writeAsset(String suffix, Uint8List bytes) async {
    final name = 'draft-${record!['id']}-$suffix';
    await asset(record!, name).writeAsBytes(bytes, flush: true);
    return name;
  }

  void describe(
    Map<String, dynamic> value,
    String key,
    String path,
    Uint8List bytes,
  ) {
    value[key] = path;
    value['${key}Length'] = bytes.length;
    value['${key}Hash'] = sha256.convert(bytes).toString();
  }

  Future<void> cleanupRetired() async {
    final current = record!;
    for (final name in List<String>.from(current['retired'] as List)) {
      final file = asset(current, name);
      if (await file.exists()) await file.delete();
    }
    if ((current['retired'] as List).isNotEmpty) {
      final next = copy()..['retired'] = <dynamic>[];
      await commit(next);
    }
  }

  Future<void> cleanupUnreferenced({bool includeScratch = false}) async {
    final current = record!;
    final referenced = <String>{};
    for (final raw in current['pages'] as List) {
      final p = raw as Map;
      referenced.add(p['file'] as String);
      referenced.add(p['thumbnail'] as String);
    }
    final attempt = current['attempt'] as Map?;
    if (attempt != null) {
      referenced.add(attempt['pdf'] as String);
      referenced.add(attempt['metadata'] as String);
    }
    referenced.addAll(List<String>.from(current['retired'] as List));
    await for (final entity in lease.directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is File &&
          (name == 'manifest.stage' ||
              RegExp(
                    r'^(draft-[0-9]+-[0-9]+-[A-Za-z0-9-]+\.(jpg|json|pdf)|scratch-[0-9]+-[0-9]+\.jpg)$',
                  ).hasMatch(name) &&
                  !referenced.contains(name) &&
                  (includeScratch || !name.startsWith('scratch-')))) {
        await entity.delete();
      }
    }
    await cleanupRetired();
  }

  Future<ScanDraft> snapshot({
    String? message,
    bool cleanupPending = false,
  }) async {
    final receipt = lease.coordinator.acceptedReceipts[lease.owner];
    final current = record;
    if (receipt != null) {
      return ScanDraft(
        id: current?['id'] as String? ?? 'recovery',
        revision: current?['revision'] as int? ?? 0,
        properties: defaults(),
        status: ScanDraftStatus.accepted,
        acceptedDocumentId: receipt,
        message: message ?? 'Uploaded. Local cleanup is pending.',
        cleanupPending: true,
      );
    }
    if (blocked || current == null) {
      return ScanDraft(
        id: 'recovery',
        revision: 0,
        properties: defaults(),
        status: ScanDraftStatus.blocked,
        message: 'The saved draft is incomplete or damaged. Discard it explicitly before starting another scan.',
      );
    }
    final pages = <ScanPage>[];
    for (final raw in current['pages'] as List) {
      final p = raw as Map<String, dynamic>;
      pages.add(
        ScanPage(
          id: p['id'] as String,
          width: p['width'] as int,
          height: p['height'] as int,
          thumbnail: await asset(
            current,
            p['thumbnail'] as String,
          ).readAsBytes(),
        ),
      );
    }
    final status = switch (current['status']) {
      'uncertain' => ScanDraftStatus.uncertain,
      'duplicate' => ScanDraftStatus.duplicate,
      'accepted' => ScanDraftStatus.accepted,
      'discarded' => ScanDraftStatus.blocked,
      _ => ScanDraftStatus.editable,
    };
    return ScanDraft(
      id: current['id'] as String,
      revision: current['revision'] as int,
      properties: properties(current['properties'] as Map<String, dynamic>),
      pages: pages,
      status: status,
      message: message,
      acceptedDocumentId: current['acceptedDocumentId'] as String?,
      cleanupPending:
          cleanupPending ||
          status == ScanDraftStatus.accepted &&
              (current['retired'] as List).isNotEmpty,
    );
  }

  static DocumentProperties properties(Map<String, dynamic> value) =>
      DocumentProperties(
        title: value['title'] as String,
        description: value['description'] as String,
        tags: List<String>.from(value['tags'] as List),
        kind: value['kind'] as String,
        sender: value['sender'] as String,
        recipients: List<String>.from(value['recipients'] as List),
        cc: List<String>.from(value['cc'] as List),
        bcc: List<String>.from(value['bcc'] as List),
        documentDate: value['documentDate'] as String,
        subject: value['subject'] as String,
        messageId: value['messageId'] as String,
      );
  void release() {
    _housekeeping?.release();
    _housekeeping = null;
  }
}
