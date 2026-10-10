package dev.domabas.domabas

import android.app.Activity
import android.content.Intent
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MlKitDocumentScannerChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private data class PendingScan(
        val id: String,
        val requestCode: Int,
        val result: MethodChannel.Result,
        var launched: Boolean = false,
    )

    private class ScanTooLargeException : Exception()

    private val channel = MethodChannel(messenger, "dev.domabas/document_scanner")
    private val reader = Executors.newSingleThreadExecutor()
    private var pending: PendingScan? = null
    private var nextRequestCode = 42000

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> {
                    val id = call.argument<String>("id")
                    if (id.isNullOrBlank()) {
                        result.error("scan_invalid", "A scan request ID is required.", null)
                    } else {
                        scan(id, result)
                    }
                }
                "cancel" -> {
                    if (pending?.id == call.argument<String>("id")) cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scan(id: String, result: MethodChannel.Result) {
        if (pending != null || activity.isFinishing || activity.isDestroyed) {
            result.error("scan_unavailable", "The document scanner is unavailable.", null)
            return
        }
        if (nextRequestCode > 65535) {
            result.error("scan_unavailable", "Restart the app before scanning again.", null)
            return
        }
        val request = PendingScan(id, nextRequestCode++, result)
        pending = request
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setPageLimit(1)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
        try {
            GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                .addOnSuccessListener { intentSender ->
                    if (pending !== request) return@addOnSuccessListener
                    try {
                        request.launched = true
                        activity.startIntentSenderForResult(
                            intentSender, request.requestCode, null, 0, 0, 0,
                        )
                    } catch (_: Exception) {
                        fail(request, "scan_unavailable")
                    }
                }
                .addOnFailureListener { error ->
                    val unsupported = error is MlKitException && error.errorCode == MlKitException.UNSUPPORTED
                    fail(request, if (unsupported) "scan_unsupported" else "scan_unavailable")
                }
        } catch (_: Exception) {
            fail(request, "scan_unavailable")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val request = pending
        if (request == null || request.requestCode != requestCode) return false
        request.launched = false
        if (resultCode == Activity.RESULT_CANCELED) {
            pending = null
            request.result.success(null)
            return true
        }
        if (resultCode != Activity.RESULT_OK) {
            fail(request, "scan_failed")
            return true
        }
        val uri = try {
            GmsDocumentScanningResult.fromActivityResultIntent(data)?.pages?.singleOrNull()?.imageUri
        } catch (_: Exception) {
            null
        }
        if (uri == null) {
            fail(request, "scan_failed")
            return true
        }
        reader.execute {
            try {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size().toLong() + count > 18L * 1024 * 1024) {
                            throw ScanTooLargeException()
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalStateException()
                activity.runOnUiThread {
                    if (pending === request) {
                        pending = null
                        request.result.success(bytes)
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    fail(request, if (error is ScanTooLargeException) "scan_too_large" else "scan_failed")
                }
            }
        }
        return true
    }

    private fun fail(request: PendingScan, code: String) {
        if (pending !== request) return
        pending = null
        request.result.error(code, "Google document scanning could not finish.", null)
    }

    private fun cancel() {
        val request = pending ?: return
        pending = null
        if (request.launched) activity.finishActivity(request.requestCode)
        request.result.error("scan_cancelled", "Document scanning was cancelled.", null)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        cancel()
        reader.shutdown()
    }
}
