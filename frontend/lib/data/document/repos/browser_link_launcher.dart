import '../../../domain/document/interfaces/document_processing_repository.dart';
import '../datasources/external_link_data_source.dart';

final class BrowserLinkLauncher implements ExternalLinkLauncher {
  BrowserLinkLauncher(this._source);
  final ExternalLinkDataSource _source;
  @override
  Future<bool> open(Uri uri) => _source.open(uri);
}
