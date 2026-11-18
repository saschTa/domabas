import 'dart:async';

import 'package:flutter/services.dart';

import '../../ui/glacier/glacier_native_values.dart';
import 'desktop_window_port.dart';

class DesktopWindowChannel implements DesktopWindowPort {
  DesktopWindowChannel({BinaryMessenger? messenger})
    : _channel = MethodChannel(
        'dev.domabas/desktop_window',
        const StandardMethodCodec(),
        messenger,
      ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'windowChanged' && !_disposed) {
        try {
          _changes.add(_snapshot(call.arguments));
        } catch (error, stack) {
          _changes.addError(error, stack);
        }
      }
    });
  }
  final MethodChannel _channel;
  final _changes = StreamController<DesktopWindowSnapshot>.broadcast();
  bool _disposed = false;
  @override
  Stream<DesktopWindowSnapshot> get changes => _changes.stream;
  DesktopWindowSnapshot _snapshot(Object? value) {
    if (value is! Map || value['protocolVersion'] != 1) {
      throw const FormatException('Unsupported desktop window protocol');
    }
    final platform = GlacierNativePlatform.values.byName(
      value['platform'] as String,
    );
    final commands = (value['commands'] as List)
        .cast<String>()
        .map((name) => GlacierNativeCommand.values.byName(name))
        .toSet();
    return DesktopWindowSnapshot(
      revision: value['revision'] as int,
      ready: value['ready'] == true,
      state: GlacierNativeWindowState(
        platform: platform,
        mode: GlacierNativeWindowMode.values.byName(value['mode'] as String),
        active: value['active'] == true,
        decoration: value['clientDecoration'] == true
            ? GlacierNativeDecoration.client
            : GlacierNativeDecoration.host,
        controlLayout: GlacierNativeControlLayout.values.byName(
          value['controlLayout'] as String? ?? 'standard',
        ),
        supportedCommands: commands,
        devicePixelRatio: (value['devicePixelRatio'] as num).toDouble(),
      ),
    );
  }

  @override
  Future<DesktopWindowSnapshot> initialize() async => _snapshot(
    await _channel.invokeMethod<Object?>('initialize', {'protocolVersion': 1}),
  );
  @override
  Future<DesktopWindowSnapshot> setClientDecoration(bool enabled) async =>
      _snapshot(
        await _channel.invokeMethod<Object?>('setClientDecoration', {
          'enabled': enabled,
        }),
      );
  @override
  Future<void> setLayout(int sequence, GlacierNativeWindowLayout layout) async {
    List<double> rect(Rect r) => [r.left, r.top, r.width, r.height];
    await _channel.invokeMethod<void>('setLayoutRegions', {
      'sequence': sequence,
      'viewport': [layout.viewport.width, layout.viewport.height],
      'devicePixelRatio': layout.devicePixelRatio,
      'resizeEdge': layout.resizeEdge,
      'dragRegions': layout.candidateDragRegions.map(rect).toList(),
      'exclusions': layout.interactiveExclusions.map(rect).toList(),
      'captions': layout.captionBounds.map(
        (key, value) => MapEntry(key.name, rect(value)),
      ),
    });
  }

  @override
  Future<void> request(GlacierNativeCommand command) =>
      _channel.invokeMethod<void>('request', {'command': command.name});
  @override
  Future<void> dispose() async {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _changes.close();
  }
}
