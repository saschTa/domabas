package dev.domabas.domabas

import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.security.KeyStore
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

class AndroidTrustedCertificatesChannel(messenger: BinaryMessenger) {
    private val channel = MethodChannel(
        messenger,
        "dev.domabas/trusted_certificates",
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    )

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "loadTrustedCertificates") {
                result.notImplemented()
            } else {
                try {
                    val factory = TrustManagerFactory.getInstance(
                        TrustManagerFactory.getDefaultAlgorithm(),
                    )
                    factory.init(null as KeyStore?)
                    val certificates = factory.trustManagers
                        .filterIsInstance<X509TrustManager>()
                        .flatMap { it.acceptedIssuers.toList() }
                    check(certificates.isNotEmpty())
                    result.success(certificates.joinToString("\n") { certificate ->
                        "-----BEGIN CERTIFICATE-----\n" +
                            Base64.encodeToString(certificate.encoded, Base64.NO_WRAP) +
                            "\n-----END CERTIFICATE-----\n"
                    })
                } catch (_: Exception) {
                    result.error(
                        "certificate_store_unavailable",
                        "Android trusted certificates could not be loaded.",
                        null,
                    )
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
    }
}
