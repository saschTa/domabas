package dev.domabas.domabas

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var trustedCertificatesChannel: AndroidTrustedCertificatesChannel? = null
    private var documentScannerChannel: MlKitDocumentScannerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        trustedCertificatesChannel = AndroidTrustedCertificatesChannel(
            flutterEngine.dartExecutor.binaryMessenger,
        )
        documentScannerChannel = MlKitDocumentScannerChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documentScannerChannel?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        documentScannerChannel?.close()
        documentScannerChannel = null
        trustedCertificatesChannel?.close()
        trustedCertificatesChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
