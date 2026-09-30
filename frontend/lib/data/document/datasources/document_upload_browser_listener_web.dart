import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'document_upload_acquisition_web.dart';
import 'document_upload_browser_listener.dart';

DocumentUploadBrowserListener createDocumentUploadBrowserListener({
  required DocumentUploadBrowserTarget? Function() currentTarget,
  void Function(bool)? onVisibilityChanged,
}) => WebDocumentUploadBrowserListener(
  currentTarget: currentTarget,
  onVisibilityChanged: onVisibilityChanged,
);

final class WebDocumentUploadBrowserListener
    implements DocumentUploadBrowserListener {
  WebDocumentUploadBrowserListener({
    required this.currentTarget,
    this.onVisibilityChanged,
  }) {
    _listen(web.document, 'dragenter', _enter);
    _listen(web.document, 'dragover', _over);
    _listen(web.document, 'dragleave', _leave);
    _listen(web.document, 'drop', _drop);
    _listen(web.document, 'dragstart', (_) {
      _internalDrag = true;
      clearHover();
    });
    _listen(web.document, 'dragend', (_) {
      _internalDrag = false;
      clearHover();
    });
    _listen(web.window, 'blur', (_) => retireTarget());
    _listen(web.document, 'visibilitychange', (_) {
      final visible = !web.document.hidden;
      if (!visible) retireTarget();
      onVisibilityChanged?.call(visible);
    });
    onVisibilityChanged?.call(!web.document.hidden);
  }
  final DocumentUploadBrowserTarget? Function() currentTarget;
  final void Function(bool)? onVisibilityChanged;
  final _listeners =
      <({web.EventTarget target, String type, JSFunction listener})>[];
  DocumentUploadBrowserTarget? _hoverTarget;
  int _depth = 0;
  bool _internalDrag = false, _disposed = false;

  void _listen(
    web.EventTarget target,
    String type,
    void Function(web.Event) callback,
  ) {
    final listener = callback.toJS;
    target.addEventListener(type, listener, true.toJS);
    _listeners.add((target: target, type: type, listener: listener));
  }

  bool _files(web.DragEvent event) {
    final transfer = event.dataTransfer;
    if (transfer == null || _internalDrag) return false;
    for (var index = 0; index < transfer.items.length; index++) {
      if (transfer.items[index].kind == 'file') return true;
    }
    return transfer.types.toDart.any((type) => type.toDart == 'Files');
  }

  DocumentUploadBrowserTarget? _target() {
    if (_disposed || web.document.hidden) return null;
    final target = currentTarget();
    return target != null && target.canAdmit() ? target : null;
  }

  bool _copy(web.DataTransfer transfer) => const {
    'all',
    'uninitialized',
    'copy',
    'copyLink',
    'copyMove',
  }.contains(transfer.effectAllowed);

  void _invite(web.DragEvent event) {
    event.preventDefault();
    final transfer = event.dataTransfer!;
    final target = _copy(transfer) ? _target() : null;
    transfer.dropEffect = target == null ? 'none' : 'copy';
    if (!identical(_hoverTarget, target)) {
      _hoverTarget?.onHover(false);
      _hoverTarget = target;
    }
    target?.onHover(true);
  }

  void _enter(web.Event raw) {
    final event = raw as web.DragEvent;
    if (!_files(event)) return;
    _depth++;
    _invite(event);
  }

  void _over(web.Event raw) {
    final event = raw as web.DragEvent;
    if (!_files(event)) return;
    if (_depth == 0) _depth = 1;
    _invite(event);
  }

  void _leave(web.Event raw) {
    final event = raw as web.DragEvent;
    if (!_files(event)) return;
    event.preventDefault();
    _depth--;
    if (_depth <= 0 ||
        event.relatedTarget == null &&
            (event.clientX <= 0 ||
                event.clientY <= 0 ||
                event.clientX >= web.window.innerWidth ||
                event.clientY >= web.window.innerHeight)) {
      clearHover();
    }
  }

  void _drop(web.Event raw) {
    final event = raw as web.DragEvent;
    if (!_files(event)) {
      _internalDrag = false;
      return;
    }
    event.preventDefault();
    final target = _target();
    final transfer = event.dataTransfer!;
    clearHover();
    _internalDrag = false;
    if (target == null) {
      if (!web.document.hidden && !_disposed) {
        final current = currentTarget();
        final reason = current?.rejectionReason?.call();
        if (reason != null) current!.onRejected(reason);
      }
      return;
    }
    if (!_copy(transfer)) {
      target.onRejected('Only files offered for copying can be uploaded.');
      return;
    }
    final source = target.acquisition;
    if (source is! WebDocumentUploadAcquisition) {
      target.onRejected('No files could be received.');
      return;
    }
    final selection = source.captureDrop(transfer, reserve: target.reserve);
    target.onBatch(selection);
  }

  @override
  void clearHover() {
    _depth = 0;
    _hoverTarget?.onHover(false);
    _hoverTarget = null;
  }

  @override
  void retireTarget() {
    _internalDrag = false;
    clearHover();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clearHover();
    for (final entry in _listeners) {
      entry.target.removeEventListener(entry.type, entry.listener, true.toJS);
    }
    _listeners.clear();
  }
}
