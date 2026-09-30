import 'package:domabas_api/api.dart' as api;

import '../domain/identity/models/identity.dart';
import 'scanner_scope.dart';

ScannerCoordinator createScannerCoordinator() =>
    _UnsupportedScannerCoordinator();

final class _UnsupportedScannerCoordinator implements ScannerCoordinator {
  @override
  ScannerScopeFactory? forSession(
    String endpoint,
    Identity identity,
    api.ApiClient client,
  ) => null;
}
