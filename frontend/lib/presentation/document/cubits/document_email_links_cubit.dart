import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/document/interfaces/document_repository.dart';
import '../../../domain/document/models/document_email.dart';
import '../../../domain/document/models/document_failure.dart';

final class DocumentEmailLinksState {
  DocumentEmailLinksState({
    Iterable<DocumentEmailAttachment> attachments = const [],
    Iterable<DocumentLink> parents = const [],
    this.attachmentCursor,
    this.parentCursor,
    this.loading = false,
    this.stale = false,
    this.error,
  }) : attachments = List.unmodifiable(attachments),
       parents = List.unmodifiable(parents);
  final List<DocumentEmailAttachment> attachments;
  final List<DocumentLink> parents;
  final String? attachmentCursor, parentCursor, error;
  final bool loading;
  final bool stale;
}

final class DocumentEmailLinksCubit extends Cubit<DocumentEmailLinksState> {
  DocumentEmailLinksCubit(this._repository, this.id)
    : super(DocumentEmailLinksState());
  final DocumentRepository _repository;
  final String id;
  final _cancel = Completer<void>();
  bool _closing = false;
  bool _paged = false;
  bool _loading = false, _background = false, _loaded = false;
  Completer<void>? _readDone;
  late final _refresh = AutomaticRefresh(
    read: _refreshRemote,
    busy: () => _loading,
    interval: () => Duration(seconds: state.error == null ? 1 : 30),
  );
  void setActive(bool value) => _refresh.setActive(value);
  void invalidate() => _refresh.invalidate();
  Future<void> reload() => load(reset: true);

  Future<void> _refreshRemote() async {
    if (_paged) {
      emit(
        DocumentEmailLinksState(
          attachments: state.attachments,
          parents: state.parents,
          attachmentCursor: state.attachmentCursor,
          parentCursor: state.parentCursor,
          stale: true,
          error: state.error,
        ),
      );
    } else {
      await load(automatic: true);
    }
  }

  Future<void> load({
    bool moreAttachments = false,
    bool moreParents = false,
    bool reset = false,
    bool automatic = false,
  }) async {
    if (_loading && _background && !automatic) await _readDone?.future;
    if (_closing || _loading || state.stale && !reset) return;
    _loading = true;
    _background = automatic && _loaded;
    final done = _readDone = Completer<void>();
    final previous = state;
    emit(
      DocumentEmailLinksState(
        attachments: previous.attachments,
        parents: previous.parents,
        attachmentCursor: previous.attachmentCursor,
        parentCursor: previous.parentCursor,
        loading: !_background,
        stale: previous.stale,
        error: automatic ? previous.error : null,
      ),
    );
    try {
      final attachments = moreParents
          ? null
          : await _repository.emailLinks(
              id,
              cursor: moreAttachments ? previous.attachmentCursor : null,
              cancel: _cancel.future,
            );
      if (_closing) return;
      final parents = moreAttachments
          ? null
          : await _repository.emailParents(
              id,
              cursor: moreParents ? previous.parentCursor : null,
              cancel: _cancel.future,
            );
      if (_closing) return;
      _paged = reset ? false : _paged || moreAttachments || moreParents;
      _loaded = true;
      emit(
        DocumentEmailLinksState(
          attachments: attachments == null
              ? previous.attachments
              : moreAttachments
              ? [
                  ...previous.attachments,
                  ...attachments.attachments.where(
                    (v) => !previous.attachments.any((p) => p.part == v.part),
                  ),
                ]
              : attachments.attachments,
          parents: parents == null
              ? previous.parents
              : moreParents
              ? [
                  ...previous.parents,
                  ...parents.items.where(
                    (v) => !previous.parents.any((p) => p.id == v.id),
                  ),
                ]
              : parents.items,
          attachmentCursor: attachments == null
              ? previous.attachmentCursor
              : attachments.nextCursor,
          parentCursor: parents == null
              ? previous.parentCursor
              : parents.nextCursor,
        ),
      );
    } on DocumentFailure catch (failure) {
      if (!_closing) {
        emit(
          DocumentEmailLinksState(
            attachments: previous.attachments,
            parents: previous.parents,
            attachmentCursor: previous.attachmentCursor,
            parentCursor: previous.parentCursor,
            error: failure.message,
            stale: previous.stale,
          ),
        );
      }
    } finally {
      _loading = false;
      done.complete();
    }
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _refresh.dispose();
    _closing = true;
    if (!_cancel.isCompleted) _cancel.complete();
    await super.close();
  }
}
