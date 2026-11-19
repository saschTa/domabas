import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/services.dart';

import '../../ui/glacier/glacier_native_values.dart';
import 'desktop_window_port.dart';

class DesktopWindowStatus {
  const DesktopWindowStatus({this.snapshot, this.error, this.failed = false});
  final DesktopWindowSnapshot? snapshot;
  final String? error;
  final bool failed;
}

class DesktopWindowController extends Cubit<DesktopWindowStatus> {
  DesktopWindowController(this._port) : super(const DesktopWindowStatus());
  DesktopWindowController.macos(this._port)
    : _snapshot = DesktopWindowSnapshot(
        revision: -1,
        ready: false,
        state: GlacierNativeWindowState(
          platform: GlacierNativePlatform.macos,
          supportedCommands: const {},
        ),
      ),
      super(const DesktopWindowStatus());
  final DesktopWindowPort _port;
  StreamSubscription<DesktopWindowSnapshot>? _subscription;
  DesktopWindowSnapshot? _snapshot;
  DesktopWindowSnapshot? get snapshot => _snapshot;
  String? error;
  bool _disposed = false, _failed = false, _enabling = false;
  int _sequence = 0;
  int _layoutRevision = 0, _pendingLayouts = 0;
  Timer? _layoutRetry;
  Timer? _initializationRetry;
  int get layoutRevision => _layoutRevision;
  Future<void> _pending = Future.value();
  bool get available => !_failed && _snapshot?.ready == true;
  bool get _macos => _snapshot?.state.platform == GlacierNativePlatform.macos;
  bool get frameVisible =>
      _macos ||
      available ||
      (_failed &&
          _snapshot != null &&
          (_snapshot!.state.fullscreen ||
              _snapshot!.state.decoration == GlacierNativeDecoration.client));
  bool get recovering => _failed && frameVisible;
  bool _restoring = false;
  void _publish() => emit(
    DesktopWindowStatus(snapshot: _snapshot, error: error, failed: _failed),
  );
  Future<void> initialize() async {
    _subscription ??= _port.changes.listen(
      _accept,
      onError: (Object _) => _recover(),
    );
    for (var attempt = 0; attempt < 10 && !_disposed; attempt++) {
      try {
        _accept(await _port.initialize().timeout(const Duration(seconds: 3)));
        return;
      } on MissingPluginException {
        if (attempt < 9) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } catch (_) {
        break;
      }
    }
    await _recover();
  }

  void _accept(DesktopWindowSnapshot value) {
    if (_disposed || value.revision < (_snapshot?.revision ?? -1)) return;
    _snapshot = value;
    if (_macos && value.ready) {
      _initializationRetry?.cancel();
      error = null;
    }
    _pendingLayouts = 0;
    _layoutRevision++;
    _publish();
    if (!value.ready && !_failed) unawaited(_recover());
  }

  Future<void> _recover() async {
    if (_disposed || _failed) return;
    if (_macos) {
      if (!available && _initializationRetry?.isActive != true) {
        _initializationRetry = Timer(const Duration(seconds: 1), initialize);
      }
      error = 'Window controls could not reach macOS.';
      _publish();
      return;
    }
    _failed = true;
    _layoutRetry?.cancel();
    error = 'Restoring system window controls…';
    _publish();
    await _restoreHost();
  }

  Future<void> _restoreHost() async {
    if (_disposed || _restoring) return;
    _restoring = true;
    try {
      final snapshot = await _port
          .setClientDecoration(false)
          .timeout(const Duration(seconds: 3));
      _accept(snapshot);
    } catch (_) {
      if (!_disposed) {
        error = 'System controls could not be restored. Try Exit full screen again or close the window.';
        _publish();
      }
    } finally {
      _restoring = false;
    }
  }

  void layoutChanged(GlacierNativeWindowLayout layout) {
    if (!available || _disposed || layout.viewport.isEmpty) return;
    _layoutRetry?.cancel();
    final sequence = ++_sequence;
    _pending = _pending.then((_) async {
      if (_disposed || !available || sequence != _sequence) return;
      try {
        await _port
            .setLayout(sequence, layout)
            .timeout(const Duration(seconds: 3));
        if (_disposed || sequence != _sequence || !available) return;
        if (!_macos &&
            _snapshot!.state.decoration == GlacierNativeDecoration.host &&
            !_enabling) {
          _enabling = true;
          _accept(
            await _port
                .setClientDecoration(true)
                .timeout(const Duration(seconds: 3)),
          );
        }
        _pendingLayouts = 0;
      } on PlatformException catch (error) {
        if (_disposed || sequence != _sequence || !available) return;
        final geometryChanged =
            error.code == 'layout_pending' ||
            _enabling && error.code == 'not_ready';
        if (!geometryChanged && !_macos) {
          await _recover();
        } else {
          _retryLayout(sequence);
        }
      } catch (_) {
        if (_macos) {
          _retryLayout(sequence);
        } else {
          await _recover();
        }
      } finally {
        _enabling = false;
      }
    });
  }

  void _retryLayout(int sequence) {
    if (_disposed ||
        !available ||
        sequence != _sequence ||
        ++_pendingLayouts > 20) {
      return;
    }
    _layoutRetry = Timer(const Duration(milliseconds: 50), () {
      if (_disposed || !available || sequence != _sequence) return;
      _layoutRevision++;
      _publish();
    });
  }

  void request(GlacierNativeCommand command) {
    if (_disposed ||
        _snapshot == null ||
        !_snapshot!.state.supportedCommands.contains(command)) {
      return;
    }
    if (_failed) {
      if (!frameVisible) return;
      if (command == GlacierNativeCommand.exitFullscreen) {
        unawaited(_restoreHost());
      } else if (command == GlacierNativeCommand.close) {
        unawaited(_closeDuringRecovery());
      }
      return;
    }
    if (!available) return;
    Future<void> send() async {
      if (_disposed || !available) return;
      try {
        await _port.request(command).timeout(const Duration(seconds: 3));
        if (_macos && !_disposed && error != null) {
          error = null;
          _publish();
        }
      } catch (_) {
        await _recover();
      }
    }

    if (_macos) {
      unawaited(send());
    } else {
      _pending = _pending.then((_) => send());
    }
  }

  Future<void> _closeDuringRecovery() async {
    try {
      await _port
          .request(GlacierNativeCommand.close)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      if (!_disposed) {
        error = 'The window could not close. Use the operating system to quit Domabas.';
        _publish();
      }
    }
  }

  @override
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _layoutRetry?.cancel();
    _initializationRetry?.cancel();
    await _subscription?.cancel();
    await _port.dispose();
    return super.close();
  }
}
