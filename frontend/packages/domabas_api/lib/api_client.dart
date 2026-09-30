// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ApiClient {
  ApiClient({this.basePath = 'http://127.0.0.1:8080', this.authentication,});

  final String basePath;
  final Authentication? authentication;

  var _client = Client();
  final _defaultHeaderMap = <String, String>{};

  Client get client => _client;

  set client(Client newClient) {
    _client = newClient;
  }

  Map<String, String> get defaultHeaderMap => _defaultHeaderMap;

  void addDefaultHeader(String key, String value) {
     _defaultHeaderMap[key] = value;
  }

  Future<Response> invokeAPI(
    String path,
    String method,
    List<QueryParam> queryParams,
    Object? body,
    Map<String, String> headerParams,
    Map<String, String> formParams,
    String? contentType, {
    Future<void>? abortTrigger,
  }) async {
    await authentication?.applyToParams(queryParams, headerParams);

    headerParams.addAll(_defaultHeaderMap);
    if (contentType != null) {
      headerParams['Content-Type'] = contentType;
    }

    final urlEncodedQueryParams = queryParams.map((param) => '$param');
    final queryString = urlEncodedQueryParams.isNotEmpty ? '?${urlEncodedQueryParams.join('&')}' : '';
    final uri = Uri.parse('$basePath$path$queryString');

    try {
      if (
        body is MultipartFile && (contentType == null ||
        !contentType.toLowerCase().startsWith('multipart/form-data'))
      ) {
        final request = AbortableStreamedRequest(method, uri, abortTrigger: abortTrigger);
        request.headers.addAll(headerParams);
        request.contentLength = body.length;
        body.finalize().listen(
          request.sink.add,
          onDone: request.sink.close,
          // ignore: avoid_types_on_closure_parameters
          onError: (Object error, StackTrace trace) => request.sink.close(),
          cancelOnError: true,
        );
        final response = await _client.send(request);
        return Response.fromStream(response);
      }

      if (body is MultipartRequest) {
        final request = AbortableMultipartRequest(method, uri, abortTrigger: abortTrigger);
        request.fields.addAll(body.fields);
        request.files.addAll(body.files);
        request.headers.addAll(body.headers);
        request.headers.addAll(headerParams);
        final response = await _client.send(request);
        return Response.fromStream(response);
      }

      final msgBody = contentType == 'application/x-www-form-urlencoded'
        ? formParams
        : await serializeAsync(body);
      final nullableHeaderParams = headerParams.isEmpty ? null : headerParams;

      final request = AbortableRequest(method, uri, abortTrigger: abortTrigger);
      if (nullableHeaderParams != null) {
        request.headers.addAll(nullableHeaderParams);
      }
      if (msgBody is String && msgBody.isNotEmpty) {
        request.body = msgBody;
      } else if (msgBody is List<int> && msgBody.isNotEmpty) {
        request.bodyBytes = msgBody;
      } else if (msgBody is Map<String, String>) {
        request.bodyFields = msgBody;
      }
      final response = await _client.send(request);
      return Response.fromStream(response);
    } on SocketException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'Socket operation failed: $method $path',
        error,
        trace,
      );
    } on TlsException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'TLS/SSL communication failed: $method $path',
        error,
        trace,
      );
    } on IOException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'I/O operation failed: $method $path',
        error,
        trace,
      );
    } on ClientException catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'HTTP connection failed: $method $path',
        error,
        trace,
      );
    } on Exception catch (error, trace) {
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'Exception occurred: $method $path',
        error,
        trace,
      );
    }
  }

  Future<dynamic> deserializeAsync(String value, String targetType, {bool growable = false,}) async =>
    // ignore: deprecated_member_use_from_same_package
    deserialize(value, targetType, growable: growable);

  @Deprecated('Scheduled for removal in OpenAPI Generator 6.x. Use deserializeAsync() instead.')
  dynamic deserialize(String value, String targetType, {bool growable = false,}) {
    targetType = targetType.replaceAll(' ', ''); // ignore: parameter_assignments

    return targetType == 'String'
      ? value
      : fromJson(json.decode(value), targetType, growable: growable);
  }

  // ignore: deprecated_member_use_from_same_package
  Future<String> serializeAsync(Object? value) async => serialize(value);

  @Deprecated('Scheduled for removal in OpenAPI Generator 6.x. Use serializeAsync() instead.')
  String serialize(Object? value) => value == null ? '' : json.encode(value);

  static dynamic fromJson(dynamic value, String targetType, {bool growable = false,}) {
    try {
      switch (targetType) {
        case 'String':
          return value is String ? value : value.toString();
        case 'int':
          return value is int ? value : int.parse('$value');
        case 'double':
          return value is double ? value : double.parse('$value');
        case 'bool':
          if (value is bool) {
            return value;
          }
          final valueString = '$value'.toLowerCase();
          return valueString == 'true' || valueString == '1';
        case 'DateTime':
          return value is DateTime ? value : DateTime.tryParse(value);
        case 'AcceptInvitation':
          return AcceptInvitation.fromJson(value);
        case 'AccountIdentity':
          return AccountIdentity.fromJson(value);
        case 'AccountMembership':
          return AccountMembership.fromJson(value);
        case 'AccountMembershipList':
          return AccountMembershipList.fromJson(value);
        case 'AccountRole':
          return AccountRoleTypeTransformer().decode(value);
        case 'AccountUser':
          return AccountUser.fromJson(value);
        case 'AccountUserList':
          return AccountUserList.fromJson(value);
        case 'AuthSession':
          return AuthSession.fromJson(value);
        case 'ChatAcceptedTurn':
          return ChatAcceptedTurn.fromJson(value);
        case 'ChatConfiguration':
          return ChatConfiguration.fromJson(value);
        case 'ChatConfigurationSummary':
          return ChatConfigurationSummary.fromJson(value);
        case 'ChatConversation':
          return ChatConversation.fromJson(value);
        case 'ChatConversationPage':
          return ChatConversationPage.fromJson(value);
        case 'ChatMessage':
          return ChatMessage.fromJson(value);
        case 'ChatMessagePage':
          return ChatMessagePage.fromJson(value);
        case 'ChatModel':
          return ChatModel.fromJson(value);
        case 'ChatModelPage':
          return ChatModelPage.fromJson(value);
        case 'ChatSource':
          return ChatSource.fromJson(value);
        case 'Claim':
          return Claim.fromJson(value);
        case 'ClaimList':
          return ClaimList.fromJson(value);
        case 'CreateAccountUser':
          return CreateAccountUser.fromJson(value);
        case 'CreateChatConversationRequest':
          return CreateChatConversationRequest.fromJson(value);
        case 'CreateDocument':
          return CreateDocument.fromJson(value);
        case 'CreateDocumentReindexBatch':
          return CreateDocumentReindexBatch.fromJson(value);
        case 'CreateEmailProvider':
          return CreateEmailProvider.fromJson(value);
        case 'CreateInvitation':
          return CreateInvitation.fromJson(value);
        case 'CurrentIdentity':
          return CurrentIdentity.fromJson(value);
        case 'Document':
          return Document.fromJson(value);
        case 'DocumentAIProcessing':
          return DocumentAIProcessing.fromJson(value);
        case 'DocumentEmailAttachment':
          return DocumentEmailAttachment.fromJson(value);
        case 'DocumentEmailLinks':
          return DocumentEmailLinks.fromJson(value);
        case 'DocumentEmailParents':
          return DocumentEmailParents.fromJson(value);
        case 'DocumentFile':
          return DocumentFile.fromJson(value);
        case 'DocumentJob':
          return DocumentJob.fromJson(value);
        case 'DocumentJobCount':
          return DocumentJobCount.fromJson(value);
        case 'DocumentJobCounts':
          return DocumentJobCounts.fromJson(value);
        case 'DocumentJobPage':
          return DocumentJobPage.fromJson(value);
        case 'DocumentLink':
          return DocumentLink.fromJson(value);
        case 'DocumentList':
          return DocumentList.fromJson(value);
        case 'DocumentOCR':
          return DocumentOCR.fromJson(value);
        case 'DocumentProcessing':
          return DocumentProcessing.fromJson(value);
        case 'DocumentProcessingConfiguration':
          return DocumentProcessingConfiguration.fromJson(value);
        case 'DocumentProcessingConfigurationSnapshot':
          return DocumentProcessingConfigurationSnapshot.fromJson(value);
        case 'DocumentProcessingPipeline':
          return DocumentProcessingPipeline.fromJson(value);
        case 'DocumentProcessingScheduling':
          return DocumentProcessingScheduling.fromJson(value);
        case 'DocumentProcessingWeight':
          return DocumentProcessingWeight.fromJson(value);
        case 'DocumentReindexBatch':
          return DocumentReindexBatch.fromJson(value);
        case 'DocumentReindexBatchPage':
          return DocumentReindexBatchPage.fromJson(value);
        case 'DocumentSearch':
          return DocumentSearch.fromJson(value);
        case 'DocumentSearchItem':
          return DocumentSearchItem.fromJson(value);
        case 'DocumentSearchOriginal':
          return DocumentSearchOriginal.fromJson(value);
        case 'DocumentSearchResults':
          return DocumentSearchResults.fromJson(value);
        case 'DocumentSearchSummary':
          return DocumentSearchSummary.fromJson(value);
        case 'DocumentThumbnail':
          return DocumentThumbnail.fromJson(value);
        case 'DocumentVocabularyOption':
          return DocumentVocabularyOption.fromJson(value);
        case 'DocumentVocabularyPage':
          return DocumentVocabularyPage.fromJson(value);
        case 'EmailCapabilities':
          return EmailCapabilities.fromJson(value);
        case 'EmailConnectionTest':
          return EmailConnectionTest.fromJson(value);
        case 'EmailProvider':
          return EmailProvider.fromJson(value);
        case 'EmailProviderPage':
          return EmailProviderPage.fromJson(value);
        case 'EmailProviderSummary':
          return EmailProviderSummary.fromJson(value);
        case 'EmailRun':
          return EmailRun.fromJson(value);
        case 'EmailRunPage':
          return EmailRunPage.fromJson(value);
        case 'Error':
          return Error.fromJson(value);
        case 'Health':
          return Health.fromJson(value);
        case 'Invitation':
          return Invitation.fromJson(value);
        case 'InvitationList':
          return InvitationList.fromJson(value);
        case 'Invoice':
          return Invoice.fromJson(value);
        case 'InvoiceAllowance':
          return InvoiceAllowance.fromJson(value);
        case 'InvoiceClassification':
          return InvoiceClassification.fromJson(value);
        case 'InvoiceFilterValuePage':
          return InvoiceFilterValuePage.fromJson(value);
        case 'InvoiceLine':
          return InvoiceLine.fromJson(value);
        case 'InvoicePage':
          return InvoicePage.fromJson(value);
        case 'InvoiceParty':
          return InvoiceParty.fromJson(value);
        case 'InvoicePayment':
          return InvoicePayment.fromJson(value);
        case 'InvoiceReference':
          return InvoiceReference.fromJson(value);
        case 'InvoiceTax':
          return InvoiceTax.fromJson(value);
        case 'IssuedInvitation':
          return IssuedInvitation.fromJson(value);
        case 'JobStatusCount':
          return JobStatusCount.fromJson(value);
        case 'JobStatusCounts':
          return JobStatusCounts.fromJson(value);
        case 'LLMConfiguration':
          return LLMConfiguration.fromJson(value);
        case 'Login':
          return Login.fromJson(value);
        case 'OllamaModelContext':
          return OllamaModelContext.fromJson(value);
        case 'PaperlessOptions':
          return PaperlessOptions.fromJson(value);
        case 'PaperlessOutcome':
          return PaperlessOutcome.fromJson(value);
        case 'PaperlessOutcomePage':
          return PaperlessOutcomePage.fromJson(value);
        case 'PaperlessRun':
          return PaperlessRun.fromJson(value);
        case 'PaperlessRunPage':
          return PaperlessRunPage.fromJson(value);
        case 'PaperlessSettings':
          return PaperlessSettings.fromJson(value);
        case 'PasswordChange':
          return PasswordChange.fromJson(value);
        case 'PersonalActivity':
          return PersonalActivity.fromJson(value);
        case 'PersonalActivityItem':
          return PersonalActivityItem.fromJson(value);
        case 'RealtimeAuthenticate':
          return RealtimeAuthenticate.fromJson(value);
        case 'RealtimeHeartbeat':
          return RealtimeHeartbeat.fromJson(value);
        case 'RealtimeInvalidation':
          return RealtimeInvalidation.fromJson(value);
        case 'RealtimeReady':
          return RealtimeReady.fromJson(value);
        case 'RealtimeResync':
          return RealtimeResync.fromJson(value);
        case 'RealtimeTopic':
          return RealtimeTopicTypeTransformer().decode(value);
        case 'Registration':
          return Registration.fromJson(value);
        case 'SendChatMessageRequest':
          return SendChatMessageRequest.fromJson(value);
        case 'StartEmailRun':
          return StartEmailRun.fromJson(value);
        case 'StartPaperlessRun':
          return StartPaperlessRun.fromJson(value);
        case 'SwitchAccount':
          return SwitchAccount.fromJson(value);
        case 'SystemRole':
          return SystemRoleTypeTransformer().decode(value);
        case 'SystemUser':
          return SystemUser.fromJson(value);
        case 'SystemUserList':
          return SystemUserList.fromJson(value);
        case 'TestEmailConnection':
          return TestEmailConnection.fromJson(value);
        case 'UnlockDocument':
          return UnlockDocument.fromJson(value);
        case 'UpdateAccountUser':
          return UpdateAccountUser.fromJson(value);
        case 'UpdateChatConfigurationRequest':
          return UpdateChatConfigurationRequest.fromJson(value);
        case 'UpdateDocument':
          return UpdateDocument.fromJson(value);
        case 'UpdateDocumentOCR':
          return UpdateDocumentOCR.fromJson(value);
        case 'UpdateDocumentProcessingConfiguration':
          return UpdateDocumentProcessingConfiguration.fromJson(value);
        case 'UpdateEmailProvider':
          return UpdateEmailProvider.fromJson(value);
        case 'UpdateLLMConfiguration':
          return UpdateLLMConfiguration.fromJson(value);
        case 'UpdatePaperlessSettingsRequest':
          return UpdatePaperlessSettingsRequest.fromJson(value);
        case 'UpdateSystemUser':
          return UpdateSystemUser.fromJson(value);
        case 'UpdateWorkloadSettingsRequest':
          return UpdateWorkloadSettingsRequest.fromJson(value);
        case 'UploadDocumentMetadata':
          return UploadDocumentMetadata.fromJson(value);
        case 'UserIdentity':
          return UserIdentity.fromJson(value);
        case 'WorkloadPipeline':
          return WorkloadPipeline.fromJson(value);
        case 'WorkloadResource':
          return WorkloadResource.fromJson(value);
        case 'WorkloadResourceLimit':
          return WorkloadResourceLimit.fromJson(value);
        case 'WorkloadSettings':
          return WorkloadSettings.fromJson(value);
        default:
          dynamic match;
          if (value is List && (match = _regList.firstMatch(targetType)?.group(1)) != null) {
            return value
              .map<dynamic>((dynamic v) => fromJson(v, match, growable: growable,))
              .toList(growable: growable);
          }
          if (value is Set && (match = _regSet.firstMatch(targetType)?.group(1)) != null) {
            return value
              .map<dynamic>((dynamic v) => fromJson(v, match, growable: growable,))
              .toSet();
          }
          if (value is Map && (match = _regMap.firstMatch(targetType)?.group(1)) != null) {
            return Map<String, dynamic>.fromIterables(
              value.keys.cast<String>(),
              value.values.map<dynamic>((dynamic v) => fromJson(v, match, growable: growable,)),
            );
          }
      }
    } on Exception catch (error, trace) {
      throw ApiException.withInner(HttpStatus.internalServerError, 'Exception during deserialization.', error, trace,);
    }
    throw ApiException(HttpStatus.internalServerError, 'Could not find a suitable class for deserialization',);
  }
}

class DeserializationMessage {
  const DeserializationMessage({
    required this.json,
    required this.targetType,
    this.growable = false,
  });

  final String json;

  final String targetType;

  final bool growable;
}

Future<dynamic> decodeAsync(DeserializationMessage message) async {
  final targetType = message.targetType.replaceAll(' ', '');

  return targetType == 'String'
    ? message.json
    : json.decode(message.json);
}

Future<dynamic> deserializeAsync(DeserializationMessage message) async {
  final targetType = message.targetType.replaceAll(' ', '');

  return targetType == 'String'
    ? message.json
    : ApiClient.fromJson(
        json.decode(message.json),
        targetType,
        growable: message.growable,
      );
}

Future<String> serializeAsync(Object? value) async => value == null ? '' : json.encode(value);
