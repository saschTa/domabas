@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:domabas/app/document_upload_coordinator.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition_web.dart';
import 'package:domabas/data/document/datasources/document_upload_browser_listener.dart';
import 'package:domabas/data/document/datasources/document_upload_browser_listener_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

@JS('Object.defineProperty')
external JSObject _defineProperty(
  JSObject target,
  JSString name,
  _PropertyDescriptor descriptor,
);

extension type _PropertyDescriptor._(JSObject _) implements JSObject {
  external factory _PropertyDescriptor({
    required JSAny value,
    required bool configurable,
  });
}

extension type _DropItem._(JSObject _) implements JSObject {
  external factory _DropItem({
    required String kind,
    required String type,
    required JSFunction getAsFile,
    required JSFunction webkitGetAsEntry,
  });
}

extension type _DirectoryEntry._(JSObject _) implements JSObject {
  external factory _DirectoryEntry({
    required bool isDirectory,
    required String name,
    required JSFunction createReader,
  });
}

void _ownedProperty(JSObject target, String name, JSAny value) {
  _defineProperty(
    target,
    name.toJS,
    _PropertyDescriptor(value: value, configurable: true),
  );
}

web.File _file(String name, List<int> bytes) => web.File(
  <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
  name,
  web.FilePropertyBag(type: 'application/incorrect'),
);

web.DataTransfer _transfer(List<web.File> files) {
  final transfer = web.DataTransfer();
  _ownedProperty(transfer, 'effectAllowed', 'copy'.toJS);
  for (final file in files) {
    transfer.items.add(file);
  }
  return transfer;
}

web.DragEvent _dispatch(
  String type,
  web.DataTransfer data, {
  int x = 30,
  int y = 30,
}) {
  final event = web.DragEvent(
    type,
    web.DragEventInit(
      bubbles: true,
      cancelable: true,
      dataTransfer: data,
      clientX: x,
      clientY: y,
    ),
  );
  web.document.dispatchEvent(event);
  return event;
}

