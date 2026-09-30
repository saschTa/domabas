import 'dart:async';

abstract interface class DocumentUploadScheduler {
  bool get contentBusy;
  Stream<void> get changes;
  bool start(Future<void> Function() operation);
}
