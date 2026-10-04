import 'dart:async';
import 'dart:io';

import '../../../domain/document/models/document.dart';
import '../../../domain/scanner/interfaces/scan_draft_repository.dart';
import '../../../domain/scanner/models/scan.dart';
import '../../document/models/prepared_document_upload_metadata.dart';
import '../datasources/native_scanner_camera.dart';
import '../datasources/scan_draft_store.dart';
import '../datasources/scan_pdf_encoder.dart';
import '../datasources/scan_storage_coordinator.dart';
import '../models/scan_image_limits.dart';
import 'scan_upload_data_port.dart';

final class LocalScanDraftRepository implements ScanDraftRepository {
  LocalScanDraftRepository({
    required this.lease,
    required this.camera,
    required this.upload,
    required this.store,
    required this.encoder,
  });
  final ScanStorageLease lease;
  final NativeScannerCamera camera;
  final ScanUploadDataPort upload;
  final ScanDraftStore store;
  final ScanPdfEncoder encoder;
  Completer<void>? _submission;
  bool _initialized = false;

  @override
  Future<ScanDraft> restore() => lease.run(() async {
    if (!_initialized) {
      await store.initialize();
      _initialized = true;
    }
    final receipt =
        lease.coordinator.acceptedReceipts[lease.owner] ??
        (store.record?['status'] == 'accepted'
            ? (store.record?['acceptedDocumentId'] as String?)
            : null);
    if (receipt != null) {
      try {
        await _finishAcceptance(receipt);
      } catch (_) {
        return store.snapshot(
          message: 'Uploaded. Local cleanup is pending.',
          cleanupPending: true,
        );
      }
    }
    return await store.snapshot();
  });

  void _editable() {
    if (!_initialized ||
        store.blocked ||
        store.record?['status'] != 'editable' ||
        lease.coordinator.acceptedReceipts.containsKey(lease.owner)) {
      throw const ScanFailure(
        'This draft is read-only. Check its upload or recovery status.',
      );
    }
  }

  @override
  Future<ScanDraft> saveProperties(DocumentProperties rawDraft) =>
      lease.run(() async {
        _editable();
        final next = store.copy()
          ..['properties'] = rawDraft.values
          ..['revision'] = (store.record!['revision'] as int) + 1;
        await store.commit(next);
        return store.snapshot();
      });

  @override
  Future<ScanDraft> keepPage(ScanCapture capture, ScanCorners corners) =>
      lease.run(() async {
        _editable();
        final existing = (store.record!['pages'] as List).any(
          (page) => (page as Map)['sourceCaptureId'] == capture.id,
        );
        if (existing) {
          return store.snapshot(message: 'This page is already saved.');
        }
        if ((store.record!['pages'] as List).length >= 20) {
          throw const ScanFailure('A scan can contain at most 20 pages.');
        }
        await store.cleanupUnreferenced();
        final reservation = await lease.reserve(
          ScanImageLimits.maxPageBytes + ScanImageLimits.maxThumbnailBytes,
        );
        try {
          final corrected = await camera.correct(capture, corners);
          final pages = store.record!['pages'] as List;
          final total = pages.fold<int>(
            0,
            (sum, p) => sum + ((p as Map)['fileLength'] as int),
          );
          if (total + corrected.bytes.length > 18 * 1024 * 1024) {
            throw const ScanFailure(
              'Saved page images must total at most 18 MiB. Remove a page before adding another.',
            );
          }
          final id = ScanDraftStore.newId();
          final next = store.copy();
          final revision = (next['revision'] as int) + 1;
          final page = <String, dynamic>{
            'id': id,
            'sourceCaptureId': capture.id,
            'revision': revision,
            'width': corrected.width,
            'height': corrected.height,
          };
          final file = await store.writeAsset('$id.jpg', corrected.bytes);
          final thumbnail = await store.writeAsset(
            '$id-thumb.jpg',
            corrected.thumbnail,
          );
          store.describe(page, 'file', file, corrected.bytes);
          store.describe(page, 'thumbnail', thumbnail, corrected.thumbnail);
          (next['pages'] as List).add(page);
          next['revision'] = revision;
          await store.commit(next);
          try {
            await camera.releaseCapture(capture.id);
          } catch (_) {
            return await store.snapshot(
              message: 'Page saved. Temporary capture cleanup will be retried when the scanner closes.',
            );
          }
          return await store.snapshot();
        } finally {
          reservation.release();
        }
      });

