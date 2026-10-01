import 'dart:js_interop';

import 'package:web/web.dart' as web;

final class IdentityClipboardDataSource {
  Future<bool> copy(String text) async {
    if (web.window.isSecureContext) {
      try {
        await web.window.navigator.clipboard.writeText(text).toDart;
        return true;
      } catch (_) {
        return false;
      }
    }
    final body = web.document.body;
    if (body == null) return false;
    final previousFocus = web.document.activeElement;
    final input = web.HTMLTextAreaElement()
      ..value = text
      ..readOnly = true;
    input.style
      ..position = 'fixed'
      ..left = '-9999px'
      ..top = '0';
    try {
      body.appendChild(input);
      input.select();
      return web.document.execCommand('copy');
    } catch (_) {
      return false;
    } finally {
      input.remove();
      if (previousFocus != null && previousFocus.isA<web.HTMLElement>()) {
        (previousFocus as web.HTMLElement).focus();
      }
    }
  }
}
