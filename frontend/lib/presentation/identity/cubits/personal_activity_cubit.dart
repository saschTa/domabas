import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../scheduling/automatic_refresh.dart';

import '../../../domain/identity/interfaces/personal_activity_repository.dart';
import '../../../domain/identity/models/personal_activity.dart';

final class PersonalActivityState {
  const PersonalActivityState({
    this.activity,
    this.loading = false,
    this.error,
    this.activePage = 1,
    this.finishedPage = 1,
  });
  final PersonalActivity? activity;
  final bool loading;
  final String? error;
  final int activePage, finishedPage;
}

final class PersonalActivityCubit extends Cubit<PersonalActivityState> {
  PersonalActivityCubit(this._repository)
    : super(const PersonalActivityState());
  final PersonalActivityRepository _repository;
  late final _refresh = AutomaticRefresh(
    read: () => refresh(automatic: true),
    busy: () => _loading,
    interval: () => Duration(seconds: state.error == null ? 1 : 30),
  );
  void invalidate() => _refresh.invalidate();

  Completer<void>? _cancel;
  Completer<void>? _readDone;
  bool _loading = false;
  bool _active = false, _closing = false;
  int _epoch = 0;
  List<String?> _activePages = [null], _finishedPages = [null];
  void setActive(bool value) {
    if (_closing || value == _active) return;
    _active = value;
    _refresh.setActive(value);
    if (value) {
      unawaited(refresh(automatic: true));
    } else {
      _epoch++;
      _loading = false;
      if (_cancel case final cancel? when !cancel.isCompleted) {
        cancel.complete();
      }
      emit(
        PersonalActivityState(
          activity: state.activity,
          error: state.error,
          activePage: _activePages.length,
          finishedPage: _finishedPages.length,
        ),
      );
    }
  }

  Future<void> refresh({
    bool automatic = false,
    bool moreActive = false,
    bool moreFinished = false,
    bool previousActive = false,
    bool previousFinished = false,
  }) async {
    final moving =
        moreActive || moreFinished || previousActive || previousFinished;
    if (_closing || !_active) return;
    if (_loading) {
      if (!automatic && !state.loading) {
        emit(
          PersonalActivityState(
            activity: state.activity,
            activePage: _activePages.length,
            finishedPage: _finishedPages.length,
            loading: true,
            error: state.error,
          ),
        );
      }
      await _readDone!.future;
      if (moving) {
        await refresh(
          moreActive: moreActive,
          moreFinished: moreFinished,
          previousActive: previousActive,
          previousFinished: previousFinished,
        );
      }
      return;
    }
    if ((moreActive && state.activity?.activeNextCursor == null) ||
        (moreFinished && state.activity?.finishedNextCursor == null) ||
        (previousActive && _activePages.length == 1) ||
        (previousFinished && _finishedPages.length == 1)) {
      return;
    }
    final activePages = automatic || moving
        ? [..._activePages]
        : <String?>[null];
    final finishedPages = automatic || moving
        ? [..._finishedPages]
        : <String?>[null];
    if (moreActive) activePages.add(state.activity!.activeNextCursor);
    if (moreFinished) finishedPages.add(state.activity!.finishedNextCursor);
    if (previousActive) activePages.removeLast();
    if (previousFinished) finishedPages.removeLast();
    _loading = true;
    final readDone = _readDone = Completer<void>();
    final epoch = ++_epoch, cancel = _cancel = Completer<void>();
    emit(
      PersonalActivityState(
        activity: state.activity,
        activePage: _activePages.length,
        finishedPage: _finishedPages.length,
        loading: !automatic || state.activity == null,
        error: state.error,
      ),
    );
    try {
      final activity = await _repository.getActivity(
        activeCursor: activePages.last,
        finishedCursor: finishedPages.last,
        cancel: cancel.future,
      );
      if (!_closing && epoch == _epoch) {
        _activePages = activePages;
        _finishedPages = finishedPages;
        emit(
          PersonalActivityState(
            activity: activity,
            activePage: _activePages.length,
            finishedPage: _finishedPages.length,
          ),
        );
      }
    } on ActivityFailure catch (failure) {
      if (!_closing &&
          epoch == _epoch &&
          failure.kind != ActivityFailureKind.cancelled) {
        emit(
          PersonalActivityState(
            activity: state.activity,
            activePage: _activePages.length,
            finishedPage: _finishedPages.length,
            error: failure.message,
          ),
        );
      }
    } finally {
      if (!_closing && epoch == _epoch) {
        _loading = false;
        if (state.loading) {
          emit(
            PersonalActivityState(
              activity: state.activity,
              activePage: _activePages.length,
              finishedPage: _finishedPages.length,
              error: state.error,
            ),
          );
        }
      }
      readDone.complete();
    }
  }

  @override
  Future<void> close() async {
    _refresh.dispose();
    _closing = true;
    _epoch++;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
    await super.close();
  }
}
