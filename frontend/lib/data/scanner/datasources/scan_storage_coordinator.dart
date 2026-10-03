import 'dart:async';
import 'dart:io';

import '../../../domain/scanner/models/scan.dart';
import '../models/scan_image_limits.dart';

final class ScanStorageCoordinator {
  ScanStorageCoordinator(this.root, {ScanStorageUsage? usage})
    : _usage = usage ?? ScanStorageUsage();
  final Future<Directory> Function() root;
  final ScanStorageUsage _usage;
  final Map<String, Future<void>> _owners = {};
  final Map<String, String> acceptedReceipts = {};
  final Map<String, int> _ownerReservations = {}, _scratchReservations = {};
  Future<void> _allocation = Future.value(),
      _images = Future.value(),
      _camera = Future.value();
  int _reserved = 0;

  Future<ScanStorageLease> acquire(String owner) async {
    final previous = _owners[owner] ?? Future.value();
    final release = Completer<void>();
    _owners[owner] = release.future;
    await previous;
    try {
      final directory = Directory('${(await root()).path}/$owner');
      await directory.create(recursive: true);
      return ScanStorageLease(this, owner, directory, release);
    } catch (_) {
      release.complete();
      rethrow;
    }
  }

  Future<T> imageWork<T>(Future<T> Function() work) {
    final result = _images.then((_) => work());
    _images = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void Function()> acquireCamera() async {
    final previous = _camera;
    final release = Completer<void>();
    _camera = release.future;
    await previous;
    return () {
      if (!release.isCompleted) {
        release.complete();
      }
    };
  }

  Future<ScanReservation> reserve(
    Directory owner,
    int bytes, {
    required bool scratch,
  }) {
    final result = _allocation
        .then((_) async {
          final directory = await root();
          var total = 0;
          await for (final entry in directory.list(followLinks: false)) {
            if (entry is Directory) {
              total += await _usage.bytes(entry, includeScratch: true);
            } else if (entry is File) {
              total += await entry.length();
            }
          }
          final used = await _usage.bytes(owner, includeScratch: false);
          final ownerReserved = _ownerReservations[owner.path] ?? 0;
          final scratchReserved = _scratchReservations[owner.path] ?? 0;
          if (scratch &&
              scratchReserved + bytes >
                  ScanImageLimits.scratchReservationBytes) {
            throw const ScanFailure(
              'The capture exceeds scanner scratch space.',
            );
          }
          if (total + _reserved + bytes > 256 * 1024 * 1024 ||
              !scratch && used + ownerReserved + bytes > 40 * 1024 * 1024) {
            throw const ScanFailure(
              'Scanner storage is full. Remove pages or discard a saved draft.',
            );
          }
          _reserved += bytes;
          final map = scratch ? _scratchReservations : _ownerReservations;
          map[owner.path] = (map[owner.path] ?? 0) + bytes;
          return ScanReservation(() {
            _allocation = _allocation.then((_) {
              _reserved -= bytes;
              map[owner.path] = (map[owner.path] ?? 0) - bytes;
            });
          });
        })
        .onError<FileSystemException>((error, stack) {
          throw const ScanFailure(
            'Scanner storage changed while checking available space. Try again.',
          );
        });
    _allocation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

class ScanStorageUsage {
  Future<int> bytes(Directory directory, {required bool includeScratch}) async {
    if (!await directory.exists()) {
      return 0;
    }
    var bytes = 0, manifests = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final length = await entity.length();
      if (name == 'manifest.json' || name == 'manifest.stage') {
        manifests += length;
      } else if (includeScratch || !name.startsWith('scratch-')) {
        bytes += length;
      }
    }
    return bytes + (manifests > 256 * 1024 ? manifests : 256 * 1024);
  }
}

final class ScanReservation {
  ScanReservation(this._release);
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _release();
  }
}

final class ScanStorageLease {
  ScanStorageLease(this.coordinator, this.owner, this.directory, this._release);
  final ScanStorageCoordinator coordinator;
  final String owner;
  final Directory directory;
  final Completer<void> _release;
  Future<void> _tail = Future.value();
  bool _cancelled = false;
  int scratchBytes = 0;
  bool get cancelled => _cancelled;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_cancelled) {
      return Future.error(const ScanFailure('This scanner session has ended.'));
    }
    final result = _tail.then((_) {
      if (_cancelled) {
        throw const ScanFailure('This scanner session has ended.');
      }
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<ScanReservation> reserve(int bytes, {bool scratch = false}) =>
      coordinator.reserve(directory, bytes, scratch: scratch);
  void cancelNewOperations() => _cancelled = true;
  Future<void> drain() => _tail;
  Future<void> release() async {
    cancelNewOperations();
    await drain();
    try {
      if (await directory.exists() &&
          await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
    } finally {
      if (!_release.isCompleted) {
        _release.complete();
      }
    }
  }
}
