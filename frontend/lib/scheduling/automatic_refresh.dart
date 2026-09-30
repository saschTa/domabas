import 'dart:async';

final class AutomaticRefresh {
  AutomaticRefresh({
    required this.read,
    required this.busy,
    Duration Function()? interval,
    this.coalesce = const Duration(milliseconds: 250),
  }) : interval = interval ?? (() => const Duration(seconds: 1));

  final Future<void> Function() read;
  final bool Function() busy;
  final Duration Function() interval;
  final Duration coalesce;
  final _clock = Stopwatch()..start();
  Timer? _timer;
  Duration? _last;
  bool _active = false, _dirty = false, _reading = false, _closed = false;

  void setActive(bool value) {
    if (_closed) return;
    _active = value;
    if (!value) {
      _timer?.cancel();
      _timer = null;
    } else {
      _schedule();
    }
  }

  void invalidate() {
    if (_closed) return;
    _dirty = true;
    _schedule();
  }

  void _schedule() {
    if (_closed || !_active || !_dirty || _reading || _timer != null) return;
    final remaining = _last == null
        ? Duration.zero
        : interval() - (_clock.elapsed - _last!);
    _timer = Timer(remaining > coalesce ? remaining : coalesce, () {
      _timer = null;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_closed || !_active || !_dirty || _reading) return;
    if (busy()) {
      _schedule();
      return;
    }
    _dirty = false;
    _reading = true;
    try {
      await read();
    } finally {
      _reading = false;
      _last = _clock.elapsed;
      _schedule();
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _clock.stop();
  }
}