void main() {
  test('production coordinator initializes synchronous browser visibility and disposes its exact listeners', () {
    final coordinator = DocumentUploadCoordinator();
    final files = _transfer([
      _file('signed-out.pdf', [1]),
    ]);
    expect(_dispatch('drop', files).defaultPrevented, isTrue);
    coordinator.dispose();
    coordinator.dispose();
    expect(_dispatch('drop', files).defaultPrevented, isFalse);
  });

  test('browser capture owns immutable file handles synchronously and reads exact bytes lazily', () async {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    final bytes = List.generate(
      2 * documentUploadReadChunk + 17,
      (index) => index % 251,
    );
    final transfer = _transfer([_file('raw mislabelled.PDF', bytes)]);
    var reservation = 0;
    final selection = source.captureDrop(
      transfer,
      reserve: (count) {
        reservation = count;
        return true;
      },
    );
    transfer.items.clear();
    expect(reservation, 1);
    expect(selection.candidates, hasLength(1));
    final read = await source.read(
      selection.candidates.single.id,
      Completer<void>().future,
    );
    expect(read, bytes);
    source.release(selection.candidates.map((candidate) => candidate.id));
    await expectLater(
      source.read(selection.candidates.single.id, Completer<void>().future),
      throwsA(isA<DocumentUploadReadException>()),
    );
  });

  test('21-file browser drop rejects atomically before reservation or any retained handles', () {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    var reserved = 0;
    final transfer = _transfer(
      List.generate(21, (index) => _file('$index.pdf', [1])),
    );
    final rejected = source.captureDrop(
      transfer,
      reserve: (count) {
        reserved += count;
        return true;
      },
    );
    expect(rejected.candidates, isEmpty);
    expect(rejected.rejection, contains('20'));
    expect(reserved, 0);
    final admitted = source.captureDrop(
      _transfer([
        _file('next.pdf', [2]),
      ]),
      reserve: (_) => true,
    );
    expect(admitted.candidates, hasLength(1));
  });

  test('cancelled browser content drains its owned FileReader before another read starts', () async {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    final selected = source
        .captureDrop(
          _transfer([
            _file('large.pdf', Uint8List(documentUploadByteLimit)),
            _file('next.pdf', [1, 2, 3]),
          ]),
          reserve: (_) => true,
        )
        .candidates;
    final cancel = Completer<void>();
    final pending = source.read(selected.first.id, cancel.future);
    final checked = expectLater(
      pending,
      throwsA(isA<DocumentUploadReadException>()),
    );
    await Future<void>.delayed(Duration.zero);
    cancel.complete();
    await checked;
    expect(await source.read(selected.last.id, Completer<void>().future), [
      1,
      2,
      3,
    ]);
  });

  test('directory entries are classified without traversal even if getAsFile returns bytes', () async {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    final file = _file('folder', [1, 2, 3]);
    final transfer = _transfer([file]);
    var traversals = 0, fileReads = 0;
    final entry = _DirectoryEntry(
      isDirectory: true,
      name: 'folder',
      createReader: (() {
        traversals++;
      }).toJS,
    );
    final item = _DropItem(
      kind: 'file',
      type: file.type,
      getAsFile: (() {
        fileReads++;
        return file;
      }).toJS,
      webkitGetAsEntry: (() => entry).toJS,
    );
    _ownedProperty(transfer, 'items', <JSObject>[item].toJS);
    final selection = source.captureDrop(transfer, reserve: (_) => true);
    await expectLater(
      source.read(selection.candidates.single.id, Completer<void>().future),
      throwsA(
        isA<DocumentUploadReadException>().having(
          (error) => error.message,
          'reason',
          contains('Folders'),
        ),
      ),
    );
    expect(traversals, 0);
    expect(fileReads, 0);
  });

  test('chooser clicks synchronously, counts once, owns the opening result and removes all temporary input state', () async {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    var reserved = 0;
    final pending = source.choose(
      reserve: (count) {
        reserved = count;
        return true;
      },
    );
    final input = web.document.querySelector(
      'input[type="file"][aria-label="Upload PDF, PNG, JPEG or EML files"]',
    ) as web.HTMLInputElement?;
    expect(input, isNotNull);
    expect(input!.multiple, isTrue);
    input.files = _transfer([
      _file('picked.png', [137, 80, 78, 71]),
    ]).files;
    input.dispatchEvent(web.Event('change'));
    input.dispatchEvent(web.Event('cancel'));
    final result = await pending;
    expect(reserved, 1);
    expect(result.cancelled, isFalse);
    expect(result.candidates.single.displayName, 'picked.png');
    expect(input.isConnected, isFalse);
    final cancelled = source.choose(
      reserve: (_) {
        fail('Cancelled chooser must not reserve.');
      },
    );
    final second = web.document.querySelector(
      'input[type="file"][aria-label="Upload PDF, PNG, JPEG or EML files"]',
    ) as web.HTMLInputElement;
    second.dispatchEvent(web.Event('cancel'));
    expect((await cancelled).cancelled, isTrue);
    expect(second.isConnected, isFalse);
  });

  test('current-target browser listeners protect signed-out file navigation and preserve link defaults', () {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    DocumentUploadBrowserTarget? target;
    final batches = <DocumentUploadSelection>[];
    final listener = WebDocumentUploadBrowserListener(
      currentTarget: () => target,
    );
    addTearDown(listener.dispose);
    final file = _transfer([
      _file('file.pdf', [1]),
    ]);
    expect(_dispatch('drop', file).defaultPrevented, isTrue);
    final link = web.DataTransfer()
      ..setData('text/uri-list', 'https://example.test');
    expect(_dispatch('drop', link).defaultPrevented, isFalse);
    target = DocumentUploadBrowserTarget(
      acquisition: source,
      canAdmit: () => true,
      reserve: (_) => true,
      onBatch: batches.add,
      onHover: (_) {},
      onRejected: (_) {},
    );
    _dispatch('drop', file);
    expect(batches, hasLength(1));
    expect(batches.single.candidates, hasLength(1));
    target = null;
    expect(_dispatch('drop', file).defaultPrevented, isTrue);
    expect(batches, hasLength(1));
  });

  test('a move-only file offer is rejected before reservation or content acquisition', () {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    var reserved = 0;
    final rejected = <String>[], batches = <DocumentUploadSelection>[];
    final target = DocumentUploadBrowserTarget(
      acquisition: source,
      canAdmit: () => true,
      reserve: (count) {
        reserved += count;
        return true;
      },
      onBatch: batches.add,
      onHover: (_) {},
      onRejected: rejected.add,
    );
    final listener = WebDocumentUploadBrowserListener(
      currentTarget: () => target,
    );
    addTearDown(listener.dispose);
    final files = _transfer([
      _file('move-only.pdf', [1, 2, 3]),
    ]);
    _ownedProperty(files, 'effectAllowed', 'move'.toJS);
    expect(_dispatch('drop', files).defaultPrevented, isTrue);
    expect(rejected.single, contains('copying'));
    expect(reserved, 0);
    expect(batches, isEmpty);
  });

  test('blur then inactive dragover restores invitation; nested leave does not clear a live outer drag', () {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    final hover = <bool>[];
    final batches = <DocumentUploadSelection>[];
    final target = DocumentUploadBrowserTarget(
      acquisition: source,
      canAdmit: () => true,
      reserve: (_) => true,
      onBatch: batches.add,
      onHover: hover.add,
      onRejected: (_) {},
    );
    final listener = WebDocumentUploadBrowserListener(
      currentTarget: () => target,
    );
    addTearDown(listener.dispose);
    final files = _transfer([
      _file('file.pdf', [1]),
    ]);
    _dispatch('dragenter', files);
    _dispatch('dragenter', files);
    _dispatch('dragleave', files);
    expect(hover.last, isTrue);
    web.window.dispatchEvent(web.Event('blur'));
    expect(hover.last, isFalse);
    _dispatch('dragover', files);
    expect(hover.last, isTrue);
    _dispatch('drop', files);
    expect(batches.single.candidates, hasLength(1));
    expect(hover.last, isFalse);
  });

  test('busy drop reports physical selection drain; retirement resets interrupted internal drag ownership', () {
    final source = WebDocumentUploadAcquisition();
    addTearDown(source.dispose);
    var allowed = false;
    final rejected = <String>[], batches = <DocumentUploadSelection>[];
    final target = DocumentUploadBrowserTarget(
      acquisition: source,
      canAdmit: () => allowed,
      reserve: (_) => true,
      onBatch: batches.add,
      onHover: (_) {},
      onRejected: rejected.add,
      rejectionReason: () => 'Finishing the previous file selection.',
    );
    final listener = WebDocumentUploadBrowserListener(
      currentTarget: () => target,
    );
    addTearDown(listener.dispose);
    final files = _transfer([
      _file('file.pdf', [1]),
    ]);
    _dispatch('drop', files);
    expect(rejected.single, contains('Finishing'));
    allowed = true;
    _dispatch('dragstart', files);
    expect(_dispatch('drop', files).defaultPrevented, isFalse);
    expect(batches, isEmpty);
    _dispatch('dragstart', files);
    listener.retireTarget();
    expect(_dispatch('drop', files).defaultPrevented, isTrue);
    expect(batches, hasLength(1));
  });
}
