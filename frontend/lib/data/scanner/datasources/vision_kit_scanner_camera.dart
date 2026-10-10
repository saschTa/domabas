import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../domain/scanner/interfaces/scanner_camera.dart';
import '../../../domain/scanner/models/scan.dart';
import '../models/scan_assets.dart';
import '../models/scan_image_limits.dart';
import '../repos/scan_capture_data_port.dart';
import 'processed_scan_page.dart';
import 'scan_draft_store.dart';
import 'scan_storage_coordinator.dart';

final class VisionKitScannerCamera
    implements ScanCaptureDataPort, ScannerBatchCamera, ScannerSystemCapture {
  VisionKitScannerCamera(
    this.lease, {
    this.channel = const MethodChannel(
      'dev.domabas/visionkit_document_scanner',
    ),
  });

  final ScanStorageLease lease;
  final MethodChannel channel;
  final _states = StreamController<ScanCameraState>.broadcast();
  ScanCameraState _state = const ScanCameraState();
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _cancelled = false;
  String? _sessionId;
  int _pageCount = 0;
  int _nextIndex = 0;
  String? _capturePath;
  ScanCapture? _capture;
  ScanReservation? _reservation;
  void Function()? _releaseCamera;

  @override
  bool get usesSystemCapture => true;
  @override
  String get systemCaptureNotice =>
      'Scanning uses Apple VisionKit. Keep the scan open until all pages are saved to your draft.';
  @override
  int get pendingPageCount => _pageCount - _nextIndex;
  @override
  ScanCameraState get state => _state;
  @override
  Stream<ScanCameraState> get states => _states.stream;

  Future<T> _run<T>(Future<T> Function() operation, {bool cleanup = false}) {
    final result = _tail.then((_) {
      if (!cleanup) _checkActive();
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkActive() {
    if (_cancelled || lease.cancelled) throw const ScanCancelled();
  }

  void _emit(ScanCameraStatus status) {
    _state = ScanCameraState(status: status);
    if (!_cancelled) _states.add(_state);
  }

  Future<void> _reserveCapture() async {
    if (_reservation != null) return;
    _reservation = await lease.reserve(
      ScanImageLimits.captureReservationBytes,
      scratch: true,
    );
    lease.scratchBytes += ScanImageLimits.captureReservationBytes;
    _checkActive();
  }

  @override
  Future<void> start() => _run(() async {
    if (_state.status == ScanCameraStatus.ready || _sessionId != null) return;
    _emit(ScanCameraStatus.starting);
    try {
      _releaseCamera = await lease.coordinator.acquireCamera();
      _checkActive();
      await _reserveCapture();
      _emit(ScanCameraStatus.ready);
    } catch (_) {
      await _releaseInput();
      _releaseCameraLease();
      _emit(ScanCameraStatus.unavailable);
      rethrow;
    }
  });

  @override
  Future<void> beginBatch({required int maxPages}) => _run(() async {
    if (_sessionId != null ||
        _state.status != ScanCameraStatus.ready ||
        _reservation == null) {
      throw const ScanFailure('Open the scanner before scanning pages.');
    }
    if (maxPages < 1 || maxPages > 20) {
      throw const ScanFailure('A scan can contain at most 20 pages.');
    }
    final id = ScanDraftStore.newId();
    _sessionId = id;
    _emit(ScanCameraStatus.capturing);
    try {
      final count = await channel.invokeMethod<int>('scan', {
        'id': id,
        'maxPages': maxPages,
      });
      _checkActive();
      if (count == null) throw const ScanCancelled();
      if (count < 1 || count > maxPages) {
        throw ScanFailure(
          'This draft has room for $maxPages more pages. Scan between 1 and $maxPages pages, then save again.',
        );
      }
      _pageCount = count;
      _nextIndex = 0;
    } catch (error) {
      await _discardSession(force: true);
      if (error is PlatformException) throw _visionKitFailure(error);
      rethrow;
    } finally {
      _emit(ScanCameraStatus.suspended);
    }
  });

  @override
  Future<ScanCapture> capture() async {
    await beginBatch(maxPages: 1);
    return captureNextPage();
  }

  @override
  Future<ScanCapture> captureNextPage() => _run(() async {
    if (_capture case final capture?) return capture;
    final session = _sessionId;
    if (session == null || pendingPageCount < 1) {
      throw const ScanFailure('There are no pending scanned pages.');
    }
    try {
      await _reserveCapture();
      _emit(ScanCameraStatus.processing);
      final bytes = await channel.invokeMethod<Uint8List>('readPage', {
        'id': session,
        'index': _nextIndex,
      });
      _checkActive();
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > ScanImageLimits.maxPageBytes) {
        throw const ScanFailure(
          'Scanned pages must be JPEGs of at most 18 MiB.',
        );
      }
      final prepared = await lease.coordinator.imageWork(
        () => prepareProcessedScanPage(bytes),
      );
      _checkActive();
      final file = File('${lease.directory.path}/scratch-$session.jpg');
      _capturePath = file.path;
      await file.writeAsBytes(bytes, flush: true);
      _checkActive();
      return _capture = ScanCapture(
        id: '$session-$_nextIndex',
        width: prepared.width,
        height: prepared.height,
        corners: ScanCorners.fullImage(),
        preview: prepared.preview,
        processed: true,
      );
    } on PlatformException catch (error) {
      throw _visionKitFailure(error);
    } finally {
      _emit(ScanCameraStatus.suspended);
    }
  });

  @override
  Future<CorrectedScanPage> correct(ScanCapture capture, ScanCorners corners) =>
      _run(() async {
        final saved = _capture;
        if (saved == null ||
            saved.id != capture.id ||
            saved.width != capture.width ||
            saved.height != capture.height ||
            _capturePath == null) {
          throw const ScanFailure('Retry importing this scanned page.');
        }
        final file = File(_capturePath!);
        if (await file.length() > ScanImageLimits.maxPageBytes) {
          throw const ScanFailure('Scanned pages must be at most 18 MiB.');
        }
        final bytes = await file.readAsBytes();
        final thumbnail = await lease.coordinator.imageWork(
          () => createProcessedScanThumbnail(bytes),
        );
        _checkActive();
        return CorrectedScanPage(bytes, thumbnail, saved.width, saved.height);
      });

  @override
  Future<void> releaseCapture(String id) async {}

  @override
  Future<void> acknowledgePage(String id) => _run(() async {
    if (_capture?.id != id) return;
    if (pendingPageCount == 1) {
      await channel.invokeMethod<void>('finish', {'id': _sessionId});
    }
    await _releaseInput();
    _nextIndex++;
    if (pendingPageCount == 0) _clearSession();
  });

  Future<void> _releaseInput() async {
    if (_capturePath case final path?) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _capturePath = null;
    _capture = null;
    if (_reservation != null) {
      lease.scratchBytes -= ScanImageLimits.captureReservationBytes;
      _reservation!.release();
      _reservation = null;
    }
  }

  void _releaseCameraLease() {
    _releaseCamera?.call();
    _releaseCamera = null;
  }

  void _clearSession() {
    _sessionId = null;
    _pageCount = 0;
    _nextIndex = 0;
    _releaseCameraLease();
  }

  Future<void> _discardSession({bool force = false}) async {
    if (force) {
      try {
        await _discardSession();
      } finally {
        try {
          await _releaseInput();
        } finally {
          _clearSession();
        }
      }
      return;
    }
    if (_sessionId case final id?) {
      await channel.invokeMethod<void>('cancel', {'id': id});
    }
    await _releaseInput();
    _clearSession();
  }

  @override
  Future<void> discardPendingPages() => _run(_discardSession, cleanup: true);

  @override
  Future<void> suspend() => _run(() async {
    if (_sessionId == null) {
      await _releaseInput();
      _releaseCameraLease();
    }
    _emit(ScanCameraStatus.suspended);
  }, cleanup: true);

  @override
  void cancelNewOperations() {
    if (_cancelled) return;
    _cancelled = true;
    if (_sessionId case final id?) {
      unawaited(
        channel
            .invokeMethod<void>('cancel', {'id': id})
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  @override
  Future<void> close() {
    cancelNewOperations();
    return _closing ??= _run(() async {
      try {
        await _discardSession(force: true);
      } finally {
        await _states.close();
      }
    }, cleanup: true);
  }
}

Exception _visionKitFailure(PlatformException error) =>
    error.code == 'scan_cancelled'
    ? const ScanCancelled()
    : ScanFailure(switch (error.code) {
        'scan_permission_denied' => 'Camera access is disabled. Allow Domabas to use the camera in iOS Settings, then try again.',
        'scan_permission_restricted' => 'Camera access is restricted on this device. Check its parental or device management settings.',
        'scan_unsupported' =>
          'Apple document scanning is not supported on this device.',
        'scan_too_many_pages' => 'This scan has more pages than the draft can hold. Scan only the number of remaining pages shown in the draft.',
        'scan_too_large' => 'This scanned page exceeds 18 MiB or 50 megapixels. Discard the remaining scans and scan a smaller document area.',
        'scan_busy' =>
          'A scan is already open. Finish or cancel it, then try again.',
        'scan_activity_unavailable' => 'The scanner screen is unavailable. Return to the draft and try again.',
        'scan_failed' => 'Apple document scanning could not finish. Open the scanner and try again.',
        'scan_read_failed' || 'scan_result_invalid' => 'The scanned page could not be read. Retry importing the pending pages or discard them and scan again.',
        _ => 'Apple document scanning could not open. Try again.',
      });
