import 'package:flutter/services.dart';

final class AndroidTrustCertificateDataSource {
  AndroidTrustCertificateDataSource({
    this._channel = const MethodChannel('dev.domabas/trusted_certificates'),
    this.timeout = const Duration(seconds: 5),
  });

  final MethodChannel _channel;
  final Duration timeout;

  Future<String> loadPemBundle() async {
    final bundle = await _channel
        .invokeMethod<String>('loadTrustedCertificates')
        .timeout(timeout);
    if (bundle == null || bundle.trim().isEmpty) {
      throw const FormatException('Android returned no trusted certificates');
    }
    return bundle;
  }
}
