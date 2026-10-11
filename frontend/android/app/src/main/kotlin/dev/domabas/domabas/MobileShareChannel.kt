package dev.domabas.domabas

import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.widget.Toast
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

class MobileShareChannel(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dev.domabas/mobile_share")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val stream = AtomicReference<InputStream?>()
    private var cancellation = CancellationSignal()
    private val root = File(File(activity.cacheDir, "shared-documents"), UUID.randomUUID().toString())
    private var batch: Map<String, Any?>? = null
    private var currentId: String? = null
    private var scope: Map<*, *>? = null
    private var batchScope: Map<*, *>? = null
    @Volatile private var closed = false
    @Volatile private var cancelled = false

    init {
        worker.execute {
            root.parentFile?.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 24 * 60 * 60 * 1000L }
                ?.forEach { it.deleteRecursively() }
            root.mkdirs()
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSession" -> {
                    val next = call.arguments as? Map<*, *>
                    if (batchScope != null && batchScope != next && currentId != null) {
                        cancelled = true
                        cancellation.cancel()
                        try { stream.getAndSet(null)?.close() } catch (_: Exception) { }
                        if (batch != null) {
                            workerCleanup(File(root, currentId!!))
                            publish(currentId!!, emptyList(), "Your session or library changed. Share these files again to choose a destination.")
                        }
                    }
                    scope = next
                    result.success(null)
                }
                "pending" -> result.success(batch)
                "release" -> {
                    if (call.arguments == currentId && batch != null) {
                        val directory = File(root, currentId!!)
                        batch = null
                        currentId = null
                        worker.execute { directory.deleteRecursively() }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    fun receive(intent: Intent?) {
        if (intent?.action !in setOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        val uris = try {
            if (intent?.action == Intent.ACTION_SEND_MULTIPLE) {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.toList()
            } else {
                intent?.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { listOf(it) }
            } ?: intent?.clipData?.let { clip ->
                if (clip.itemCount > 20) emptyList() else (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
            } ?: emptyList()
        } catch (_: RuntimeException) { emptyList() }
        intent?.action = Intent.ACTION_MAIN
        intent?.removeExtra(Intent.EXTRA_STREAM)
        intent?.clipData = null
        if (closed) return
        if (currentId != null) {
            Toast.makeText(activity, "Finish or discard the previous shared files, then share again.", Toast.LENGTH_LONG).show()
            return
        }
        val id = UUID.randomUUID().toString()
        currentId = id
        batchScope = scope
        if (uris.isEmpty() || uris.size > 20 || uris.any { it.scheme != "content" || it.authority?.startsWith(activity.packageName) == true }) {
            publish(id, emptyList(), "Share up to 20 PDF, PNG or JPEG files using the source app's Share action.")
            return
        }
        cancelled = false
        cancellation = CancellationSignal()
        val deadline = Runnable {
            cancelled = true
            cancellation.cancel()
            try { stream.getAndSet(null)?.close() } catch (_: Exception) { }
        }
        main.postDelayed(deadline, 120_000)
        worker.execute {
            val directory = File(root, id)
            try {
                check(directory.mkdirs())
                var total = 0L
                val paths = uris.mapIndexed { index, uri ->
                    check(!closed && !cancelled)
                    val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null, cancellation)?.use {
                        if (it.moveToFirst()) it.getString(0) else null
                    } ?: "document"
                    val folder = File(directory, index.toString())
                    check(folder.mkdirs())
                    val file = File(folder, safeName(name))
                    activity.contentResolver.openAssetFileDescriptor(uri, "r", cancellation)?.use { descriptor ->
                        descriptor.createInputStream().use { input ->
                            stream.set(input)
                            file.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                var size = 0L
                                while (true) {
                                    check(!closed && !cancelled)
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    size += count
                                    total += count
                                    require(size <= 100L * 1024 * 1024 && total <= 200L * 1024 * 1024)
                                    output.write(buffer, 0, count)
                                }
                                require(size > 0)
                            }
                        }
                    } ?: error("unavailable")
                    stream.set(null)
                    val prefix = file.inputStream().use { input -> ByteArray(8).also { input.read(it) } }
                    require(supported(prefix))
                    file.absolutePath
                }
                main.post {
                    main.removeCallbacks(deadline)
                    if (!closed && !cancelled) publish(id, paths, null)
                    else {
                        workerCleanup(directory)
                        if (!closed) publish(id, emptyList(), "The source app stopped responding. Download the files there and share again.")
                    }
                }
            } catch (_: Exception) {
                stream.set(null)
                directory.deleteRecursively()
                main.post {
                    main.removeCallbacks(deadline)
                    if (!closed) publish(id, emptyList(), "No files were uploaded. Share readable PDF, PNG or JPEG files up to 100 MiB each and 200 MiB in total. Download cloud files first.")
                }
            }
        }
    }

    private fun publish(id: String, paths: List<String>, error: String?) {
        if (closed || currentId != id) return
        batch = mapOf("id" to id, "paths" to paths, "error" to error)
        channel.invokeMethod("changed", null)
    }

    private fun workerCleanup(directory: File) {
        if (!worker.isShutdown) worker.execute { directory.deleteRecursively() }
    }

    fun close() {
        closed = true
        cancelled = true
        channel.setMethodCallHandler(null)
        main.removeCallbacksAndMessages(null)
        cancellation.cancel()
        try { stream.getAndSet(null)?.close() } catch (_: Exception) { }
        worker.execute { root.deleteRecursively() }
        worker.shutdown()
    }

    companion object {
        fun supported(bytes: ByteArray): Boolean = listOf(
            byteArrayOf(37, 80, 68, 70, 45),
            byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10),
            byteArrayOf(-1, -40, -1),
        ).any { prefix -> bytes.size >= prefix.size && prefix.indices.all { prefix[it] == bytes[it] } }

        fun safeName(raw: String): String {
            val output = StringBuilder()
            var length = 0
            for (code in raw.codePoints().toArray()) {
                val part = if (code < 32 || code in 127..159 || code in listOf(34, 47, 92, 65533)) "_" else String(Character.toChars(code))
                val bytes = part.toByteArray(Charsets.UTF_8).size
                if (length + bytes > 255) break
                output.append(part)
                length += bytes
            }
            return output.toString().trim().takeUnless { it.isEmpty() || it == "." || it == ".." } ?: "document"
        }
    }
}
