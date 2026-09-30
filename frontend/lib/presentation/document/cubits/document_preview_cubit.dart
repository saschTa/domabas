import 'dart:ui' as ui;

import 'package:bloc/bloc.dart';

import '../../../domain/document/models/document.dart';
import '../models/document_previews.dart';

final class DocumentPreviewState {
  const DocumentPreviewState({this.image, this.loading = false});
  final ui.Image? image;
  final bool loading;
}

final class DocumentPreviewCubit extends Cubit<DocumentPreviewState> {
  DocumentPreviewCubit(this.coordinator, this.document)
    : super(const DocumentPreviewState());
  final DocumentPreviewCoordinator coordinator;
  final DocumentThumbnailRef? document;
  DocumentPreviewRequest? _request;
  Future<void> resume() async {
    if (!isClosed && state.image == null && _request?.cancelled == true) {
      await load();
    }
  }

  Future<void> load() async {
    if (isClosed) return;
    _request?.cancel();
    final request = _request = coordinator.request(document);
    if (isClosed) return;
    emit(DocumentPreviewState(image: state.image, loading: true));
    final image = await request.result.future;
    if (isClosed || !identical(request, _request)) {
      image?.dispose();
      return;
    }
    if (request.cancelled) {
      image?.dispose();
      emit(DocumentPreviewState(image: state.image));
      return;
    }
    final old = state.image;
    emit(DocumentPreviewState(image: image));
    old?.dispose();
  }

  @override
  Future<void> close() async {
    _request?.cancel();
    state.image?.dispose();
    await super.close();
  }
}
