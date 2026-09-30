import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/server/datasources/android_trust_certificate_data_source.dart';

Future<HttpClient> createNativeHttpClient() =>
    NativeHttpClientFactory().create();

final class NativeHttpClientFactory {
  NativeHttpClientFactory({
    AndroidTrustCertificateDataSource? androidCertificates,
  }) : _androidCertificates =
           androidCertificates ??
           (Platform.isAndroid ? AndroidTrustCertificateDataSource() : null);

  final AndroidTrustCertificateDataSource? _androidCertificates;

  Future<HttpClient> create() async {
    final certificates = _androidCertificates;
    if (certificates == null) return HttpClient();
    try {
      final context = SecurityContext()
        ..setTrustedCertificatesBytes(
          utf8.encode(await certificates.loadPemBundle()),
        );
      return HttpClient(context: context);
    } on Exception {
      throw http.ClientException(
        'Could not load Android trusted certificates.',
      );
    }
  }
}
