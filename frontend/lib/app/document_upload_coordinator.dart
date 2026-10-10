import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/document/datasources/document_upload_acquisition.dart';
import '../data/document/datasources/document_upload_acquisition_factory.dart';
import '../data/document/datasources/document_upload_browser_listener.dart';
import '../data/document/datasources/document_upload_browser_listener_factory.dart';
import '../domain/document/interfaces/document_upload_scheduler.dart';
import '../presentation/document/cubits/document_uploads_cubit.dart';
import 'desktop_upload_bridge.dart';

final class DocumentUploadCoordinator implements DocumentUploadScheduler {
  DocumentUploadCoordinator({
    DocumentUploadAcquisition? acquisition,
    DesktopUploadBridge? desktopBridge,
  }) : acquisition = acquisition ?? createDocumentUploadAcquisition() {
    _desktop =
        desktopBridge ??
        createDesktopUploadBridge(
          canAcquire: () => canAcquire,
          onBusyChanged: _changed,
        );
    _browser = createDocumentUploadBrowserListener(
      currentTarget: () => _browserTarget,
      onVisibilityChanged: (visible) {
        _documentVisible = visible;
        if (_browserReady) _sync();
      },
    );
    _browserReady = true;
  }
  final DocumentUploadAcquisition acquisition;
  late final DesktopUploadBridge _desktop;
  late final DocumentUploadBrowserListener _browser;
  final _changes = StreamController<void>.broadcast(sync: true);
  DocumentUploadsCubit? _target;
  DocumentUploadBrowserTarget? _browserTarget;
  bool _contentBusy = false;
  bool _chooserBusy = false;
  bool _sessionBusy = false;
  bool _documentVisible = true;
  bool _disposed = false;
  bool _browserReady = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _visible =>
      _documentVisible &&
      (_lifecycle == AppLifecycleState.resumed ||
          !_mobile && _lifecycle == AppLifecycleState.inactive);
  bool get canAcquire =>
      !_disposed &&
      !_chooserBusy &&
      !_desktop.portalBusy &&
      (_target?.admissionAllowed ?? false);
  @override
  bool get contentBusy => _contentBusy;
  @override
  Stream<void> get changes => _changes.stream;

  void attach(DocumentUploadsCubit? target, {required bool busy}) {
    if (!identical(_target, target)) {
      _browser.retireTarget();
      _target?.setHover(false);
      _target?.onGateChanged = null;
      _target = target;
      target?.onGateChanged = _sync;
      var browserReserved = 0;
      _browserTarget = target == null
          ? null
          : DocumentUploadBrowserTarget(
              acquisition: acquisition,
              canAdmit: () => identical(_target, target) && canAcquire,
              reserve: (count) {
                final admitted = _reserve(target, count);
                if (admitted) browserReserved = count;
                return admitted;
              },
              onBatch: (selection) {
                final reserved = browserReserved;
                browserReserved = 0;
                _receive(
                  target,
                  target.generation,
                  selection,
                  reserved: reserved,
                );
              },
              rejectionReason: () => target.admissionAllowed && !canAcquire
                  ? 'Finishing the previous file selection.'
                  : null,
              onHover: target.setHover,
              onRejected: target.reject,
            );
    }
    _sessionBusy = busy;
    _sync();
  }

