import 'dart:js_interop';

@JS('window')
external _GlacierBrowserInputWindow get _window;

extension type _GlacierBrowserInputWindow(JSObject _) implements JSObject {
  external void addEventListener(
    String type,
    JSFunction listener,
    bool capture,
  );
  external void removeEventListener(
    String type,
    JSFunction listener,
    bool capture,
  );
}

void Function() observeGlacierBrowserPointerDown(
  void Function() onPointerDown,
) {
  final listener = ((JSAny? event) => onPointerDown()).toJS;
  _window.addEventListener('pointerdown', listener, true);
  return () => _window.removeEventListener('pointerdown', listener, true);
}