  @override
  Future<ScanDraft> removePage(String id) => lease.run(() async {
    _editable();
    final next = store.copy();
    final pages = next['pages'] as List;
    final removed = pages.where((p) => (p as Map)['id'] == id).toList();
    for (final raw in removed) {
      final page = raw as Map;
      (next['retired'] as List).addAll([page['file'], page['thumbnail']]);
    }
    pages.removeWhere((p) => (p as Map)['id'] == id);
    next['revision'] = (next['revision'] as int) + 1;
    await store.commit(next);
    try {
      await store.cleanupRetired();
    } catch (_) {}
    return store.snapshot();
  });

  @override
  Future<ScanDraft> movePage(String id, int finalIndex) => lease.run(() async {
    _editable();
    final next = store.copy();
    final pages = next['pages'] as List;
    final originalIndex = pages.indexWhere((page) => (page as Map)['id'] == id);
    if (originalIndex < 0 || finalIndex < 0 || finalIndex >= pages.length) {
      throw const ScanFailure('Choose a saved page and a valid page position.');
    }
    final current = await store.snapshot();
    if (originalIndex == finalIndex) return current;
    pages.insert(finalIndex, pages.removeAt(originalIndex));
    final revision = current.revision + 1;
    next['revision'] = revision;
    final reordered = [...current.pages];
    reordered.insert(finalIndex, reordered.removeAt(originalIndex));
    final result = ScanDraft(
      id: current.id,
      revision: revision,
      properties: current.properties,
      pages: reordered,
    );
    await store.commit(next);
    return result;
  });

  @override
  Future<ScanSubmission> submit() {
    if (_submission != null) {
      return Future.error(const ScanFailure('An upload is already running.'));
    }
    final token = Completer<void>();
    _submission = token;
    return lease
        .run(() async {
          _editable();
          final pages = store.record!['pages'] as List;
          if (pages.isEmpty) {
            throw const ScanFailure('Add at least one page before uploading.');
          }
          final metadata = upload.prepare(
            ScanDraftStore.properties(
              store.record!['properties'] as Map<String, dynamic>,
            ),
          );
          await store.cleanupUnreferenced();
          final reservation = await lease.reserve(20 * 1024 * 1024 + 32768);
          try {
            if (token.isCompleted) {
              throw const ScanFailure('Upload cancelled before preparation.');
            }
            final manifest = store.record!;
            final pdf = await lease.coordinator.imageWork(
              () => encoder.encode(
                pages.map((p) {
                  final page = p as Map;
                  return ScanPdfPage(
                    store.asset(manifest, page['file'] as String).path,
                    page['width'] as int,
                    page['height'] as int,
                  );
                }).toList(),
              ),
            );
            if (token.isCompleted || lease.cancelled) {
              throw const ScanFailure('Upload cancelled before sending.');
            }
            final attempt = <String, dynamic>{
              'metadataVersion': metadata.version,
            };
            final stamp = ScanDraftStore.newId();
            final pdfName = await store.writeAsset('$stamp.pdf', pdf);
            final metadataName = await store.writeAsset(
              '$stamp.json',
              metadata.bytes,
            );
            store.describe(attempt, 'pdf', pdfName, pdf);
            store.describe(attempt, 'metadata', metadataName, metadata.bytes);
            final next = store.copy()
              ..['attempt'] = attempt
              ..['status'] = 'uncertain'
              ..['revision'] = (store.record!['revision'] as int) + 1;
            await store.commit(next);
          } finally {
            reservation.release();
          }
          return _send(token);
        })
        .whenComplete(() {
          if (identical(_submission, token)) _submission = null;
        });
  }

  @override
  Future<ScanSubmission> retryUpload() {
    if (_submission != null) {
      return Future.error(const ScanFailure('An upload is already running.'));
    }
    final token = Completer<void>();
    _submission = token;
    return lease
        .run(() async {
          if (store.blocked ||
              store.record?['status'] != 'uncertain' ||
              lease.coordinator.acceptedReceipts.containsKey(lease.owner)) {
            throw const ScanFailure('This draft cannot be uploaded again.');
          }
          return _send(token);
        })
        .whenComplete(() {
          if (identical(_submission, token)) _submission = null;
        });
  }

