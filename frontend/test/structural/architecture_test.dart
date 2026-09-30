import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _root = Directory('lib').absolute.uri;
final _directives = RegExp(
  r'''^\s*(?:import|export)\s+[^;]+;''',
  multiLine: true,
);
final _strings = RegExp(r'''['"]([^'"]+)['"]''');

Iterable<File> _sources(String directory) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

Iterable<String> _targets(String source) sync* {
  for (final directive in _directives.allMatches(source)) {
    for (final target in _strings.allMatches(directive.group(0)!)) {
      yield target.group(1)!;
    }
  }
}

Uri _resolve(Uri source, String target) => target.startsWith('package:domabas/')
    ? _root.resolve(target.substring('package:domabas/'.length))
    : source.resolve(target);

({String layer, String owner, String role})? _location(Uri uri) {
  if (!uri.path.startsWith(_root.path)) return null;
  final segments = uri.path.substring(_root.path.length).split('/');
  if (segments.length < 3 ||
      !const {'domain', 'data', 'presentation'}.contains(segments.first)) {
    return null;
  }
  return (layer: segments[0], owner: segments[1], role: segments[2]);
}

bool _allowed(Uri source, String target) {
  final from = _location(source)!;
  final resolved = _resolve(source, target);
  final to = _location(resolved);
  final app = resolved.path.startsWith(_root.resolve('app/').path);
  final ui = resolved.path.startsWith(_root.resolve('ui/').path);
  final generated =
      target.startsWith('package:domabas_api') ||
      resolved.path.contains('/packages/domabas_api/');
  if (app || generated && from.layer != 'data') return false;
  if (from.layer == 'domain') {
    if (to == null) {
      return const {
        'dart:async',
        'dart:collection',
        'dart:convert',
        'dart:math',
        'dart:typed_data',
      }.contains(target);
    }
    if (to.layer != 'domain') return false;
    if (from.owner != to.owner && to.role != 'models') return false;
    if (from.role == 'models' && to.role != 'models') return false;
    if (from.role == 'interfaces' && to.role == 'services') return false;
  }
  if (from.layer == 'presentation') {
    if (to?.layer == 'data' ||
        target == 'dart:io' ||
        target.startsWith('package:http')) {
      return false;
    }
    if (to?.layer == 'presentation' && from.owner != to?.owner) return false;
  }
  if (from.layer == 'data') {
    if (to?.layer == 'presentation' ||
        ui ||
        target.startsWith('package:pdfrx') ||
        target.startsWith('package:bloc') ||
        target.startsWith('package:flutter_bloc') ||
        target == 'package:flutter/material.dart' ||
        target == 'package:flutter/widgets.dart') {
      return false;
    }
    if (to?.layer == 'data' && from.owner != to?.owner) {
      return const {'repos', 'datasources'}.contains(from.role) &&
          to?.role == 'models';
    }
  }
  return true;
}

