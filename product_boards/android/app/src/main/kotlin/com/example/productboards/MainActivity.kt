package com.example.productboards

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
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
    private var browserAttempt = 0
    private val browserEvents = mutableListOf<Map<String, Any?>>()
    private var browserFinalUrl: String? = null
    private var browserPageTitle: String? = null
    private var browserScreenshotUri: String? = null

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
        browserAttempt = 0
        browserEvents.clear()
        browserFinalUrl = null
        browserPageTitle = null
        browserScreenshotUri = null

        val request = activeBrowserRequest ?: return
        logBrowserEvent("START", mapOf("originalUrl" to request.url))

        val webView = WebView(this)
        activeBrowser = webView
        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.loadsImagesAutomatically = true
        webView.settings.allowContentAccess = true
        webView.settings.allowFileAccess = true
        webView.settings.javaScriptCanOpenWindowsAutomatically = true
        webView.settings.cacheMode = WebSettings.LOAD_DEFAULT
        webView.settings.userAgentString = "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
        webView.setBackgroundColor(android.graphics.Color.WHITE)
        webView.alpha = 0f
        webView.layoutParams = FrameLayout.LayoutParams(900, 1600)
        webView.isVerticalScrollBarEnabled = false
        webView.isHorizontalScrollBarEnabled = false

        (findViewById<FrameLayout>(android.R.id.content))?.addView(webView)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                browserFinalUrl = url ?: browserFinalUrl
                logBrowserEvent("PAGE_STARTED", mapOf("url" to url, "title" to view?.title))
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                browserFinalUrl = view?.url ?: url ?: browserFinalUrl
                browserPageTitle = view?.title
                logBrowserEvent("PAGE_FINISHED", mapOf(
                    "url" to browserFinalUrl,
                    "title" to browserPageTitle,
                    "attempt" to browserAttempt,
                ))
                browserHandler.postDelayed({ captureAndExtract(webView) }, 1800L)
            }

            override fun onReceivedHttpError(view: WebView?, request: WebResourceRequest?, errorResponse: WebResourceResponse?) {
                if (request?.isForMainFrame == true) {
                    logBrowserEvent("MAIN_FRAME_HTTP_ERROR", mapOf(
                        "url" to request.url.toString(),
                        "status" to errorResponse?.statusCode,
                        "reason" to errorResponse?.reasonPhrase,
                        "contentType" to errorResponse?.mimeType,
                    ))
                }
            }

            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                if (request?.isForMainFrame == true) {
                    logBrowserEvent("MAIN_FRAME_LOAD_ERROR", mapOf(
                        "url" to request.url.toString(),
                        "code" to error?.errorCode,
                        "description" to error?.description?.toString(),
                    ))
                }
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                if (request != null) {
                    browserFinalUrl = request.url.toString()
                    logBrowserEvent("REDIRECT", mapOf(
                        "url" to request.url.toString(),
                        "isMainFrame" to request.isForMainFrame,
                    ))
                }
                return false
            }
        }

        browserHandler.postDelayed({
            if (!browserFinished) {
                logBrowserEvent("TIMEOUT", mapOf(
                    "originalUrl" to request.url,
                    "finalUrl" to browserFinalUrl,
                    "attempts" to browserAttempt,
                    "screenshotUri" to browserScreenshotUri,
                ))
                finishBrowserResolve(null, "timeout")
            }
        }, 20000L)

        try {
            webView.loadUrl(request.url)
            logBrowserEvent("LOAD_URL", mapOf("url" to request.url))
        } catch (error: Exception) {
            logBrowserEvent("LOAD_URL_EXCEPTION", mapOf("url" to request.url, "error" to error.toString()))
            finishBrowserResolve(null, "loadUrl_exception")
        }
    }

    private fun captureAndExtract(webView: WebView) {
        if (browserFinished) return
        browserAttempt++
        browserFinalUrl = webView.url ?: browserFinalUrl
        browserPageTitle = webView.title ?: browserPageTitle
        logBrowserEvent("SCREENSHOT_START", mapOf(
            "attempt" to browserAttempt,
            "url" to browserFinalUrl,
            "title" to browserPageTitle,
        ))

        val screenshotAllowed = isScreenshotAllowed(browserFinalUrl, browserPageTitle)
        if (screenshotAllowed) {
            prepareWebViewForScreenshot(webView)
        } else {
            logBrowserEvent("SCREENSHOT_SKIPPED", mapOf(
                "reason" to "error_or_antibot_page",
                "url" to browserFinalUrl,
                "title" to browserPageTitle,
            ))
        }

        val script = """
            (function() {
              const clean = v => v == null ? null : String(v).replace(/\\s+/g, ' ').trim();
              const host = location.host.toLowerCase();
              const meta = name => {
                const a = document.querySelector('meta[property="' + name + '"]');
                const b = document.querySelector('meta[name="' + name + '"]');
                return clean((a || b)?.content);
              };
              const textOf = selector => {
                const el = document.querySelector(selector);
                return clean(el?.innerText || el?.textContent);
              };
              let title = meta('og:title') || meta('twitter:title');
              for (const selector of ['[data-widget="webProductHeading"] h1','h1']) {
                if (!title) title = textOf(selector);
              }
              if (!title) title = clean(document.title);
              const currency = meta('product:price:currency') || 'RUB';
              const body = clean(document.body?.innerText || '');
              const scripts = Array.from(document.scripts).map(s => s.textContent || '').join(' ');
              const allText = (body.slice(0, 140000) + ' ' + scripts.slice(0, 200000));
              const patterns = [
                /([0-9][0-9\\s\\u00a0\\u202f,.]*)\\s*(?:₽|руб\\.?|RUB)\\b/i,
                /(?:₽|руб\\.?|RUB)\\s*([0-9][0-9\\s\\u00a0\\u202f,.]*)/i,
                /["'](?:price|currentPrice|salePrice|finalPrice)["']\\s*:\\s*["']?([0-9][0-9\\s.,\\u00a0\\u202f]*)/i
              ];
              let price = null;
              for (const re of patterns) {
                const m = allText.match(re);
                if (!m) continue;
                const normalized = String(m[1]).replace(/[\\s\\u00a0\\u202f]/g, '').replace(',', '.').replace(/[^0-9.]/g, '');
                const parsed = parseFloat(normalized);
                if (!Number.isNaN(parsed) && parsed > 0 && parsed < 100000000) { price = parsed; break; }
              }
              return JSON.stringify({
                title,
                price,
                currency,
                description: meta('og:description') || meta('twitter:description'),
                finalUrl: location.href,
                pageTitle: clean(document.title),
                readyState: document.readyState,
                bodyLength: document.body?.innerText?.length || 0
              });
            })();
        """.trimIndent()

        try {
            webView.evaluateJavascript(script) { rawResult ->
                browserHandler.post {
                    var title: String? = null
                    var price: Double? = null
                    var currency: String? = null
                    var description: String? = null
                    try {
                        if (!rawResult.isNullOrBlank() && rawResult != "null") {
                            val jsonString = JSONTokener(rawResult).nextValue()
                            if (jsonString is String) {
                                val json = org.json.JSONObject(jsonString)
                                title = json.optString("title", null)
                                price = if (json.has("price") && !json.isNull("price")) json.getDouble("price") else null
                                currency = json.optString("currency", null)
                                description = json.optString("description", null)
                                browserFinalUrl = json.optString("finalUrl", null) ?: browserFinalUrl
                                browserPageTitle = json.optString("pageTitle", null) ?: browserPageTitle
                                logBrowserEvent("JS_RESULT", mapOf(
                                    "attempt" to browserAttempt,
                                    "finalUrl" to browserFinalUrl,
                                    "pageTitle" to browserPageTitle,
                                    "title" to title,
                                    "price" to price,
                                    "currency" to currency,
                                    "bodyLength" to json.optInt("bodyLength", 0),
                                ))
                            }
                        } else {
                            logBrowserEvent("JS_RESULT_EMPTY", mapOf("attempt" to browserAttempt, "url" to webView.url))
                        }
                    } catch (error: Exception) {
                        logBrowserEvent("JS_PARSE_EXCEPTION", mapOf("attempt" to browserAttempt, "error" to error.toString()))
                    }

                    val payload = linkedMapOf<String, Any?>()
                    payload["title"] = title
                    payload["price"] = price
                    payload["currency"] = currency
                    payload["description"] = description
                    payload["originalUrl"] = activeBrowserRequest?.url
                    payload["finalUrl"] = browserFinalUrl ?: webView.url
                    payload["pageTitle"] = browserPageTitle ?: webView.title
                    payload["screenshotUri"] = browserScreenshotUri

                    val hasAnything = title != null || price != null || browserScreenshotUri != null
                    finishBrowserResolve(payload, if (hasAnything) "success" else "no_data")
                }
            }
        } catch (error: Exception) {
            logBrowserEvent("JS_EVALUATE_EXCEPTION", mapOf("attempt" to browserAttempt, "error" to error.toString()))
            val payload = mapOf<String, Any?>(
                "originalUrl" to activeBrowserRequest?.url?.toString(),
                "finalUrl" to (browserFinalUrl ?: webView.url),
                "pageTitle" to (browserPageTitle ?: webView.title),
                "screenshotUri" to browserScreenshotUri,
            )
            finishBrowserResolve(payload, if (browserScreenshotUri != null) "screenshot_only" else "js_exception")
        }
    }

    private fun prepareWebViewForScreenshot(webView: WebView) {
        val heightScript = """
            (function() {
              const height = Math.max(
                document.documentElement?.scrollHeight || 0,
                document.body?.scrollHeight || 0,
                document.documentElement?.offsetHeight || 0
              );
              return Math.min(Math.max(height, 1600), 2800);
            })();
        """.trimIndent()
        try {
            webView.evaluateJavascript(heightScript) { rawHeight ->
                val contentHeight = rawHeight?.toIntOrNull()?.coerceIn(1600, 2800) ?: 1600
                webView.post {
                    val params = webView.layoutParams as? FrameLayout.LayoutParams
                    if (params != null) {
                        params.width = 900
                        params.height = contentHeight
                        webView.layoutParams = params
                    }
                    logBrowserEvent("SCREENSHOT_LAYOUT", mapOf(
                        "width" to 900,
                        "height" to contentHeight,
                        "contentHeight" to rawHeight,
                    ))
                    webView.postDelayed({ browserScreenshotUri = captureWebViewScreenshot(webView) }, 250L)
                }
            }
        } catch (error: Exception) {
            logBrowserEvent("SCREENSHOT_LAYOUT_FAIL", mapOf("error" to error.toString()))
            browserScreenshotUri = captureWebViewScreenshot(webView)
        }
    }

    private fun isScreenshotAllowed(url: String?, title: String?): Boolean {
        val u = (url ?: "").lowercase()
        val t = (title ?: "").lowercase()
        if (u.isBlank()) return false
        val blockedTitle = listOf(
            "похоже, нет соединения",
            "antibot",
            "access denied",
            "robot",
            "captcha",
            "forbidden",
            "403",
        ).any { t.contains(it) }
        val blockedUrl = u.contains("captcha") || u.contains("challenge") || u.contains("blocked")
        return !blockedTitle && !blockedUrl
    }

    private fun captureWebViewScreenshot(webView: WebView): String? {
        return try {
            if (webView.width <= 0 || webView.height <= 0) {
                logBrowserEvent("SCREENSHOT_FAIL", mapOf("reason" to "invalid_view_size", "width" to webView.width, "height" to webView.height))
                return null
            }
            webView.scrollTo(0, 0)
            val bitmap = Bitmap.createBitmap(webView.width, webView.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            webView.draw(canvas)
            val file = File(cacheDir, "pinzon_screenshot_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)) {
                    logBrowserEvent("SCREENSHOT_FAIL", mapOf("reason" to "bitmap_compress_failed"))
                    bitmap.recycle()
                    return null
                }
                out.flush()
            }
            bitmap.recycle()
            logBrowserEvent("SCREENSHOT_SAVED", mapOf(
                "path" to file.absolutePath,
                "uri" to file.toURI().toString(),
                "width" to webView.width,
                "height" to webView.height,
                "bytes" to file.length(),
            ))
            file.toURI().toString()
        } catch (error: Exception) {
            logBrowserEvent("SCREENSHOT_FAIL", mapOf("error" to error.toString()))
            null
        }
    }

    private fun logBrowserEvent(stage: String, details: Map<String, Any?> = emptyMap()) {
        val event = linkedMapOf<String, Any?>("stage" to stage, "timestampMs" to System.currentTimeMillis())
        event.putAll(details)
        browserEvents.add(event)
        if (browserEvents.size > 200) browserEvents.removeAt(0)
    }

    private fun finishBrowserResolve(data: Map<String, Any?>?, reason: String) {
        if (browserFinished) return
        browserFinished = true
        val request = activeBrowserRequest
        val payload = linkedMapOf<String, Any?>()
        if (data != null) payload.putAll(data)
        payload["originalUrl"] = payload["originalUrl"] ?: request?.url
        payload["finalUrl"] = payload["finalUrl"] ?: browserFinalUrl ?: activeBrowser?.url
        payload["pageTitle"] = payload["pageTitle"] ?: browserPageTitle ?: activeBrowser?.title
        payload["reason"] = reason
        payload["attempts"] = browserAttempt
        payload["screenshotUri"] = payload["screenshotUri"] ?: browserScreenshotUri
        payload["diagnostics"] = browserEvents.toList()
        logBrowserEvent("FINISH", mapOf(
            "reason" to reason,
            "finalUrl" to payload["finalUrl"],
            "title" to payload["title"],
            "price" to payload["price"],
            "screenshotUri" to payload["screenshotUri"],
        ))

        try {
            request?.result?.success(payload)
        } catch (_: Exception) {
        }

        activeBrowser?.let { view ->
            (view.parent as? FrameLayout)?.removeView(view)
            view.stopLoading()
            view.destroy()
        }
        activeBrowser = null
        activeBrowserRequest = null
        browserHandler.post { startNextBrowserResolve() }
    }

    private fun getParcelableExtra(intent: Intent): Uri? {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun extractUrl(text: String): String? {
        if (text.isBlank()) return null
        val match = Regex("https?://[^\\s<>]+", RegexOption.IGNORE_CASE).find(text)
        return match?.value?.trimEnd('.', ',', ';', ')', ']', '}')
    }
}
