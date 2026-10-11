import 'package:domabas_api/api.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../domain/appearance/interfaces/appearance_repository.dart';
import '../domain/licenses/interfaces/third_party_license_repository.dart';
import '../data/licenses/datasources/bundled_third_party_license_data_source.dart';
import '../data/licenses/repos/bundled_third_party_license_repository.dart';
import '../domain/chat/interfaces/chat_repository.dart';
import '../data/chat/datasources/chat_remote_data_source.dart';
import '../data/chat/repos/remote_chat_repository.dart';
import '../domain/invoice/interfaces/invoice_repository.dart';
import '../data/invoice/datasources/invoice_remote_data_source.dart';
import '../data/invoice/repos/remote_invoice_repository.dart';
import '../domain/paperless/interfaces/paperless_repository.dart';
import '../domain/paperless/interfaces/paperless_settings_repository.dart';
import '../data/paperless/datasources/paperless_remote_data_source.dart';
import '../data/paperless/repos/remote_paperless_repository.dart';
import '../data/paperless/repos/remote_paperless_settings_repository.dart';
import '../domain/workload/interfaces/workload_settings_repository.dart';
import '../data/workload/datasources/workload_remote_data_source.dart';
import '../data/workload/repos/remote_workload_settings_repository.dart';
import '../data/appearance/datasources/preferences_appearance_data_source.dart';
import '../data/appearance/repos/local_appearance_repository.dart';

import '../data/document/datasources/document_remote_data_source.dart';
import '../data/document/datasources/document_file_save_data_source.dart';
import '../data/document/repos/local_document_file_saver.dart';
import '../data/document/repos/remote_document_repository.dart';
import '../domain/document/interfaces/document_file_saver.dart';
import '../domain/document/interfaces/document_repository.dart';
import '../domain/document/interfaces/document_vocabulary_repository.dart';
import '../data/document/datasources/document_vocabulary_remote_data_source.dart';
import '../data/document/repos/remote_document_vocabulary_repository.dart';
import '../domain/document/interfaces/document_processing_repository.dart';
import '../data/document/datasources/document_processing_remote_data_source.dart';
import '../data/document/repos/remote_document_processing_repository.dart';
import '../data/document/datasources/external_link_data_source.dart';
import '../data/document/repos/browser_link_launcher.dart';
import '../data/identity/datasources/identity_remote_data_source.dart';
import '../data/identity/repos/remote_identity_repository.dart';
import '../domain/identity/models/identity.dart';
import '../domain/identity/interfaces/identity_repository.dart';
import '../domain/identity/interfaces/session_store.dart';
import '../domain/email/interfaces/email_repository.dart';
import '../domain/identity/interfaces/personal_activity_repository.dart';
import '../data/email/datasources/email_remote_data_source.dart';
import '../data/email/repos/remote_email_repository.dart';
import '../data/identity/datasources/personal_activity_remote_data_source.dart';
import '../data/identity/repos/remote_personal_activity_repository.dart';
import '../domain/realtime/interfaces/realtime_repository.dart';
import '../data/realtime/datasources/realtime_websocket_data_source.dart';
import '../data/realtime/repos/remote_realtime_repository.dart';
import 'api_endpoint.dart';
import 'http_client.dart';
import 'limited_response_client.dart';
import 'persistent_session_store.dart';
import 'realtime_socket_factory.dart';
import 'session_client.dart';
import 'scanner_scope.dart';
import 'document_upload_coordinator.dart';
import 'mobile_share_cubit.dart';
import '../data/document/datasources/document_upload_remote_data_source.dart';
import '../data/document/repos/remote_document_upload_repository.dart';
import '../presentation/document/cubits/document_uploads_cubit.dart';

final class AuthenticatedDependencies {
  AuthenticatedDependencies({
    required this.documents,
    this.documentFileSaver,
    this.invoices,
    this.chat,
    this.vocabulary,
    this.paperless,
    this.paperlessSettings,
    this.workloadSettings,
    this.licenses,
    required this.identity,
    required this.processing,
    required this.email,
    required this.activity,
    required this.realtime,
    required this.externalLinks,
    this.scanner,
    this.uploads,
    required this._close,
  });

  final DocumentRepository documents;
  final DocumentFileSaver? documentFileSaver;
  final InvoiceRepository? invoices;
  final ChatRepository? chat;
  final PaperlessRepository? paperless;
  final PaperlessSettingsRepository? paperlessSettings;
  final WorkloadSettingsRepository? workloadSettings;
  final ThirdPartyLicenseRepository? licenses;
  final DocumentVocabularyRepository? vocabulary;
  final IdentityRepository identity;
  final DocumentProcessingRepository processing;
  final EmailRepository email;
  final PersonalActivityRepository activity;
  final RealtimeRepository realtime;
  final ExternalLinkLauncher externalLinks;
  final ScannerScopeFactory? scanner;
  final DocumentUploadsCubit? uploads;
  final void Function() _close;
  bool _disposed = false;
  bool _documentsCancelled = false;

