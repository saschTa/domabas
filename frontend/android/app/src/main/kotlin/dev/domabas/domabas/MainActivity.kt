package dev.domabas.domabas

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var trustedCertificatesChannel: AndroidTrustedCertificatesChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        trustedCertificatesChannel = AndroidTrustedCertificatesChannel(
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        trustedCertificatesChannel?.close()
        trustedCertificatesChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
