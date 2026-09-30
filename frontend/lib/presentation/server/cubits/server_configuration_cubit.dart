import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../domain/server/interfaces/server_repository.dart';
import '../../../domain/server/models/server_address.dart';
import '../../../domain/server/models/server_failure.dart';

final class ServerConfigurationState {
  const ServerConfigurationState({
    this.address,
    this.loading = false,
    this.busy = false,
    this.message,
    this.error,
  });

  final ServerAddress? address;
  final bool loading;
  final bool busy;
  final String? message;
  final String? error;
}

final class ServerConfigurationCubit extends Cubit<ServerConfigurationState> {
  ServerConfigurationCubit(
    this._repository, {
    this.initialAddress = '',
    this.storageTimeout = const Duration(seconds: 3),
  }) : super(const ServerConfigurationState(loading: true));

  final ServerRepository _repository;
  final String initialAddress;
  final Duration storageTimeout;
  bool _closing = false;
  int _generation = 0;
  Timer? _saveTimer;

  Future<void> restore() async {
    if (_closing || state.busy) return;
    final generation = ++_generation;
    emit(ServerConfigurationState(address: state.address, loading: true));
    try {
      final saved = await _repository.read().timeout(storageTimeout);
      final selected =
          saved ??
          (initialAddress.trim().isEmpty
              ? null
              : ServerAddress.parse(initialAddress));
      if (!_closing && generation == _generation) {
        emit(ServerConfigurationState(address: selected));
      }
    } catch (_) {
      if (!_closing && generation == _generation) {
        emit(
          ServerConfigurationState(
            address: state.address,
            error: 'Could not load the saved server. Enter its address or try again.',
          ),
        );
      }
    }
  }

  Future<bool> connect(String value) async {
    if (_closing || state.busy || state.loading) return false;
    final ServerAddress address;
    try {
      address = ServerAddress.parse(value);
    } on FormatException catch (failure) {
      emit(
        ServerConfigurationState(
          address: state.address,
          error: failure.message,
        ),
      );
      return false;
    }
    ++_generation;
    emit(
      ServerConfigurationState(
        address: state.address,
        busy: true,
        message: 'Checking server…',
      ),
    );
    try {
      await _repository.check(address);
      if (_closing) return false;
      emit(
        ServerConfigurationState(
          address: state.address,
          busy: true,
          message: 'Saving server…',
        ),
      );
      _saveTimer = Timer(storageTimeout, () {
        if (_closing) return;
        emit(
          ServerConfigurationState(
            address: state.address,
            busy: true,
            message:
                'Still saving the server address. Waiting for device storage…',
          ),
        );
      });
      await _repository.save(address);
      if (_closing) return false;
      emit(
        ServerConfigurationState(
          address: address,
          message: 'Server connected.',
        ),
      );
      return true;
    } on ServerFailure catch (failure) {
      if (!_closing) {
        emit(
          ServerConfigurationState(
            address: state.address,
            error: failure.message,
          ),
        );
      }
      return false;
    } catch (_) {
      if (!_closing) {
        emit(
          ServerConfigurationState(
            address: state.address,
            error: 'Could not configure this server. Please try again.',
          ),
        );
      }
      return false;
    } finally {
      _saveTimer?.cancel();
      _saveTimer = null;
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    ++_generation;
    _saveTimer?.cancel();
    return super.close();
  }
}
