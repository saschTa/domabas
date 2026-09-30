import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

final class DesktopDropEvent {
  const DesktopDropEvent(
    this.kind, {
    this.paths = const [],
    this.message,
    this.fromPortal = false,
  });
  final DesktopDropEventKind kind;
  final List<String> paths;
  final String? message;
  final bool fromPortal;
}

enum DesktopDropEventKind { entered, updated, exited, files, rejected }

typedef DesktopDropListener = void Function(DesktopDropEvent);

abstract interface class DesktopPortalLookup {
  Future<List<String>> retrieve(String key);
  Future<void> close();
}

final class DBusDesktopPortalLookup implements DesktopPortalLookup {
  final DBusClient _client = DBusClient.session();
  @override
  Future<List<String>> retrieve(String key) async {
    final result = await _client.callMethod(
      destination: 'org.freedesktop.portal.Documents',
      path: DBusObjectPath('/org/freedesktop/portal/documents'),
      interface: 'org.freedesktop.portal.FileTransfer',
      name: 'RetrieveFiles',
      values: [DBusString(key), DBusDict.stringVariant({})],
    );
    if (result.values.length != 1 || result.values.first is! DBusArray) {
      throw const FormatException('Invalid portal response');
    }
    final values = (result.values.first as DBusArray).children;
    if (values.length > 20) throw const DesktopDropCapacityException();
    return values.map((value) => value.asString()).toList(growable: false);
  }

  @override
  Future<void> close() => _client.close();
}

final class DesktopDropCapacityException implements Exception {
  const DesktopDropCapacityException();
}

final class DesktopDropRegistration {
  DesktopDropRegistration._(this._owner, this._listener);
  final DesktopDropController _owner;
  final DesktopDropListener _listener;
  bool _active = true;
  void dispose() {
    if (!_active) return;
    _active = false;
    _owner._listeners.remove(this);
  }
}

final class DesktopDropController {
  DesktopDropController({
    this._channel = const MethodChannel('desktop_drop'),
    DesktopPortalLookup Function()? portalFactory,
    this.portalDeadline = const Duration(seconds: 10),
    this.onPortalBusyChanged,
    this.canStartPortal,
  }) : _portalFactory = portalFactory ?? DBusDesktopPortalLookup.new {
    _channel.setMethodCallHandler(handleMethodCall);
  }

  final MethodChannel _channel;
  final DesktopPortalLookup Function() _portalFactory;
  final Duration portalDeadline;
  final void Function(bool)? onPortalBusyChanged;
  final bool Function()? canStartPortal;
  final _listeners = <DesktopDropRegistration>{};
  bool _disposed = false;
  bool _portalBusy = false;
  Future<void>? _portalDrain;
  bool get portalBusy => _portalBusy;

  DesktopDropRegistration listen(DesktopDropListener listener) {
    if (_disposed) throw StateError('Drop controller is disposed');
    final registration = DesktopDropRegistration._(this, listener);
    _listeners.add(registration);
    return registration;
  }

  void _deliver(
    List<DesktopDropRegistration> captured,
    DesktopDropEvent event,
  ) {
    if (_disposed) return;
    for (final registration in captured) {
      if (registration._active) registration._listener(event);
    }
  }

