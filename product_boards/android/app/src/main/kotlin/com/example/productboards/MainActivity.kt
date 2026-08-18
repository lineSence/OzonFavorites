package com.example.productboards

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "product_boards/share"
    private var channel: MethodChannel? = null
    private var pendingSharedUrl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedUrl" -> {
                    result.success(pendingSharedUrl)
                    pendingSharedUrl = null
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
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim() ?: return
        val url = extractUrl(text) ?: return
        pendingSharedUrl = url
        if (notifyDart) channel?.invokeMethod("sharedUrl", url)
    }

    private fun extractUrl(text: String): String? {
        val regex = Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE)
        return regex.find(text)?.value?.trimEnd('.', ',', ';', ')', ']', '}')
    }
}
