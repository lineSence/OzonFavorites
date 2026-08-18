package com.example.productboards

import android.content.Intent
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "product_boards/share"
    private var channel: MethodChannel? = null
    private var pendingSharedData: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedData" -> {
                    result.success(pendingSharedData)
                    pendingSharedData = null
                }
                else -> result.notImplemented()
            }
        }
        handleIncomingIntent(intent, notifyDart = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, notifyDart = true)
    }

    private fun handleIncomingIntent(intent: Intent?, notifyDart: Boolean) {
        if (intent?.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val url = extractUrl(text) ?: return
        val title = intent.getStringExtra(Intent.EXTRA_TITLE)?.trim()?.takeIf { it.isNotEmpty() }
            ?: extractTitle(text, url)
        val imagePath = copySharedImage(intent)
        pendingSharedData = mapOf("url" to url, "title" to title, "imagePath" to imagePath)
        if (notifyDart) channel?.invokeMethod("sharedData", pendingSharedData)
    }

    private fun extractTitle(text: String, url: String): String? {
        val before = text.substringBefore(url).trim().trim('-', '—', ':', ' ', '\n')
        return before.takeIf { it.length >= 3 && !it.equals("Поделиться", ignoreCase = true) }
    }

    private fun copySharedImage(intent: Intent): String? {
        val uri = getParcelableExtra(intent) ?: return null
        return try {
            val mime = contentResolver.getType(uri) ?: "image/jpeg"
            val ext = when {
                mime.contains("png") -> "png"
                mime.contains("webp") -> "webp"
                mime.contains("gif") -> "gif"
                else -> "jpg"
            }
            val file = File(cacheDir, "shared_${System.currentTimeMillis()}.$ext")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(file).use { output -> input.copyTo(output) }
            }
            file.toURI().toString()
        } catch (_: Exception) { null }
    }

    private fun extractUrl(text: String): String? {
        val regex = Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE)
        return regex.find(text)?.value?.trimEnd('.', ',', ';', ')', ']', '}')
    }

    /**
     * getParcelableExtra(Uri::class.java) доступен только с API 33,
     * поэтому для старых версий используется deprecated-перегрузка.
     */
    @Suppress("DEPRECATION")
    private fun getParcelableExtra(intent: Intent): Uri? =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
}