  void lifecycleChanged(AppLifecycleState state) {
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      _browser.clearHover();
      _target?.setHover(false);
    }
    _sync();
  }

  void _sync() {
    final target = _target;
    target?.setGate(busy: _sessionBusy, visible: _visible);
    final enabled = !_disposed && (target?.scopeUsable ?? false);
    _desktop.bind(
      enabled ? target : null,
      enabled ? (event) => _native(target!, event) : null,
    );
    if (!enabled || !_visible) _browser.retireTarget();
  }

  bool _reserve(
    DocumentUploadsCubit target,
    int count, {
    bool chooser = false,
  }) {
    if (!identical(_target, target)) return false;
    if (!chooser && !canAcquire) {
      target.reject('Finishing the previous file selection.');
      return false;
    }
    return target.reserveBatch(count, chooserResult: chooser);
  }

  void _receive(
    DocumentUploadsCubit target,
    int generation,
    DocumentUploadSelection selection, {
    int reserved = 0,
  }) {
    if (!identical(_target, target) ||
        target.generation != generation ||
        !target.scopeUsable) {
      acquisition.release(selection.candidates.map((value) => value.id));
      target.releaseReservation(
        reserved == 0 ? selection.candidates.length : reserved,
      );
      return;
    }
    if (selection.candidates.isNotEmpty) {
      target.receiveBatch(selection.candidates);
    } else {
      target.releaseReservation(reserved);
    }
    if (selection.rejection case final rejection?) target.reject(rejection);
  }

  void choose(DocumentUploadsCubit target) {
    if (!identical(_target, target) || !target.admissionAllowed) return;
    if (!canAcquire) {
      target.reject('Finishing the previous file selection.');
      return;
    }
    _chooserBusy = true;
    final generation = target.generation;
    int reserved = 0;
    Future<DocumentUploadSelection> selection;
    try {
      selection = acquisition.choose(
        reserve: (count) {
          if (!identical(_target, target) ||
              generation != target.generation ||
              !target.scopeUsable) {
            return false;
          }
          final admitted = _reserve(target, count, chooser: true);
          if (admitted) reserved = count;
          return admitted;
        },
      );
    } catch (_) {
      _chooserBusy = false;
      target.releaseReservation(reserved);
      target.reject('No files could be received.');
      _changed();
      return;
    }
    unawaited(
      selection
          .then(
            (value) => _receive(target, generation, value, reserved: reserved),
            onError: (Object _, StackTrace _) {
              target.releaseReservation(reserved);
              if (identical(_target, target) &&
                  generation == target.generation) {
                target.reject('No files could be received.');
              }
            },
          )
          .whenComplete(() {
            _chooserBusy = false;
            _changed();
          }),
    );
  }

  Set<String> receiveSharedPaths(
    DocumentUploadsCubit target,
    List<String> paths,
  ) {
    if (!identical(_target, target) || !canAcquire) return const {};
    final selection = acquisition.captureNativePaths(
      paths,
      reserve: (count) => _reserve(target, count),
    );
    _receive(target, target.generation, selection);
    return selection.candidates.map((candidate) => candidate.id).toSet();
  }

  void _native(DocumentUploadsCubit target, DesktopUploadEvent event) {
    if (!identical(_target, target)) return;
    if (event.hover case final hover?) {
      target.setHover(hover && canAcquire);
    }
    if (event.rejection case final rejection?) {
      target.reject(rejection);
    }
    if (event.paths case final paths?) {
      target.setHover(false);
      if (!event.fromPortal && !target.admissionAllowed) return;
      var reserved = 0;
      final generation = target.generation;
      final selection = acquisition.captureNativePaths(
        paths,
        reserve: (count) {
          final admitted = event.fromPortal
              ? identical(_target, target) &&
                    target.reserveBatch(count, chooserResult: true)
              : _reserve(target, count);
          if (admitted) reserved = count;
          return admitted;
        },
      );
      _receive(target, generation, selection, reserved: reserved);
    }
  }

  @override
  bool start(Future<void> Function() operation) {
    if (_disposed || _contentBusy) return false;
    _contentBusy = true;
    unawaited(
      Future<void>.sync(operation).catchError((Object _) {}).whenComplete(() {
        _contentBusy = false;
        _changed();
      }),
    );
    return true;
  }

  void _changed() {
    if (!_disposed) _changes.add(null);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _target?.retire();
    _target = null;
    _browserTarget = null;
    _browser.dispose();
    unawaited(_desktop.dispose());
    acquisition.dispose();
    unawaited(_changes.close());
  }
}
