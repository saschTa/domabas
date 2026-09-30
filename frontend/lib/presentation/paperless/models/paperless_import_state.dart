import '../../../domain/paperless/models/paperless.dart';

final class PaperlessImportState {
  PaperlessImportState({
    this.options,
    this.cursor,
    this.browsingHistory = false,
    Iterable<PaperlessRun> runs = const [],
    this.loading = false,
    this.saving = false,
    this.pendingRequest = false,
    this.error,
  }) : runs = List.unmodifiable(runs);
  final PaperlessOptions? options;
  final List<PaperlessRun> runs;
  final bool loading, saving, pendingRequest, browsingHistory;
  final String? error, cursor;
  bool get busy => loading || saving;
}
