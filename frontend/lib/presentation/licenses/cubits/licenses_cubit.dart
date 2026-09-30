import 'package:bloc/bloc.dart';

import '../../../domain/licenses/interfaces/third_party_license_repository.dart';
import '../../../domain/licenses/models/third_party_license.dart';

final class LicensesState {
  LicensesState({
    List<ThirdPartyLicense> entries = const [],
    this.query = '',
    this.loading = false,
    this.loaded = false,
    this.error,
  }) : entries = List.unmodifiable(entries);

  final List<ThirdPartyLicense> entries;
  final String query;
  final bool loading, loaded;
  final String? error;

  List<ThirdPartyLicense> get matches {
    final terms = query.toLowerCase().trim().split(RegExp(r'\s+'));
    return entries
        .where((entry) {
          final searchable =
              '${entry.name} ${entry.version} ${entry.component} ${entry.license}'
                  .toLowerCase();
          return terms.every(searchable.contains);
        })
        .toList(growable: false);
  }
}

final class LicensesCubit extends Cubit<LicensesState> {
  LicensesCubit(this._repository) : super(LicensesState());

  final ThirdPartyLicenseRepository? _repository;

  Future<void> load() async {
    if (isClosed || state.loading || state.loaded) return;
    emit(_state(loading: true));
    try {
      final repository = _repository;
      if (repository == null) throw StateError('License source unavailable');
      final entries = [...await repository.load()]
        ..sort((left, right) {
          final name = left.name.toLowerCase().compareTo(
            right.name.toLowerCase(),
          );
          return name == 0 ? left.id.compareTo(right.id) : name;
        });
      if (isClosed) return;
      emit(LicensesState(entries: entries, query: state.query, loaded: true));
    } catch (_) {
      if (isClosed) return;
      emit(
        _state(
          error: 'The bundled license notices could not be loaded. Try again.',
        ),
      );
    }
  }

  void search(String query) {
    if (isClosed || state.query == query) return;
    emit(
      LicensesState(
        entries: state.entries,
        query: query,
        loading: state.loading,
        loaded: state.loaded,
        error: state.error,
      ),
    );
  }

  LicensesState _state({bool loading = false, String? error}) => LicensesState(
    entries: state.entries,
    query: state.query,
    loading: loading,
    loaded: state.loaded,
    error: error,
  );
}
