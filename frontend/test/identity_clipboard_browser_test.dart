@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:domabas/data/identity/datasources/identity_clipboard_data_source_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

@JS('Object.defineProperty')
external void _defineProperty(
  JSObject target,
  JSString name,
  JSObject descriptor,
);

@JS('Reflect.deleteProperty')
external void _deleteProperty(JSObject target, JSString name);

void main() {
  for (final outcome in ['copied', 'denied', 'error']) {
    test(
      'HTTP clipboard $outcome restores focus and removes the code',
      () async {
        final focus = web.HTMLButtonElement();
        web.document.body!.appendChild(focus);
        focus.focus();
        final textareas = web.document.querySelectorAll('textarea').length;
        _defineProperty(
          web.window,
          'isSecureContext'.toJS,
          {'value': false, 'configurable': true}.jsify()! as JSObject,
        );
        var attempts = 0;
        _defineProperty(
          web.document,
          'execCommand'.toJS,
          {
                'value': ((JSString command) {
                  attempts++;
                  expect(command.toDart, 'copy');
                  final input =
                      web.document.activeElement as web.HTMLTextAreaElement;
                  expect(input.value, 'one-time-invitation');
                  expect(input.selectionStart, 0);
                  expect(input.selectionEnd, input.value.length);
                  if (outcome == 'error') throw StateError('Clipboard denied');
                  return outcome == 'copied';
                }).toJS,
                'configurable': true,
              }.jsify()!
              as JSObject,
        );
        addTearDown(() {
          _deleteProperty(web.window, 'isSecureContext'.toJS);
          _deleteProperty(web.document, 'execCommand'.toJS);
          focus.remove();
        });

        expect(
          await IdentityClipboardDataSource().copy('one-time-invitation'),
          outcome == 'copied',
        );
        expect(attempts, 1);
        expect(web.document.activeElement, focus);
        expect(web.document.querySelectorAll('textarea').length, textareas);
      },
    );
  }
}
