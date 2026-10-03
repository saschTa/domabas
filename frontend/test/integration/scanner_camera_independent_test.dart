import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    as platform;
import 'package:document_scan/document_scan.dart' as scan;
import 'package:domabas/data/document/models/prepared_document_upload_metadata.dart';
import 'package:domabas/data/scanner/datasources/native_scanner_camera.dart';
import 'package:domabas/data/scanner/datasources/scan_draft_store.dart';
import 'package:domabas/data/scanner/datasources/scan_pdf_encoder.dart';
import 'package:domabas/data/scanner/datasources/scan_storage_coordinator.dart';
import 'package:domabas/data/scanner/models/scan_image_limits.dart';
import 'package:domabas/data/scanner/repos/local_scan_draft_repository.dart';
import 'package:domabas/data/scanner/repos/scan_upload_data_port.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native camera frame boundary', () {
    test('BGRA retains padded rows, bytes and all right-angle rotations', () {
      final bytes = Uint8List.fromList(List.generate(48, (index) => index));
      final frame = CameraImage.fromPlatformInterface(
        _frame(
          width: 3,
          height: 3,
          format: ImageFormatGroup.bgra8888,
          planes: [_plane(bytes: bytes, row: 16, pixel: 4)],
        ),
      );
      for (final rotation in [0, 90, 180, 270]) {
        final input = NativeScannerCamera.frameInput(
          frame,
          rotation,
        ) as scan.CameraFrameScanInput;
        expect(input.format, scan.ScanImageFormat.bgra8888);
        expect((input.width, input.height), (3, 3));
        expect(input.rotation, rotation);
        expect(input.bytesPerRow, 16);
        expect(input.bytes, bytes);
      }
    });

    test(
      'BGRA rejects missing trailing row padding, short rows and extra planes',
      () {
        for (final planes in [
          [_plane(length: 43, row: 16, pixel: 4)],
          [_plane(length: 44, row: 16, pixel: 4)],
          [_plane(length: 47, row: 16, pixel: 4)],
          [_plane(length: 44, row: 11, pixel: 4)],
          [_plane(length: 44, row: 16, pixel: 4), _plane(length: 1, row: 1)],
          <platform.CameraImagePlane>[],
        ]) {
          expect(
            () => NativeScannerCamera.frameInput(
              CameraImage.fromPlatformInterface(
                _frame(
                  width: 3,
                  height: 3,
                  format: ImageFormatGroup.bgra8888,
                  planes: planes,
                ),
              ),
              0,
            ),
            throwsA(isA<ScanFailure>()),
          );
        }
      },
    );

    test(
      'odd YUV dimensions preserve padded planar and interleaved chroma',
      () {
        for (final pixelStride in [1, 2]) {
          final chromaLength = 8 + 2 * pixelStride + 1;
          final y = _plane(length: 21, row: 8, pixel: 1);
          final u = _plane(length: chromaLength, row: 8, pixel: pixelStride);
          final v = _plane(length: chromaLength, row: 8, pixel: pixelStride);
          final input = NativeScannerCamera.frameInput(
            CameraImage.fromPlatformInterface(
              _frame(width: 5, height: 3, planes: [y, u, v]),
            ),
            270,
          ) as scan.CameraFrameScanInput;
          expect((input.width, input.height, input.rotation), (5, 3, 270));
          expect(input.format, scan.ScanImageFormat.yuv420);
          expect(input.yRowStride, 8);
          expect(input.uvRowStride, 8);
          expect(input.uvPixelStride, pixelStride);
          expect(input.yBytes, y.bytes);
          expect(input.uBytes, u.bytes);
          expect(input.vBytes, v.bytes);
        }
      },
    );

    test('YUV rejects malformed plane extents and incompatible strides', () {
      final y = _plane(length: 21, row: 8, pixel: 1);
      final uv = _plane(length: 13, row: 8, pixel: 2);
      final cases = <String, List<platform.CameraImagePlane>>{
        'missing plane': [y, uv],
        'short luminance': [_plane(length: 20, row: 8, pixel: 1), uv, uv],
        'short chroma': [y, _plane(length: 12, row: 8, pixel: 2), uv],
        'short luminance row': [_plane(length: 21, row: 4, pixel: 1), uv, uv],
        'short chroma row': [
          y,
          _plane(length: 13, row: 4, pixel: 2),
          _plane(length: 13, row: 4, pixel: 2),
        ],
        'different chroma rows': [y, _plane(length: 14, row: 9, pixel: 2), uv],
        'different chroma pixels': [
          y,
          _plane(length: 13, row: 8, pixel: 1),
          uv,
        ],
        'unsupported chroma pixels': [
          y,
          _plane(length: 15, row: 8, pixel: 3),
          _plane(length: 15, row: 8, pixel: 3),
        ],
        'unsupported luminance pixels': [
          _plane(length: 21, row: 8, pixel: 2),
          uv,
          uv,
        ],
      };
      for (final entry in cases.entries) {
        expect(
          () => NativeScannerCamera.frameInput(
            CameraImage.fromPlatformInterface(
              _frame(width: 5, height: 3, planes: entry.value),
            ),
            90,
          ),
          throwsA(isA<ScanFailure>()),
          reason: entry.key,
        );
      }
    });

    test('invalid dimensions and unknown formats fail before detection', () {
      for (final size in [(0, 3), (3, 0), (-1, 3), (5000, 4001)]) {
        expect(
          () => NativeScannerCamera.frameInput(
            CameraImage.fromPlatformInterface(
              _frame(width: size.$1, height: size.$2, planes: const []),
            ),
            0,
          ),
          throwsA(isA<ScanFailure>()),
        );
      }
      expect(
        () => NativeScannerCamera.frameInput(
          CameraImage.fromPlatformInterface(
            _frame(
              width: 3,
              height: 3,
              format: ImageFormatGroup.unknown,
              planes: const [],
            ),
          ),
          0,
        ),
        throwsA(isA<ScanFailure>()),
      );
    });
  });

  group('native camera ownership', () {
    late Directory root;
    late ScanStorageCoordinator coordinator;
    late _StorageUsage storageUsage;
    late ScanStorageLease lease;
    late _CameraPlatform cameraPlatform;
    late platform.CameraPlatform previousPlatform;
    late _Detector detector;
    late NativeScannerCamera camera;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('domabas-native-camera-');
      storageUsage = _StorageUsage();
      coordinator = ScanStorageCoordinator(
        () async => root,
        usage: storageUsage,
      );
      lease = await coordinator.acquire('camera-owner');
      previousPlatform = platform.CameraPlatform.instance;
      cameraPlatform = _CameraPlatform(root);
      platform.CameraPlatform.instance = cameraPlatform;
      detector = _Detector();
      camera = NativeScannerCamera(lease, detector: detector);
    });

    tearDown(() async {
      detector.finishPending();
      cameraPlatform.finishInitialization();
      cameraPlatform.finishCapture();
      storageUsage.finishPending();
      await camera.close();
      await lease.release();
      await cameraPlatform.closeStreams();
      platform.CameraPlatform.instance = previousPlatform;
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'shutter precedes detector drain and preserves capture phase geometry',
      () async {
        await camera.start();
        final dimensions = (camera.state.width, camera.state.height);
        final pending = detector.holdNext();
        cameraPlatform.emit(_liveFrame());
        cameraPlatform.picture = Completer<void>();
        var completed = false;
        final capturing = camera.capture().then((capture) {
          completed = true;
          return capture;
        });
        await cameraPlatform.pictureEntered.future.timeout(
          const Duration(seconds: 2),
        );
        expect(camera.state.status, ScanCameraStatus.capturing);
        expect((camera.state.width, camera.state.height), dimensions);
        expect(cameraPlatform.streamStops, 0);
        expect(cameraPlatform.disposals, 0);
        expect(detector.files, isEmpty);
        expect(completed, isFalse);
        await expectLater(camera.capture(), throwsA(isA<ScanFailure>()));
        expect(cameraPlatform.captureCalls, 1);

        cameraPlatform.finishCapture();
        await cameraPlatform.streamStopped.future.timeout(
          const Duration(seconds: 2),
        );
        expect(camera.state.status, ScanCameraStatus.processing);
        expect((camera.state.width, camera.state.height), dimensions);
        expect(detector.files, isEmpty);
        expect(cameraPlatform.disposals, 0);
        expect(completed, isFalse);
        pending.complete(_corners());
        final capture = await capturing;
        expect(detector.files, hasLength(1));
        expect(cameraPlatform.disposals, 1);
        expect(await cameraPlatform.original!.exists(), isFalse);
        await camera.releaseCapture(capture.id);
        expect(lease.scratchBytes, 0);
      },
    );

    test(
      'late live detection failure cannot replace the capturing phase',
      () async {
        await camera.start();
        final pending = detector.holdNext();
        cameraPlatform.emit(_liveFrame());
        cameraPlatform.picture = Completer<void>();
        final capturing = camera.capture();
        await cameraPlatform.pictureEntered.future;
        pending.completeError(StateError('Fixture live detection failed'));
        await Future<void>.delayed(Duration.zero);
        expect(camera.state.status, ScanCameraStatus.capturing);
        expect(camera.state.message, isNull);
        expect(detector.files, isEmpty);
        cameraPlatform.finishCapture();
        final capture = await capturing;
        expect(detector.files, hasLength(1));
        await camera.releaseCapture(capture.id);
      },
    );

    for (final interruption in ['suspend', 'close', 'cancel']) {
      test(
        '$interruption during startup storage admission prevents readiness',
        () async {
          storageUsage.holdNext();
          final starting = camera.start();
          await storageUsage.entered.future;
          expect(camera.state.status, ScanCameraStatus.starting);
          await expectLater(camera.capture(), throwsA(isA<ScanFailure>()));
          expect(detector.frames, isEmpty);
          expect(cameraPlatform.captureCalls, 0);
          Future<void>? lifecycle;
          switch (interruption) {
            case 'suspend':
              lifecycle = camera.suspend();
            case 'close':
              lifecycle = camera.close();
            case 'cancel':
              camera.cancelNewOperations();
          }
          storageUsage.finishPending();
          await starting;
          await lifecycle;
          expect(cameraPlatform.captureCalls, 0);
          expect(cameraPlatform.disposals, 1);
          expect(lease.scratchBytes, 0);
          expect(camera.currentController, isNull);
          expect(await lease.directory.list().isEmpty, isTrue);
          final release = await coordinator.acquireCamera().timeout(
            const Duration(seconds: 2),
          );
          release();
        },
      );
    }

    test(
      'storage admission failure releases camera ownership without a shot',
      () async {
        storageUsage.failure = const ScanFailure('Fixture quota exhausted');
        await camera.start();
        expect(camera.state.status, ScanCameraStatus.unavailable);
        expect(camera.state.message, 'Fixture quota exhausted');
        expect(cameraPlatform.captureCalls, 0);
        expect(cameraPlatform.disposals, 1);
        expect(lease.scratchBytes, 0);
        expect(camera.currentController, isNull);
        await camera.start();
        expect(camera.state.status, ScanCameraStatus.ready);
      },
    );

    test('ready camera reaches shutter without another storage scan', () async {
      await camera.start();
      expect(lease.scratchBytes, ScanImageLimits.captureReservationBytes);
      storageUsage.holdNext();
      cameraPlatform.picture = Completer<void>();
      final capturing = camera.capture();
      await cameraPlatform.pictureEntered.future.timeout(
        const Duration(seconds: 2),
      );
      expect(storageUsage.entered.isCompleted, isFalse);
      cameraPlatform.finishCapture();
      final capture = await capturing;
      await camera.releaseCapture(capture.id);
      expect(lease.scratchBytes, 0);
    });

    test('maximum detail settings are ready before capture', () async {
      await camera.start();
      expect(cameraPlatform.settings!.resolutionPreset, ResolutionPreset.max);
      expect(cameraPlatform.settings!.enableAudio, isFalse);
      expect(cameraPlatform.quality, 100);
      expect(cameraPlatform.flash, FlashMode.off);
      expect(cameraPlatform.focus, FocusMode.auto);
      expect(cameraPlatform.exposure, ExposureMode.auto);
      expect(cameraPlatform.exposureOffset, -1);
      final before = List<String>.of(cameraPlatform.settingCalls);
      final capture = await camera.capture();
      expect(cameraPlatform.settingCalls, before);
      await camera.releaseCapture(capture.id);
    });

    test('unsupported optional camera settings preserve capture', () async {
      cameraPlatform.rejectSettings = true;
      await camera.start();
      expect(camera.state.status, ScanCameraStatus.ready);
      final capture = await camera.capture();
      expect(capture.preview, isNotEmpty);
      await camera.releaseCapture(capture.id);
    });

    for (final closing in [false, true]) {
      test(
        '${closing ? 'close' : 'suspend'} during the shot drains before handoff',
        () async {
          await camera.start();
          cameraPlatform.picture = Completer<void>();
          final capturing = camera.capture();
          await cameraPlatform.pictureEntered.future;
          var drained = false;
          final lifecycle = (closing ? camera.close() : camera.suspend()).then((
            _,
          ) {
            drained = true;
          });
          var handedOff = false;
          final handoff = coordinator.acquireCamera().then((release) {
            handedOff = true;
            return release;
          });
          await Future<void>.delayed(Duration.zero);
          expect(cameraPlatform.disposals, 0);
          expect(drained, isFalse);
          expect(handedOff, isFalse);
          cameraPlatform.finishCapture();
          final capture = await capturing;
          await lifecycle;
          final release = await handoff.timeout(const Duration(seconds: 2));
          release();
          expect(cameraPlatform.disposals, 1);
          expect(camera.currentController, isNull);
          expect(await cameraPlatform.original!.exists(), isFalse);
          final scratch = File(
            '${lease.directory.path}/scratch-${capture.id}.jpg',
          );
          expect(await scratch.exists(), !closing);
          expect(
            lease.scratchBytes,
            closing ? 0 : ScanImageLimits.captureReservationBytes,
          );
          if (!closing) await camera.releaseCapture(capture.id);
        },
      );
    }

    test(
      'shutter failure still drains the detector and releases its reservation',
      () async {
        await camera.start();
        final pending = detector.holdNext();
        cameraPlatform.emit(_liveFrame());
        cameraPlatform.failPicture = true;
        final capturing = expectLater(camera.capture(), throwsStateError);
        await cameraPlatform.pictureEntered.future;
        await cameraPlatform.streamStopped.future;
        expect(cameraPlatform.disposals, 0);
        expect(detector.files, isEmpty);
        pending.complete(_corners());
        await capturing;
        expect(cameraPlatform.disposals, 1);
        expect(lease.scratchBytes, 0);
        expect(camera.currentController, isNull);
        expect(await lease.directory.list().isEmpty, isTrue);
        await camera.start();
        expect(camera.state.status, ScanCameraStatus.ready);
      },
    );

    test('stream stop failure after the shot removes the original and releases quota', () async {
      await camera.start();
      cameraPlatform.failStop = true;
      await expectLater(camera.capture(), throwsStateError);
      expect(cameraPlatform.captureCalls, 1);
      expect(cameraPlatform.disposals, 1);
      expect(await cameraPlatform.original!.exists(), isFalse);
      expect(lease.scratchBytes, 0);
      expect(camera.currentController, isNull);
      expect(await lease.directory.list().isEmpty, isTrue);
    });

    test(
      'captured source survives suspend and Keep cleanup, then releases',
      () async {
        final store = ScanDraftStore(lease);
        final repository = LocalScanDraftRepository(
          lease: lease,
          camera: camera,
          upload: _UnexpectedUpload(),
          store: store,
          encoder: ScanPdfEncoder(),
        );
        addTearDown(repository.close);
        await repository.restore();
        await camera.start();
        expect(camera.state.status, ScanCameraStatus.ready);
        final capture = await camera.capture();
        final scratch = File(
          '${lease.directory.path}/scratch-${capture.id}.jpg',
        );
        expect(await scratch.exists(), isTrue);
        expect(await cameraPlatform.original!.exists(), isFalse);
        expect(lease.scratchBytes, ScanImageLimits.captureReservationBytes);
        expect(camera.currentController, isNull);
        await camera.suspend();
        expect(await scratch.exists(), isTrue);

        final saved = await repository.keepPage(capture, capture.corners);
        expect(saved.pages, hasLength(1));
        expect(await scratch.exists(), isFalse);
        expect(lease.scratchBytes, 0);
        final entry =
            (store.record!['pages'] as List).single as Map<String, dynamic>;
        final bytes = await store.verifyAsset(
          store.record!,
          entry,
          'file',
          3 * 1024 * 1024,
        );
        final corrected = img.decodeJpg(bytes)!;
        _expectQuadrants(corrected);
        expect(img.decodeJpg(saved.pages.single.thumbnail), isNotNull);
        final retried = await repository.keepPage(capture, capture.corners);
        expect(retried.pages.single.id, saved.pages.single.id);
        expect(retried.revision, saved.revision);
        final restored = ScanDraftStore(lease);
        await restored.initialize();
        expect(
          (await restored.snapshot()).pages.single.id,
          saved.pages.single.id,
        );
        restored.release();
      },
    );

    for (final (orientation, colors) in [
      (1, ['red', 'green', 'yellow', 'blue']),
      (2, ['green', 'red', 'blue', 'yellow']),
      (3, ['yellow', 'blue', 'red', 'green']),
      (4, ['blue', 'yellow', 'green', 'red']),
      (5, ['red', 'blue', 'yellow', 'green']),
      (6, ['blue', 'red', 'green', 'yellow']),
      (7, ['yellow', 'green', 'red', 'blue']),
      (8, ['green', 'yellow', 'blue', 'red']),
    ]) {
      test(
        'EXIF $orientation capture and correction preserve asymmetric pixels',
        () async {
          cameraPlatform.orientationTag = orientation;
          await camera.start();
          final capture = await camera.capture();
          final dimensions = orientation >= 5 ? (144, 96) : (96, 144);
          expect((capture.width, capture.height), dimensions);
          final preview = img.decodeJpg(capture.preview)!;
          expect((preview.width, preview.height), dimensions);
          final corrected = await camera.correct(capture, capture.corners);
          final decoded = img.decodeJpg(corrected.bytes)!;
          for (final image in [preview, decoded]) {
            _expectColor(image, .25, .25, colors[0]);
            _expectColor(image, .75, .25, colors[1]);
            _expectColor(image, .75, .75, colors[2]);
            _expectColor(image, .25, .75, colors[3]);
          }
          await camera.releaseCapture(capture.id);
          expect(lease.scratchBytes, 0);
          await expectLater(
            camera.correct(capture, capture.corners),
            throwsA(isA<ScanFailure>()),
          );
        },
      );
    }

    test(
      'full-resolution detail survives capture, correction, restore and PDF',
      () async {
        const width = 2400, height = 3200;
        final source = img.Image(width: width, height: height);
        img.fill(source, color: img.ColorRgb8(255, 255, 255));
        for (var x = 1100; x < 1300; x += 8) {
          img.fillRect(
            source,
            x1: x,
            y1: 1000,
            x2: x + 2,
            y2: 2200,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
        cameraPlatform.photoBytes = img.encodeJpg(source, quality: 100);
        final store = ScanDraftStore(lease);
        final repository = LocalScanDraftRepository(
          lease: lease,
          camera: camera,
          upload: _UnexpectedUpload(),
          store: store,
          encoder: ScanPdfEncoder(),
        );
        addTearDown(repository.close);
        await repository.restore();
        await camera.start();
        final capture = await camera.capture();
        expect((capture.width, capture.height), (width, height));
        final retained = await File(
          '${lease.directory.path}/scratch-${capture.id}.jpg',
        ).readAsBytes();
        expect(retained, cameraPlatform.photoBytes);
        final saved = await repository.keepPage(
          capture,
          ScanCorners.fullImage(),
        );
        expect(
          (saved.pages.single.width, saved.pages.single.height),
          (width, height),
        );
        final restored = ScanDraftStore(lease);
        await restored.initialize();
        expect(restored.blocked, isFalse);
        final page =
            (restored.record!['pages'] as List).single as Map<String, dynamic>;
        final file = restored.asset(restored.record!, page['file'] as String);
        final corrected = img.decodeJpg(await file.readAsBytes())!;
        expect(corrected.getPixel(1197, 1600).r, lessThan(90));
        expect(corrected.getPixel(1201, 1600).r, greaterThan(220));
        final pdf = await ScanPdfEncoder().encode([
          ScanPdfPage(file.path, width, height),
        ]);
        final pdfObjects = latin1.decode(pdf);
        expect(pdfObjects, contains('/Width $width'));
        expect(pdfObjects, contains('/Height $height'));
        expect(pdfObjects, contains('/DCTDecode'));
        restored.release();
      },
    );

    test(
      'release for another capture cannot delete the current correction source',
      () async {
        await camera.start();
        final capture = await camera.capture();
        final scratch = File(
          '${lease.directory.path}/scratch-${capture.id}.jpg',
        );
        await camera.releaseCapture('stale-capture');
        expect(await scratch.exists(), isTrue);
        final invalid = ScanCorners(const [
          ScanPoint(0, 0),
          ScanPoint(1, 1),
          ScanPoint(1, 0),
          ScanPoint(0, 1),
        ]);
        await expectLater(
          camera.correct(capture, invalid),
          throwsA(isA<ScanFailure>()),
        );
        expect(await scratch.exists(), isTrue);
        expect(lease.scratchBytes, ScanImageLimits.captureReservationBytes);
        await camera.close();
        expect(await scratch.exists(), isFalse);
        expect(lease.scratchBytes, 0);
      },
    );

    test(
      'perspective correction straightens a projected page and its markers',
      () async {
        final sourceBytes = img.encodeJpg(
          _projectedGridDocument(),
          quality: 95,
        );
        cameraPlatform.photoBytes = sourceBytes;
        await camera.start();
        final capture = await camera.capture();
        expect((capture.width, capture.height), (800, 1000));
        final corners = ScanCorners(const [
          ScanPoint(.25, .10),
          ScanPoint(.75, .10),
          ScanPoint(.875, .90),
          ScanPoint(.125, .90),
        ]);
        final corrected = await camera.correct(capture, corners);
        expect((corrected.width, corrected.height), (500, 806));
        expect(corrected.width / corrected.height, closeTo(.6203, .001));
        final image = img.decodeJpg(corrected.bytes)!;
        _expectQuadrants(image);
        for (final marker in [
          (color: 'red', x: .25, y: .25),
          (color: 'green', x: .75, y: .25),
          (color: 'blue', x: .25, y: .75),
          (color: 'yellow', x: .75, y: .75),
        ]) {
          final center = _markerCenter(image, marker.color);
          expect(
            center.x,
            closeTo(marker.x, .01),
            reason: '${marker.color} marker x',
          );
          expect(
            center.y,
            closeTo(marker.y, .01),
            reason: '${marker.color} marker y',
          );
        }
        for (final position in [.1, .2, .3, .4, .6, .7, .8, .9]) {
          _expectBrightness(image, .5, position, dark: true);
          _expectBrightness(image, position, .5, dark: true);
          _expectBrightness(image, .46, position, dark: false);
          _expectBrightness(image, .54, position, dark: false);
          _expectBrightness(image, position, .46, dark: false);
          _expectBrightness(image, position, .54, dark: false);
        }
        for (final position in [.02, .08, .18, .35, .65, .82, .92, .98]) {
          _expectBrightness(image, .02, position, dark: false);
          _expectBrightness(image, .98, position, dark: false);
          _expectBrightness(image, position, .02, dark: false);
          _expectBrightness(image, position, .98, dark: false);
        }
        final evidencePath = Platform.environment['SCANNER_TEST_EVIDENCE_DIR'];
        if (evidencePath != null) {
          final evidence = await Directory(evidencePath)
              .create(recursive: true);
          await File('${evidence.path}/perspective-capture.jpg')
              .writeAsBytes(sourceBytes);
          await File('${evidence.path}/perspective-corrected.jpg')
              .writeAsBytes(corrected.bytes);
        }
        await camera.releaseCapture(capture.id);
        expect(lease.scratchBytes, 0);
      },
    );

    test(
      'corrupt capture releases its original, scratch quota and camera',
      () async {
        cameraPlatform.invalidPhoto = true;
        await camera.start();
        await expectLater(camera.capture(), throwsA(isA<ScanFailure>()));
        expect(await cameraPlatform.original!.exists(), isFalse);
        expect(await lease.directory.list().isEmpty, isTrue);
        expect(lease.scratchBytes, 0);
        expect(camera.currentController, isNull);
        final release = await coordinator.acquireCamera().timeout(
          const Duration(seconds: 2),
        );
        release();
      },
    );

    test('orientation discards in-flight corners and later frames use new rotation', () async {
      await camera.start();
      final generation = camera.state.generation;
      final pending = detector.holdNext();
      cameraPlatform.emit(_liveFrame());
      expect(detector.frames, hasLength(1));
      expect(detector.frames.single.rotation, Platform.isIOS ? 0 : 90);
      cameraPlatform.orient(DeviceOrientation.landscapeLeft);
      expect(camera.state.generation, greaterThan(generation));
      expect((camera.state.width, camera.state.height), (640, 480));
      pending.complete(_corners());
      await Future<void>.delayed(Duration.zero);
      expect(camera.state.corners, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 110));
      cameraPlatform.emit(_liveFrame(portrait: false));
      await Future<void>.delayed(Duration.zero);
      expect(detector.frames, hasLength(2));
      expect(detector.frames.last.rotation, 0);
      expect(camera.state.corners, isNotNull);
      expect((camera.state.width, camera.state.height), (640, 480));
    });

    test(
      'different analysis framing hides corners while preserving the preview',
      () async {
        await camera.start();
        cameraPlatform.emit(
          _frame(
            width: 8,
            height: 8,
            planes: [
              _plane(length: 64, row: 8, pixel: 1),
              _plane(length: 16, row: 4, pixel: 1),
              _plane(length: 16, row: 4, pixel: 1),
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(detector.frames, isEmpty);
        expect(camera.state.status, ScanCameraStatus.ready);
        expect((camera.state.width, camera.state.height), (480, 640));
        expect(camera.state.corners, isNull);
        expect(camera.state.message, contains('different framing area'));
        final capture = await camera.capture();
        expect((capture.width, capture.height), (96, 144));
        expect(
          (await camera.correct(capture, capture.corners)).bytes,
          isNotEmpty,
        );
      },
    );

    for (final (orientation, rotation, portrait) in [
      (DeviceOrientation.portraitUp, 90, true),
      (DeviceOrientation.landscapeLeft, 0, false),
      (DeviceOrientation.portraitDown, 270, true),
      (DeviceOrientation.landscapeRight, 180, false),
    ]) {
      test(
        'matching $orientation frame retains preview geometry and corners',
        () async {
          await camera.start();
          cameraPlatform.orient(orientation);
          cameraPlatform.emit(_liveFrame(portrait: portrait));
          await Future<void>.delayed(Duration.zero);
          expect(
            detector.frames.single.rotation,
            Platform.isIOS ? 0 : rotation,
          );
          expect(camera.state.rotation, Platform.isIOS ? 0 : rotation);
          expect((
            camera.state.width,
            camera.state.height,
          ), portrait ? (480, 640) : (640, 480));
          expect(camera.state.corners!.points.first.x, closeTo(.1, .0001));
          expect(camera.state.corners!.points.first.y, closeTo(.1, .0001));
        },
      );
    }

    test(
      'suspend drains detection before camera handoff and rejects extra frames',
      () async {
        await camera.start();
        final pending = detector.holdNext();
        cameraPlatform.emit(_liveFrame());
        cameraPlatform.emit(_liveFrame());
        expect(detector.frames, hasLength(1));
        var suspended = false;
        final suspension = camera.suspend().then((_) {
          suspended = true;
        });
        var handedOff = false;
        final handoff = coordinator.acquireCamera().then((release) {
          handedOff = true;
          return release;
        });
        await Future<void>.delayed(Duration.zero);
        expect(suspended, isFalse);
        expect(handedOff, isFalse);
        expect(cameraPlatform.disposals, 0);
        pending.complete(_corners());
        await suspension;
        final release = await handoff.timeout(const Duration(seconds: 2));
        release();
        expect(cameraPlatform.disposals, 1);
        expect(camera.state.status, ScanCameraStatus.suspended);
        expect(camera.state.corners, isNull);
      },
    );

    test(
      'close waits for initialization and never starts a cancelled stream',
      () async {
        cameraPlatform.initialization = Completer<void>();
        final starting = camera.start();
        await cameraPlatform.initializationEntered.future;
        var closed = false;
        final closing = camera.close().then((_) {
          closed = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
        expect(cameraPlatform.disposals, 0);
        cameraPlatform.finishInitialization();
        await starting;
        await closing;
        expect(cameraPlatform.streamStarts, 0);
        expect(cameraPlatform.disposals, 1);
        expect(camera.currentController, isNull);
        final release = await coordinator.acquireCamera().timeout(
          const Duration(seconds: 2),
        );
        release();
      },
    );

    for (final failure in ['stream cancellation', 'controller disposal']) {
      test('$failure failure still releases the shared camera lease', () async {
        await camera.start();
        cameraPlatform.failStop = failure == 'stream cancellation';
        cameraPlatform.failDispose = failure == 'controller disposal';
        await expectLater(camera.suspend(), throwsStateError);
        expect(cameraPlatform.disposals, 1);
        expect(camera.currentController, isNull);
        final release = await coordinator.acquireCamera().timeout(
          const Duration(seconds: 2),
        );
        release();
        await camera.start();
        expect(camera.state.status, ScanCameraStatus.ready);
      });
    }
  });
}

platform.CameraImagePlane _plane({
  Uint8List? bytes,
  int length = 0,
  required int row,
  int? pixel,
}) => platform.CameraImagePlane(
  bytes: bytes ?? Uint8List(length),
  bytesPerRow: row,
  bytesPerPixel: pixel,
);

platform.CameraImageData _frame({
  required int width,
  required int height,
  ImageFormatGroup format = ImageFormatGroup.yuv420,
  required List<platform.CameraImagePlane> planes,
}) => platform.CameraImageData(
  format: platform.CameraImageFormat(format, raw: format.index),
  width: width,
  height: height,
  planes: planes,
);

platform.CameraImageData _liveFrame({bool portrait = true}) {
  final width = Platform.isIOS && portrait ? 6 : 8;
  final height = Platform.isIOS && portrait ? 8 : 6;
  return _frame(
    width: width,
    height: height,
    planes: [
      _plane(length: 48, row: width, pixel: 1),
      _plane(length: 12, row: width ~/ 2, pixel: 1),
      _plane(length: 12, row: width ~/ 2, pixel: 1),
    ],
  );
}

scan.DocumentCorners _corners() => const scan.DocumentCorners(
  topLeft: (x: .1, y: .1),
  topRight: (x: .9, y: .1),
  bottomRight: (x: .9, y: .9),
  bottomLeft: (x: .1, y: .9),
);

final class _Detector extends scan.DocumentDetector {
  final frames = <scan.CameraFrameScanInput>[];
  final files = <scan.FileScanInput>[];
  final pending = <Completer<scan.DocumentCorners?>>[];
  Completer<scan.DocumentCorners?>? _next;

  Completer<scan.DocumentCorners?> holdNext() {
    final gate = Completer<scan.DocumentCorners?>();
    pending.add(gate);
    _next = gate;
    return gate;
  }

  void finishPending() {
    for (final gate in pending) {
      if (!gate.isCompleted) gate.complete(null);
    }
  }

  @override
  Future<scan.DocumentCorners?> detect(
    scan.ScanInput input, {
    scan.DetectionSensitivity sensitivity = scan.DetectionSensitivity.balanced,
  }) async {
    if (input is scan.FileScanInput) files.add(input);
    if (input is! scan.CameraFrameScanInput) return null;
    frames.add(input);
    final gate = _next;
    _next = null;
    return gate == null ? _corners() : gate.future;
  }
}

final class _CameraPlatform extends platform.CameraPlatform {
  _CameraPlatform(this.root);
  final Directory root;
  final orientations =
      StreamController<platform.DeviceOrientationChangedEvent>.broadcast(
        sync: true,
      );
  final streams = <int, StreamController<platform.CameraImageData>>{};
  final errors = <int, StreamController<platform.CameraErrorEvent>>{};
  final initializationEntered = Completer<void>();
  final pictureEntered = Completer<void>();
  final streamStopped = Completer<void>();
  Completer<void>? initialization;
  Completer<void>? picture;
  File? original;
  Uint8List? photoBytes;
  platform.MediaSettings? settings;
  int? quality;
  FlashMode? flash;
  FocusMode? focus;
  ExposureMode? exposure;
  double? exposureOffset;
  bool rejectSettings = false;
  final settingCalls = <String>[];
  int _nextId = 0,
      disposals = 0,
      streamStarts = 0,
      streamStops = 0,
      captureCalls = 0;
  int? orientationTag;
  bool failStop = false,
      failDispose = false,
      failPicture = false,
      invalidPhoto = false;

  void emit(platform.CameraImageData frame) => streams[_nextId]!.add(frame);
  void orient(DeviceOrientation orientation) =>
      orientations.add(platform.DeviceOrientationChangedEvent(orientation));
  void finishInitialization() {
    final gate = initialization;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void finishCapture() {
    final gate = picture;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'fixture-rear',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    platform.MediaSettings settings,
  ) async {
    this.settings = settings;
    return ++_nextId;
  }

  void setting(String name) {
    settingCalls.add(name);
    if (rejectSettings) throw CameraException('unsupported', name);
  }

  @override
  Future<void> setJpegImageQuality(int cameraId, int quality) async {
    setting('quality');
    this.quality = quality;
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    setting('flash');
    flash = mode;
  }

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {
    setting('focus');
    focus = mode;
  }

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {
    setting('exposure');
    exposure = mode;
  }

  @override
  Future<double> getMinExposureOffset(int cameraId) async => -2;

  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 2;

  @override
  Future<double> getExposureOffsetStepSize(int cameraId) async => .25;

  @override
  Future<double> setExposureOffset(int cameraId, double offset) async {
    setting('offset');
    exposureOffset = offset;
    return offset;
  }

  @override
  Stream<platform.CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        platform.CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<platform.CameraErrorEvent> onCameraError(int cameraId) {
    final controller = StreamController<platform.CameraErrorEvent>();
    errors[cameraId] = controller;
    return controller.stream;
  }

  @override
  Stream<platform.DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientations.stream;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    if (!initializationEntered.isCompleted) initializationEntered.complete();
    await initialization?.future;
  }

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<platform.CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    platform.CameraImageStreamOptions? options,
  }) {
    streamStarts++;
    final stream = StreamController<platform.CameraImageData>(
      sync: true,
      onCancel: () async {
        streamStops++;
        if (!streamStopped.isCompleted) streamStopped.complete();
        if (failStop) {
          failStop = false;
          throw StateError('Fixture stream cancellation failed');
        }
      },
    );
    streams[cameraId] = stream;
    return stream.stream;
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    captureCalls++;
    if (!pictureEntered.isCompleted) pictureEntered.complete();
    await picture?.future;
    if (failPicture) {
      failPicture = false;
      throw StateError('Fixture shutter failed');
    }
    final file = File('${root.path}/platform-capture-$cameraId.jpg');
    original = file;
    final fixture = photoBytes;
    if (fixture != null) {
      await file.writeAsBytes(fixture);
      return XFile(file.path);
    }
    final image = img.Image(width: 96, height: 144);
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 47,
      y2: 71,
      color: img.ColorRgb8(230, 20, 20),
    );
    img.fillRect(
      image,
      x1: 48,
      y1: 0,
      x2: 95,
      y2: 71,
      color: img.ColorRgb8(20, 230, 20),
    );
    img.fillRect(
      image,
      x1: 0,
      y1: 72,
      x2: 47,
      y2: 143,
      color: img.ColorRgb8(20, 20, 230),
    );
    img.fillRect(
      image,
      x1: 48,
      y1: 72,
      x2: 95,
      y2: 143,
      color: img.ColorRgb8(230, 230, 20),
    );
    if (orientationTag != null) {
      image.exif.imageIfd.orientation = orientationTag;
    }
    await file.writeAsBytes(
      invalidPhoto ? [1, 2, 3] : img.encodeJpg(image, quality: 95),
    );
    return XFile(file.path);
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposals++;
    errors[cameraId]?.add(platform.CameraErrorEvent(cameraId, 'disposed'));
    if (failDispose) {
      failDispose = false;
      throw StateError('Fixture camera disposal failed');
    }
  }

  Future<void> closeStreams() async {
    await orientations.close();
    for (final stream in streams.values) {
      await stream.close();
    }
    for (final stream in errors.values) {
      await stream.close();
    }
  }
}

final class _StorageUsage extends ScanStorageUsage {
  final entered = Completer<void>();
  Completer<void>? _pending;
  ScanFailure? failure;

  void holdNext() => _pending = Completer<void>();

  void finishPending() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  Future<int> bytes(Directory directory, {required bool includeScratch}) async {
    if (_pending case final pending?) {
      if (!entered.isCompleted) entered.complete();
      await pending.future;
      _pending = null;
    }
    if (failure case final error?) {
      failure = null;
      throw error;
    }
    return super.bytes(directory, includeScratch: includeScratch);
  }
}

img.Image _projectedGridDocument() {
  final image = img.Image(width: 800, height: 1000);
  img.fill(image, color: img.ColorRgb8(20, 20, 20));
  const markers = [
    (x: .25, y: .25, color: (230, 20, 20)),
    (x: .75, y: .25, color: (20, 230, 20)),
    (x: .25, y: .75, color: (20, 20, 230)),
    (x: .75, y: .75, color: (230, 230, 20)),
  ];
  for (var y = 100; y <= 900; y++) {
    final depth = (y - 100) / (1600 / 3 + (y - 100) / 3);
    for (var x = 100; x <= 700; x++) {
      final horizontal = .5 + (x - 400) * (1 - depth / 3) / 400;
      if (horizontal < 0 || horizontal > 1) {
        continue;
      }
      var color = (240, 240, 240);
      if ((horizontal - .5).abs() < .008 || (depth - .5).abs() < .008) {
        color = (35, 35, 35);
      }
      for (final marker in markers) {
        if ((horizontal - marker.x).abs() < .055 &&
            (depth - marker.y).abs() < .055) {
          color = marker.color;
        }
      }
      image.setPixelRgb(x, y, color.$1, color.$2, color.$3);
    }
  }
  return image;
}

({double x, double y}) _markerCenter(img.Image image, String color) {
  var totalX = 0.0, totalY = 0.0, count = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final matches = switch (color) {
        'red' => pixel.r > 180 && pixel.g < 70 && pixel.b < 70,
        'green' => pixel.r < 70 && pixel.g > 180 && pixel.b < 70,
        'blue' => pixel.r < 70 && pixel.g < 70 && pixel.b > 180,
        'yellow' => pixel.r > 180 && pixel.g > 180 && pixel.b < 70,
        _ => throw ArgumentError.value(color),
      };
      if (matches) {
        totalX += x;
        totalY += y;
        count++;
      }
    }
  }
  expect(count, greaterThan(1000), reason: '$color marker remains visible');
  return (x: totalX / count / image.width, y: totalY / count / image.height);
}