void main() {
  test('handwritten types identify their owner and purpose', () {
    final ambiguousType = RegExp(
      r'\b(?:class|enum|typedef)\s+(?:Service|DataSource|Repository|Handler|'
      r'Container|Source|Mapper|Permission|Claim|Credentials|ImportState|'
      r'ProcessingRepository|ProcessingRemoteDataSource|RemoteProcessingRepository|'
      r'ProcessingState|ProcessingCubit|ProcessingConfiguration|ProcessingJob|'
      r'PipelineConfiguration|ProcessingPipeline|ReindexBatch|ReindexRequest|'
      r'ActivityRepository|ActivityRemoteDataSource|RemoteActivityRepository|'
      r'WebSocketRemoteDataSource|SocketAttempt|SocketAttemptFactory|'
      r'SocketAttemptCancelled|_Section|_Party|_Fields|_DetailRecord|_FrameParser|'
      r'_ReadControl|_ProbeClient|_WriteIntent)\b',
    );
    for (final file in _sources('lib')) {
      expect(
        ambiguousType.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} must name its types explicitly',
      );
      expect(
        const {
          'service.dart',
          'data_source.dart',
          'repository.dart',
          'mapper.dart',
          'mapping.dart',
          'import_state.dart',
          'processing.dart',
          'processing_repository.dart',
          'processing_remote_data_source.dart',
          'remote_processing_repository.dart',
          'socket_attempt.dart',
          'websocket_remote_data_source.dart',
        }.contains(file.uri.pathSegments.last),
        isFalse,
        reason: '${file.path} must name its implementation explicitly',
      );
    }
    expect(ambiguousType.hasMatch('final class ProcessingJob {}'), isTrue);
    expect(
      ambiguousType.hasMatch('final class DocumentProcessingJob {}'),
      isFalse,
    );
    expect(ambiguousType.hasMatch('final class Invoice {}'), isFalse);
  });

  test('boundary conversion helpers use explicit mapper names', () {
    final ambiguousMapper = RegExp(r'\b(?:_toDomain|_fromNative)\s*\(');
    for (final file in _sources('lib/data')) {
      expect(
        ambiguousMapper.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} must identify boundary conversion helpers',
      );
    }
  });

  test('shared scheduling has no application or framework dependencies', () {
    for (final file in _sources('lib/scheduling')) {
      expect(_targets(file.readAsStringSync()), everyElement('dart:async'));
    }
  });
  test('shared UI presenters depend only on Flutter and other presenters', () {
    final root = _root.resolve('ui/');
    final files = _sources('lib/ui');
    expect(files, isNotEmpty);
    for (final file in files) {
      for (final target in _targets(file.readAsStringSync())) {
        final resolved = _resolve(file.absolute.uri, target);
        expect(
          target.startsWith('package:flutter/') ||
              resolved.path.startsWith(root.path),
          isTrue,
          reason: '${file.path} must not depend on $target',
        );
      }
    }
  });

  test('every domain uses the domain, data and presentation boundaries', () {
    expect(Directory('lib/features').existsSync(), isFalse);
    for (final owner in [
      'invoice',
      'document',
      'identity',
      'email',
      'realtime',
      'appearance',
      'scanner',
      'server',
    ]) {
      for (final layer in ['domain', 'data', 'presentation']) {
        final files = _sources('lib/$layer/$owner').toList();
        expect(files, isNotEmpty, reason: '$layer/$owner must be exercised');
        for (final file in files) {
          for (final target in _targets(file.readAsStringSync())) {
            expect(
              _allowed(file.absolute.uri, target),
              isTrue,
              reason: '${file.path} must not depend on $target',
            );
          }
        }
      }
    }
  });

  test('all application state owners use Cubits without notifier bridges', () {
    for (final file in _sources('lib')) {
      expect(
        file.readAsStringSync(),
        isNot(contains('extends ChangeNotifier')),
        reason: file.path,
      );
    }
    for (final owner in [
      'invoice',
      'document',
      'identity',
      'email',
      'realtime',
      'appearance',
      'scanner',
      'server',
    ]) {
      expect(
        _sources('lib/presentation/$owner/cubits').where(
          (file) => RegExp(r'extends Cubit<').hasMatch(file.readAsStringSync()),
        ),
        isNotEmpty,
      );
    }
  });

  test(
    'boundary policy rejects package, relative and conditional bypasses',
    () {
      final model = _root.resolve('domain/document/models/document.dart');
      final presentation = _root.resolve(
        'presentation/document/views/document.dart',
      );
      final source = _root.resolve('data/document/datasources/document.dart');
      expect(_allowed(model, 'package:bloc/bloc.dart'), isFalse);
      expect(
        _allowed(model, 'package:domabas/data/document/models/record.dart'),
        isFalse,
      );
      expect(_allowed(model, '../interfaces/repository.dart'), isFalse);
      expect(_allowed(presentation, 'package:domabas_api/api.dart'), isFalse);
      expect(
        _allowed(presentation, '../../../data/document/repos/repository.dart'),
        isFalse,
      );
      expect(
        _allowed(presentation, '../../identity/cubits/session_cubit.dart'),
        isFalse,
      );
      expect(_allowed(source, '../../identity/repos/repository.dart'), isFalse);
      expect(_allowed(source, '../../identity/models/record.dart'), isTrue);
      expect(_allowed(source, 'package:pdfrx/pdfrx.dart'), isFalse);
      expect(
        _targets(
          "import 'native.dart' if (dart.library.js_interop) 'browser.dart';",
        ),
        ['native.dart', 'browser.dart'],
      );
    },
  );
}
