import 'package:domabas/app/desktop_upload_bridge.dart';
import 'package:domabas/app/document_upload_coordinator.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition_native.dart';
import 'package:domabas/domain/document/interfaces/document_upload_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/presentation/document/cubits/document_uploads_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Bridge implements DesktopUploadBridge {
  Object? owner;
  void Function(DesktopUploadEvent)? listener;
  @override
  bool get portalBusy => false;
  @override
  void bind(Object? owner, void Function(DesktopUploadEvent)? listener) {
    this.owner = owner;
    this.listener = listener;
  }

  @override
  Future<void> dispose() async {}
}

final class _Repository implements DocumentUploadRepository {
  int calls = 0;
  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) async {
    calls++;
    return const DocumentUploadResult(
      outcome: DocumentUploadOutcome.rejected,
      message: 'Test complete',
    );
  }

  @override
  void release(Iterable<String> ids) {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('started portal retains its registration while hidden; direct hidden drops cannot use its continuation', () async {
    final bridge = _Bridge();
    final coordinator = DocumentUploadCoordinator(
      acquisition: NativeDocumentUploadAcquisition(),
      desktopBridge: bridge,
    );
    final repository = _Repository();
    final cubit = DocumentUploadsCubit(
      repository: repository,
      scheduler: coordinator,
      libraryName: 'Library',
      canRead: true,
      allowed: true,
    );
    coordinator.attach(cubit, busy: false);
    final owner = bridge.owner;
    coordinator.lifecycleChanged(AppLifecycleState.hidden);
    expect(identical(owner, bridge.owner), isTrue);
    expect(coordinator.canAcquire, isFalse);
    bridge.listener!(const DesktopUploadEvent(paths: ['/tmp/new-hidden.pdf']));
    expect(cubit.state.rows, isEmpty);
    bridge.listener!(
      const DesktopUploadEvent(
        paths: ['/tmp/started-portal.pdf'],
        fromPortal: true,
      ),
    );
    expect(cubit.state.pending, 1);
    expect(repository.calls, 0);
    coordinator.lifecycleChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 1);
    await cubit.close();
    coordinator.dispose();
  });

  test('busy retirement invalidates portal registration and cancels hidden admitted batch without resuming it', () async {
    final bridge = _Bridge();
    final coordinator = DocumentUploadCoordinator(
      acquisition: NativeDocumentUploadAcquisition(),
      desktopBridge: bridge,
    );
    final repository = _Repository();
    final cubit = DocumentUploadsCubit(
      repository: repository,
      scheduler: coordinator,
      libraryName: 'Library',
      canRead: false,
      allowed: true,
    );
    coordinator.attach(cubit, busy: false);
    coordinator.lifecycleChanged(AppLifecycleState.hidden);
    bridge.listener!(
      const DesktopUploadEvent(paths: ['/tmp/started.pdf'], fromPortal: true),
    );
    coordinator.attach(cubit, busy: true);
    expect(bridge.owner, isNull);
    expect(cubit.state.pending, 0);
    coordinator.attach(cubit, busy: false);
    coordinator.lifecycleChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 0);
    await cubit.close();
    coordinator.dispose();
  });
}