void _expectBrightness(
  img.Image image,
  double x,
  double y, {
  required bool dark,
}) {
  final pixel = image.getPixel(
    (image.width * x).floor(),
    (image.height * y).floor(),
  );
  final brightness = (pixel.r + pixel.g + pixel.b) / 3;
  expect(
    brightness,
    dark ? lessThan(80) : greaterThan(200),
    reason:
        'Rectified point ($x, $y) is ${dark ? 'on the straight grid' : 'inside the white page'}',
  );
}

void _expectQuadrants(img.Image image) {
  _expectColor(image, .25, .25, 'red');
  _expectColor(image, .75, .25, 'green');
  _expectColor(image, .25, .75, 'blue');
  _expectColor(image, .75, .75, 'yellow');
}

void _expectColor(img.Image image, double x, double y, String color) {
  final pixel = image.getPixel(
    (image.width * x).floor(),
    (image.height * y).floor(),
  );
  final expected = switch (color) {
    'red' => (230, 20, 20),
    'green' => (20, 230, 20),
    'blue' => (20, 20, 230),
    'yellow' => (230, 230, 20),
    _ => throw ArgumentError.value(color),
  };
  expect(pixel.r, closeTo(expected.$1, 25), reason: '$color red channel');
  expect(pixel.g, closeTo(expected.$2, 25), reason: '$color green channel');
  expect(pixel.b, closeTo(expected.$3, 25), reason: '$color blue channel');
}

final class _UnexpectedUpload implements ScanUploadDataPort {
  @override
  PreparedDocumentUploadMetadata prepare(DocumentProperties properties) =>
      throw StateError('Keep must not upload');
  @override
  Future<Document> send(
    Uint8List pdfBytes,
    PreparedDocumentUploadMetadata metadata,
    String filename,
    Future<void> cancel,
  ) => throw StateError('Keep must not upload');
}
