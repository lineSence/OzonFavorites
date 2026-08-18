package com.example.productboards

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import org.json.JSONTokener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private val channelName = "product_boards/share"
    private var channel: MethodChannel? = null
    private var pendingSharedData: Map<String, String?>? = null

    private val browserHandler = Handler(Looper.getMainLooper())
    private val browserQueue = ArrayDeque<BrowserRequest>()
    private var activeBrowserRequest: BrowserRequest? = null
    private var activeBrowser: WebView? = null
    private var browserFinished = false

    private data class BrowserRequest(
        val url: String,
        val result: MethodChannel.Result,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedData" -> {
                    result.success(pendingSharedData)
                    pendingSharedData = null
                }
                "resolveProduct" -> {
                    val url = (call.arguments as? Map<*, *>)?.get("url")?.toString()
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "Missing product URL", null)
                    } else {
                        browserQueue.addLast(BrowserRequest(url, result))
                        startNextBrowserResolve()
                    }
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

    override fun onDestroy() {
        activeBrowser?.stopLoading()
        activeBrowser?.destroy()
        activeBrowser = null
        browserHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun handleIncomingIntent(intent: Intent?, notifyDart: Boolean) {
        if (intent?.action != Intent.ACTION_SEND) return
        val rawText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val extraTitle = intent.getStringExtra(Intent.EXTRA_TITLE)?.trim().orEmpty()
        val url = extractUrl(rawText) ?: extractUrl(extraTitle)
        if (url == null) return

        val title = extraTitle.takeIf { it.isNotEmpty() }
            ?: extractTitle(rawText, url)
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

    private fun startNextBrowserResolve() {
        if (activeBrowserRequest != null || browserQueue.isEmpty()) return
        activeBrowserRequest = browserQueue.removeFirst()
        browserFinished = false

        val request = activeBrowserRequest ?: return
        val webView = WebView(this)
        activeBrowser = webView
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.loadsImagesAutomatically = true
        webView.settings.userAgentString = "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36"
        webView.alpha = 0f
        webView.layoutParams = FrameLayout.LayoutParams(1, 1)

        (findViewById<FrameLayout>(android.R.id.content))?.addView(webView)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                browserHandler.postDelayed({ extractBrowserData(webView) }, 1800L)
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean = false
        }

        browserHandler.postDelayed({
            if (!browserFinished) finishBrowserResolve(null)
        }, 15000L)

        webView.loadUrl(request.url)
    }

    private fun extractBrowserData(webView: WebView) {
        if (browserFinished) return
        val script = """
            (function() {
              const clean = v => v == null ? null : String(v).replace(/\\s+/g, ' ').trim();
              const meta = name => {
                const a = document.querySelector('meta[property="' + name + '"]');
                const b = document.querySelector('meta[name="' + name + '"]');
                return clean((a || b)?.content);
              };
              const attrs = el => {
                if (!el) return null;
                for (const k of ['src','data-src','data-original','content','href']) {
                  const v = el.getAttribute(k);
                  if (v && /^https?:\\/\\//i.test(v)) return v;
                }
                const srcset = el.getAttribute('srcset');
                if (srcset) {
                  const first = srcset.split(',')[0].trim().split(' ')[0];
                  if (/^https?:\\/\\//i.test(first)) return first;
                }
                return null;
              };
              let title = meta('og:title') || meta('twitter:title') || clean(document.querySelector('[data-widget="webProductHeading"] h1')?.innerText) || clean(document.querySelector('h1')?.innerText) || clean(document.title);
              let image = meta('og:image') || meta('twitter:image') || attrs(document.querySelector('[itemprop="image"]'));
              if (!image) {
                for (const img of document.images) {
                  const src = attrs(img);
                  if (src) { image = src; break; }
                }
              }
              let currency = meta('product:price:currency');
              let price = null;
              const priceText = meta('product:price:amount') || clean(document.querySelector('[data-widget*="price" i]')?.innerText) || clean(document.body?.innerText);
              const scriptText = Array.from(document.scripts).map(s => s.textContent || '').join(' ');
              const allText = (priceText || '') + ' ' + scriptText;
              const rub = allText.match(/([0-9][0-9\\s\\u00a0\\u202f,.]*)\\s*(?:₽|руб\\.?|RUB)\\b/i);
              const quoted = allText.match(/(?:"price"|"currentPrice"|"salePrice")\\s*:\s*"?([0-9][0-9\\s.,\\u00a0\\u202f]*)/i);
              const candidate = rub ? rub[1] : (quoted ? quoted[1] : null);
              if (candidate) {
                const normalized = candidate.replace(/[\\s\\u00a0\\u202f]/g, '').replace(',', '.');
                const parsed = parseFloat(normalized);
                if (!Number.isNaN(parsed) && parsed > 0) price = parsed;
                if (!currency && rub) currency = 'RUB';
              }
              return JSON.stringify({title, imageUrl:image, price, currency, description:meta('og:description') || meta('twitter:description')});
            })();
        """.trimIndent()

        webView.evaluateJavascript(script) { rawResult ->
            try {
                val jsonString = JSONTokener(rawResult ?: "null").nextValue()
                val json = if (jsonString is String) org.json.JSONObject(jsonString) else null
                val result = if (json != null) {
                    val price = if (json.has("price") && !json.isNull("price")) json.getDouble("price") else null
                    mapOf(
                        "title" to json.optString("title", null),
                        "imageUrl" to json.optString("imageUrl", null),
                        "price" to price,
                        "currency" to json.optString("currency", null),
                        "description" to json.optString("description", null),
                    )
                } else null
                finishBrowserResolve(result)
            } catch (_: Exception) {
                finishBrowserResolve(null)
            }
        }
    }

    private fun finishBrowserResolve(data: Map<String, Any?>?) {
        if (browserFinished) return
        browserFinished = true
        activeBrowser?.stopLoading()
        (activeBrowser?.parent as? FrameLayout)?.removeView(activeBrowser)
        activeBrowser?.destroy()
        activeBrowser = null
        activeBrowserRequest?.result?.success(data)
        activeBrowserRequest = null
        browserHandler.removeCallbacksAndMessages(null)
        startNextBrowserResolve()
    }

    private fun extractUrl(text: String): String? {
        val regex = Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE)
        return regex.find(text)?.value?.trimEnd('.', ',', ';', ')', ']', '}')
    }

    @Suppress("DEPRECATION")
    private fun getParcelableExtra(intent: Intent): Uri? =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
}
