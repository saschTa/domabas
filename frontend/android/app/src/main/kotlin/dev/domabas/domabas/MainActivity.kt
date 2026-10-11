package dev.domabas.domabas

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var trustedCertificatesChannel: AndroidTrustedCertificatesChannel? = null
    private var documentScannerChannel: MlKitDocumentScannerChannel? = null
    private var mobileShareChannel: MobileShareChannel? = null
    private var shareConsumed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        shareConsumed = savedInstanceState?.getBoolean("domabas.shareConsumed") ?: false
        super.onCreate(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("domabas.shareConsumed", shareConsumed)
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        mobileShareChannel?.receive(intent)
        setIntent(intent)
        shareConsumed = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        trustedCertificatesChannel = AndroidTrustedCertificatesChannel(
            flutterEngine.dartExecutor.binaryMessenger,
        )
        documentScannerChannel = MlKitDocumentScannerChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        mobileShareChannel = MobileShareChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        if (!shareConsumed) {
            mobileShareChannel?.receive(intent)
            shareConsumed = true
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documentScannerChannel?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mobileShareChannel?.close()
        mobileShareChannel = null
        documentScannerChannel?.close()
        documentScannerChannel = null
        trustedCertificatesChannel?.close()
        trustedCertificatesChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
