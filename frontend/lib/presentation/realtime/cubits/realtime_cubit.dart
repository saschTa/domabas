import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';

import '../../../domain/realtime/interfaces/realtime_repository.dart';
import '../../../domain/realtime/models/realtime.dart';

final class RealtimeState {
  RealtimeState({
    this.status = RealtimeStatus.inactive,
    Iterable<RealtimeTopic> topics = const [],
    Iterable<RealtimeTopic> invalidated = const [],
    this.revision = 0,
  }) : topics = Set.unmodifiable(topics),
       invalidated = Set.unmodifiable(invalidated);
  final RealtimeStatus status;
  final Set<RealtimeTopic> topics, invalidated;
  final int revision;
  bool get healthy => status == RealtimeStatus.healthy;
}

final class RealtimeCubit extends Cubit<RealtimeState> {
  RealtimeCubit(
    this._repository, {
    required this.onSessionEnded,
    this.connectTimeout = const Duration(seconds: 10),
    this.heartbeatTimeout = const Duration(seconds: 45),
    this.resyncInterval = const Duration(seconds: 60),
    double Function()? random,
  }) : _random = random ?? Random().nextDouble,
       super(RealtimeState()) {
    _subscription = _repository.events.listen(_event);
  }

  final RealtimeRepository _repository;
  final void Function() onSessionEnded;
  final Duration connectTimeout, heartbeatTimeout, resyncInterval;
  final double Function() _random;
  late final StreamSubscription<RealtimeEvent> _subscription;
  Timer? _retry, _heartbeat, _resync;
  bool _active = false, _closing = false;
  int _failures = 0;
  int _epoch = 0;

  void setActive(bool value) {
    if (_closing || value == _active) return;
    _active = value;
    _epoch++;
    _cancelTimers();
    if (value) {
      _connect();
    } else {
      _repository.disconnect();
      emit(RealtimeState(status: RealtimeStatus.inactive));
    }
  }

  void _connect() {
    if (_closing || !_active) return;
    final epoch = ++_epoch;
    emit(
      RealtimeState(
        status: _failures == 0
            ? RealtimeStatus.connecting
            : RealtimeStatus.reconnecting,
      ),
    );
    _heartbeat = Timer(connectTimeout, _lost);
    unawaited(
      _repository.connect().catchError((Object _) {
        if (!_closing && epoch == _epoch) _lost();
      }),
    );
  }

  void _event(RealtimeEvent event) {
    if (_closing || !_active) return;
    if (event.kind == RealtimeEventKind.disconnected) {
      if (event.closeCode == 4401 || event.closeCode == 4403) {
        _active = false;
        _cancelTimers();
        _repository.disconnect();
        emit(RealtimeState(status: RealtimeStatus.unavailable));
        onSessionEnded();
      } else {
        _lost();
      }
      return;
    }
    _heartbeat?.cancel();
    _heartbeat = Timer(heartbeatTimeout, _lost);
    if (event.kind == RealtimeEventKind.heartbeat) return;
    final topics =
        event.kind == RealtimeEventKind.ready ||
            event.kind == RealtimeEventKind.resync
        ? event.topics
        : state.topics;
    _failures = 0;
    emit(
      RealtimeState(
        status: RealtimeStatus.healthy,
        topics: topics,
        invalidated: event.topics,
        revision: state.revision + 1,
      ),
    );
    _resync ??= Timer.periodic(resyncInterval, (_) {
      if (!_closing && _active && state.healthy) {
        emit(
          RealtimeState(
            status: state.status,
            topics: state.topics,
            invalidated: state.topics.where(
              (topic) => const {
                RealtimeTopic.documents,
                RealtimeTopic.identity,
                RealtimeTopic.members,
                RealtimeTopic.systemUsers,
              }.contains(topic),
            ),
            revision: state.revision + 1,
          ),
        );
      }
    });
  }

  void _lost() {
    if (_closing || !_active || _retry != null) return;
    _epoch++;
    _heartbeat?.cancel();
    _resync?.cancel();
    _resync = null;
    _repository.disconnect();
    emit(RealtimeState(status: RealtimeStatus.reconnecting));
    final milliseconds = min(15000, 500 * (1 << min(_failures++, 5)));
    _retry = Timer(
      Duration(milliseconds: (milliseconds * (.8 + .4 * _random())).round()),
      () {
        _retry = null;
        _connect();
      },
    );
  }

  void _cancelTimers() {
    _retry?.cancel();
    _heartbeat?.cancel();
    _resync?.cancel();
    _retry = _heartbeat = _resync = null;
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _epoch++;
    _cancelTimers();
    _repository.disconnect();
    await _subscription.cancel();
    await super.close();
  }
}