  void cancelDocuments() {
    if (_documentsCancelled) return;
    _documentsCancelled = true;
    scanner?.cancelNewOperations();
    uploads?.retire();
    realtime.dispose();
    documents.cancelRequests();
    invoices?.cancelRequests();
    chat?.cancelRequests();
    vocabulary?.cancelRequests();
    processing.cancelRequests();
    email.cancelRequests();
    paperless?.cancelRequests();
    paperlessSettings?.cancelRequests();
    workloadSettings?.cancelRequests();
    activity.cancelRequests();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelDocuments();
    uploads?.close();
    _close();
  }
}

final class AppDependencies {
  AppDependencies._(this._client, this._endpoint, this.auth, this.appearance);

  factory AppDependencies.production({
    String baseUrl = const String.fromEnvironment('API_BASE_URL'),
  }) {
    final endpoint = ApiEndpoint.resolve(
      baseUrl,
      browserUri: kIsWeb ? Uri.base : null,
    );
    final client = LimitedResponseClient(createHttpClient());
    return AppDependencies._(
      client,
      endpoint.baseUrl,
      _identity(
        _apiClient(endpoint.baseUrl, client),
        sessionStore: createPersistentSessionStore(endpoint.baseUrl),
      ),
      LocalAppearanceRepository(PreferencesAppearanceDataSource()),
    );
  }

  final http.Client _client;
  final String _endpoint;
  final AuthRepository auth;
  final AppearanceRepository appearance;
  final ScannerCoordinator _scannerCoordinator = createScannerCoordinator();
  final DocumentUploadCoordinator uploads = DocumentUploadCoordinator();
  late final MobileShareCubit? shares = MobileShareCubit.production(
    _endpoint,
    uploads,
  );

  AuthenticatedDependencies authenticate(
    AuthSession session,
    void Function() onUnauthorized,
  ) {
    final client = SessionClient(
      LimitedResponseClient(createHttpClient()),
      token: session.token,
      onUnauthorized: onUnauthorized,
    );
    final apiClient = _apiClient(_endpoint, client);
    return AuthenticatedDependencies(
      licenses: BundledThirdPartyLicenseRepository(
        dataSource: BundledThirdPartyLicenseDataSource(
          bundle: rootBundle,
          licenses: () => LicenseRegistry.licenses,
        ),
      ),
      chat: RemoteChatRepository(ChatRemoteDataSource(api.ChatApi(apiClient))),
      invoices: RemoteInvoiceRepository(
        InvoiceRemoteDataSource(api.InvoicesApi(apiClient)),
      ),
      paperless: RemotePaperlessRepository(
        PaperlessRemoteDataSource(api.PaperlessApi(apiClient)),
      ),
      paperlessSettings: RemotePaperlessSettingsRepository(
        PaperlessRemoteDataSource(api.PaperlessApi(apiClient)),
      ),
      workloadSettings: RemoteWorkloadSettingsRepository(
        WorkloadRemoteDataSource(api.SystemApi(apiClient)),
      ),
      documents: RemoteDocumentRepository(
        DocumentRemoteDataSource(api.DocumentsApi(apiClient)),
      ),
      documentFileSaver: LocalDocumentFileSaver(DocumentFileSaveDataSource()),
      vocabulary: RemoteDocumentVocabularyRepository(
        DocumentVocabularyRemoteDataSource(api.DocumentsApi(apiClient)),
      ),
      identity: _identity(apiClient),
      email: RemoteEmailRepository(
        EmailRemoteDataSource(api.EmailApi(apiClient)),
        namespaceId: session.identity.accountId,
      ),
      activity: RemotePersonalActivityRepository(
        PersonalActivityRemoteDataSource(api.IdentityApi(apiClient)),
      ),
      realtime: RemoteRealtimeRepository(
        RealtimeWebSocketDataSource(
          endpoint: _endpoint,
          token: session.token,
          socketFactory: createRealtimeSocketAttempt,
        ),
      ),
      processing: RemoteDocumentProcessingRepository(
        DocumentProcessingRemoteDataSource(api.DocumentsApi(apiClient)),
      ),
      scanner: _scannerCoordinator.forSession(
        _endpoint,
        session.identity,
        apiClient,
      ),
      uploads: DocumentUploadsCubit(
        repository: RemoteDocumentUploadRepository(
          uploads.acquisition,
          DocumentUploadRemoteDataSource(apiClient),
        ),
        scheduler: uploads,
        libraryName: session.identity.accountName,
        canRead: session.identity.allows(IdentityPermission.readDocuments),
        allowed: session.identity.allows(IdentityPermission.uploadDocuments),
      ),
      externalLinks: BrowserLinkLauncher(ExternalLinkDataSource()),
      close: client.close,
    );
  }

  static api.ApiClient _apiClient(String endpoint, http.Client client) {
    final generated = api.ApiClient(basePath: endpoint);
    generated.client.close();
    generated.client = client;
    return generated;
  }

  static RemoteIdentityRepository _identity(
    api.ApiClient client, {
    SessionStore? sessionStore,
  }) => RemoteIdentityRepository(
    IdentityRemoteDataSource(api.IdentityApi(client)),
    sessionStore: sessionStore,
  );

  void dispose() {
    uploads.dispose();
    shares?.close();
    _client.close();
  }
}