  Future<void> handleMethodCall(MethodCall call) async {
    if (_disposed) return;
    final captured = _listeners.toList(growable: false);
    switch (call.method) {
      case 'entered':
      case 'updated':
      case 'exited':
        _deliver(
          captured,
          DesktopDropEvent(switch (call.method) {
            'entered' => DesktopDropEventKind.entered,
            'updated' => DesktopDropEventKind.updated,
            _ => DesktopDropEventKind.exited,
          }),
        );
      case 'rejected':
        _deliver(
          captured,
          DesktopDropEvent(
            DesktopDropEventKind.rejected,
            message: call.arguments is String ? call.arguments as String : null,
          ),
        );
      case 'performOperation':
        final values = call.arguments;
        if (values is! List || values.length > 20) {
          _reject(
            captured,
            'Choose up to 20 files. None of this batch were uploaded.',
          );
          return;
        }
        final paths = values
            .map((value) => value is String ? value : '')
            .toList(growable: false);
        _deliver(
          captured,
          DesktopDropEvent(DesktopDropEventKind.files, paths: paths),
        );
      case 'performOperation_linux':
        final values = call.arguments;
        final raw = values is List && values.isNotEmpty ? values.first : null;
        if (raw is! String || raw.length > 20 * 32768) {
          _reject(captured, 'No files could be received.');
          return;
        }
        final paths = <String>[];
        for (final line in const LineSplitter().convert(raw)) {
          if (line.isEmpty || line.startsWith('#')) continue;
          if (paths.length == 20) {
            _reject(
              captured,
              'Choose up to 20 files. None of this batch were uploaded.',
            );
            return;
          }
          final uri = Uri.tryParse(line);
          String path = line;
          if (uri?.scheme == 'file') {
            try {
              path = uri!.toFilePath();
            } catch (_) {
              path = '';
            }
          }
          paths.add(path);
        }
        _deliver(
          captured,
          DesktopDropEvent(DesktopDropEventKind.files, paths: paths),
        );
      case 'performOperation_portal':
        if (captured.isEmpty) return;
        if (_portalBusy || !(canStartPortal?.call() ?? true)) {
          _reject(captured, 'Finishing the previous file selection.');
          return;
        }
        final values = call.arguments;
        final key = values is List && values.isNotEmpty ? values.first : null;
        if (key is! String || key.isEmpty || key.length > 4096) {
          _reject(captured, 'No files could be received.');
          return;
        }
        _portalBusy = true;
        onPortalBusyChanged?.call(true);
        _portalDrain = _resolvePortal(key, captured);
        unawaited(_portalDrain);
    }
  }

  void _reject(List<DesktopDropRegistration> captured, String message) =>
      _deliver(
        captured,
        DesktopDropEvent(DesktopDropEventKind.rejected, message: message),
      );

  Future<void> _resolvePortal(
    String key,
    List<DesktopDropRegistration> captured,
  ) async {
    DesktopPortalLookup? lookup;
    Future<void>? closing;
    Future<void> closeLookup() => closing ??= Future<void>.sync(() async {
      await lookup?.close();
    });
    bool expired = false;
    Timer? deadline;
    DesktopDropEvent? completed;
    try {
      lookup = _portalFactory();
      deadline = Timer(portalDeadline, () {
        expired = true;
        _reject(
          captured,
          'No files could be received. The file selection timed out.',
        );
        unawaited(closeLookup().catchError((Object _) {}));
      });
      final paths = await lookup.retrieve(key);
      if (!expired) {
        completed = paths.length > 20
            ? const DesktopDropEvent(
                DesktopDropEventKind.rejected,
                message:
                    'Choose up to 20 files. None of this batch were uploaded.',
              )
            : DesktopDropEvent(
                DesktopDropEventKind.files,
                paths: paths,
                fromPortal: true,
              );
      }
    } on DesktopDropCapacityException {
      if (!expired) {
        completed = const DesktopDropEvent(
          DesktopDropEventKind.rejected,
          message: 'Choose up to 20 files. None of this batch were uploaded.',
        );
      }
    } catch (_) {
      if (!expired) {
        completed = const DesktopDropEvent(
          DesktopDropEventKind.rejected,
          message: 'No files could be received.',
        );
      }
    } finally {
      try {
        await closeLookup();
      } catch (_) {}
      deadline?.cancel();
      _portalBusy = false;
      onPortalBusyChanged?.call(false);
      if (!expired && completed != null) _deliver(captured, completed);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final listener in _listeners.toList()) {
      listener.dispose();
    }
    _channel.setMethodCallHandler(null);
    await _portalDrain;
  }
}
