import 'package:bloc/bloc.dart';

final class WorkspaceCubit extends Cubit<String> {
  WorkspaceCubit() : super('documents');

  void select(String destination) {
    if (!isClosed) emit(destination);
  }
}