  Future<ScanSubmission> _send(Completer<void> token) async {
    Document document;
    try {
      final manifest = store.record!;
      final attempt = manifest['attempt'] as Map<String, dynamic>;
      final pdf = await store.verifyAsset(
        manifest,
        attempt,
        'pdf',
        20 * 1024 * 1024,
      );
      final metadataBytes = await store.verifyAsset(
        manifest,
        attempt,
        'metadata',
        32768,
      );
      final metadata = PreparedDocumentUploadMetadata(
        version: attempt['metadataVersion'] as int,
        bytes: metadataBytes,
        sha256Hex: attempt['metadataHash'] as String,
      );
      if (token.isCompleted || lease.cancelled) {
        return ScanSubmission(
          await store.snapshot(
            message: 'Upload cancelled. Check the library before retrying this exact upload.',
          ),
        );
      }
      document = await upload.send(
        pdf,
        metadata,
        'scan-${manifest['id']}.pdf',
        token.future,
      );
    } on DocumentUploadException catch (error) {
      try {
        if (error.disposition == DocumentUploadDisposition.rejected &&
            !token.isCompleted &&
            !lease.cancelled) {
          final next = store.copy();
          final attempt = next.remove('attempt') as Map;
          (next['retired'] as List).addAll([
            attempt['pdf'],
            attempt['metadata'],
          ]);
          next['status'] = 'editable';
          await store.commit(next);
          await store.cleanupRetired();
        } else if (error.disposition == DocumentUploadDisposition.duplicate) {
          await store.commit(store.copy()..['status'] = 'duplicate');
        }
      } catch (_) {}
      return ScanSubmission(await store.snapshot(message: error.message));
    } catch (_) {
      store.blocked = true;
      return ScanSubmission(
        await store.snapshot(
          message: 'The saved upload payload is damaged. It cannot be regenerated for retry.',
        ),
      );
    }
    lease.coordinator.acceptedReceipts[lease.owner] = document.id;
    try {
      await _finishAcceptance(document.id);
      return ScanSubmission(
        await store.snapshot(message: 'Uploaded successfully.'),
        document: document,
      );
    } catch (_) {
      return ScanSubmission(
        await store.snapshot(
          message:
              'Uploaded successfully. Local cleanup needs another attempt.',
          cleanupPending: true,
        ),
        document: document,
      );
    }
  }

  Future<void> _finishAcceptance(String documentId) async {
    final next = store.copy();
    for (final raw in next['pages'] as List) {
      final p = raw as Map;
      (next['retired'] as List).addAll([p['file'], p['thumbnail']]);
    }
    final attempt = next.remove('attempt') as Map?;
    if (attempt != null) {
      (next['retired'] as List).addAll([attempt['pdf'], attempt['metadata']]);
    }
    next['pages'] = <dynamic>[];
    next['status'] = 'accepted';
    next['acceptedDocumentId'] = documentId;
    await store.commit(next);
    lease.coordinator.acceptedReceipts.remove(lease.owner);
    store.blocked = false;
    await store.cleanupRetired();
    final manifest = File('${lease.directory.path}/manifest.json');
    if (await manifest.exists()) await manifest.delete();
  }

  @override
  Future<ScanDraft> retryCleanup() => lease.run(() async {
    final receipt =
        lease.coordinator.acceptedReceipts[lease.owner] ??
        store.record?['acceptedDocumentId'] as String?;
    if (receipt == null) {
      throw const ScanFailure('There is no accepted upload to clean up.');
    }
    try {
      await _finishAcceptance(receipt);
    } catch (_) {
      return store.snapshot(
        message: 'Uploaded. Local cleanup is still pending.',
        cleanupPending: true,
      );
    }
    return store.snapshot(message: 'Uploaded. Local files have been removed.');
  });

  @override
  Future<void> discard() => lease.run(() async {
    if (lease.coordinator.acceptedReceipts.containsKey(lease.owner) ||
        store.record?['status'] == 'accepted') {
      throw const ScanFailure('This upload was accepted. Use Retry cleanup.');
    }
    if (store.blocked || store.record == null) {
      final files = <File>[];
      await for (final entity in lease.directory.list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (entity is File &&
            RegExp(
              r'^(draft-[0-9]+-[0-9]+-[A-Za-z0-9-]+\.(jpg|json|pdf)|scratch-[0-9]+-[0-9]+\.jpg|manifest.stage)$',
            ).hasMatch(name)) {
          files.add(entity);
        }
      }
      for (final file in files) {
        await file.delete();
      }
    } else {
      final next = store.copy();
      for (final raw in next['pages'] as List) {
        final p = raw as Map;
        (next['retired'] as List).addAll([p['file'], p['thumbnail']]);
      }
      final attempt = next.remove('attempt') as Map?;
      if (attempt != null) {
        (next['retired'] as List).addAll([attempt['pdf'], attempt['metadata']]);
      }
      next['pages'] = <dynamic>[];
      next['status'] = 'discarded';
      await store.commit(next);
      await store.cleanupUnreferenced();
    }
    final file = File('${lease.directory.path}/manifest.json');
    if (await file.exists()) await file.delete();
  });

  @override
  void cancelSubmission() {
    final token = _submission;
    if (token != null && !token.isCompleted) token.complete();
  }

  @override
  void cancelNewOperations() {
    cancelSubmission();
    lease.cancelNewOperations();
  }

  @override
  Future<void> close() async {
    cancelNewOperations();
    await lease.drain();
    store.release();
  }
}
