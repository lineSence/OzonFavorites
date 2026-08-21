package com.example.productboards

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONTokener
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private val channelName = "product_boards/share"
    private var channel: MethodChannel? = null
    private var pendingSharedData: Map<String, String?>? = null
    private val handler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<Request>()
    private var active: Request? = null
    private var webView: WebView? = null
    private var finished = false
    private var attempt = 0
    private val events = mutableListOf<Map<String, Any?>>()
    private var finalUrl: String? = null
    private var pageTitle: String? = null
    private var screenshotUri: String? = null

    private data class Request(val url: String, val result: MethodChannel.Result)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedData" -> { result.success(pendingSharedData); pendingSharedData = null }
                "resolveProduct" -> {
                    val url = (call.arguments as? Map<*, *>)?.get("url")?.toString()?.trim()
                    if (url.isNullOrEmpty()) result.error("INVALID_URL", "Missing product URL", null)
                    else { queue.addLast(Request(url, result)); startNext() }
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent, false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, true)
    }

    override fun onDestroy() {
        cleanupWebView()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun handleIntent(intent: Intent?, notify: Boolean) {
        if (intent?.action != Intent.ACTION_SEND) return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val extraTitle = intent.getStringExtra(Intent.EXTRA_TITLE)?.trim().orEmpty()
        val url = extractUrl(text) ?: extractUrl(extraTitle) ?: return
        val title = extraTitle.takeIf { it.isNotEmpty() } ?: text.substringBefore(url).trim().trim('-', '—', ':', ' ', '\n').takeIf { it.length >= 3 }
        val imagePath = copySharedImage(intent)
        pendingSharedData = mapOf("url" to url, "title" to title, "imagePath" to imagePath)
        if (notify) channel?.invokeMethod("sharedData", pendingSharedData)
    }

    private fun copySharedImage(intent: Intent): String? {
        val uri = getStreamUri(intent) ?: return null
        return try {
            val mime = contentResolver.getType(uri) ?: "image/jpeg"
            val ext = when {
                mime.contains("png") -> "png"
                mime.contains("webp") -> "webp"
                mime.contains("gif") -> "gif"
                else -> "jpg"
            }
            val file = File(cacheDir, "shared_${System.currentTimeMillis()}.$ext")
            contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(file).use { output -> input.copyTo(output) } }
            file.toURI().toString()
        } catch (_: Exception) { null }
    }

    private fun startNext() {
        if (active != null || queue.isEmpty()) return
        active = queue.removeFirst()
        finished = false
        attempt = 0
        events.clear()
        finalUrl = null
        pageTitle = null
        screenshotUri = null

        val request = active ?: return
        val view = WebView(this)
        webView = view
        CookieManager.getInstance().apply { setAcceptCookie(true); setAcceptThirdPartyCookies(view, true) }
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            loadsImagesAutomatically = true
            allowContentAccess = true
            allowFileAccess = true
            javaScriptCanOpenWindowsAutomatically = true
            cacheMode = WebSettings.LOAD_DEFAULT
            userAgentString = "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36"
        }
        view.setBackgroundColor(android.graphics.Color.WHITE)
        view.alpha = 1f
        view.translationX = -10000f
        view.translationY = -10000f
        view.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
        view.layoutParams = FrameLayout.LayoutParams(900, 1600)
        view.isVerticalScrollBarEnabled = false
        view.isHorizontalScrollBarEnabled = false
        findViewById<FrameLayout>(android.R.id.content)?.addView(view)

        view.webViewClient = object : WebViewClient() {
            override fun onPageStarted(v: WebView?, url: String?, favicon: Bitmap?) { finalUrl = url ?: finalUrl; log("PAGE_STARTED", mapOf("url" to url)) }
            override fun onPageFinished(v: WebView?, url: String?) {
                finalUrl = v?.url ?: url ?: finalUrl
                pageTitle = v?.title
                log("PAGE_FINISHED", mapOf("url" to finalUrl, "title" to pageTitle))
                handler.postDelayed({ captureAndExtract(view) }, 1800L)
            }
            override fun onReceivedHttpError(v: WebView?, r: WebResourceRequest?, e: WebResourceResponse?) { if (r?.isForMainFrame == true) log("MAIN_FRAME_HTTP_ERROR", mapOf("url" to r.url.toString(), "status" to e?.statusCode)) }
            override fun onReceivedError(v: WebView?, r: WebResourceRequest?, e: WebResourceError?) { if (r?.isForMainFrame == true) log("MAIN_FRAME_LOAD_ERROR", mapOf("url" to r.url.toString(), "code" to e?.errorCode)) }
        }
        handler.postDelayed({ if (!finished) finish(null, "timeout") }, 20000L)
        try { view.loadUrl(request.url); log("LOAD_URL", mapOf("url" to request.url)) } catch (_: Exception) { finish(null, "load_exception") }
    }

    private fun captureAndExtract(view: WebView) {
        if (finished) return
        attempt++
        finalUrl = view.url ?: finalUrl
        pageTitle = view.title ?: pageTitle
        if (isScreenshotAllowed(finalUrl, pageTitle)) {
            prepareWebViewForScreenshot(view) { screenshot ->
                screenshotUri = screenshot
                extractMetadataAndFinish(view)
            }
        } else {
            log("SCREENSHOT_SKIPPED", mapOf("url" to finalUrl, "title" to pageTitle))
            extractMetadataAndFinish(view)
        }
    }

    private fun extractMetadataAndFinish(view: WebView) {
        if (finished) return
        val script = """
            (function(){
              const clean=v=>v==null?null:String(v).replace(/\\s+/g,' ').trim();
              const meta=n=>{const a=document.querySelector('meta[property="'+n+'"]');const b=document.querySelector('meta[name="'+n+'"]');return clean((a||b)?.content)};
              let title=meta('og:title')||meta('twitter:title');
              for(const s of ['[data-widget="webProductHeading"] h1','h1']) if(!title){const e=document.querySelector(s);title=clean(e?.innerText||e?.textContent)}
              title=title||clean(document.title);
              const body=clean(document.body?.innerText||''); const scripts=Array.from(document.scripts).map(s=>s.textContent||'').join(' '); const text=(body.slice(0,140000)+' '+scripts.slice(0,200000));
              const patterns=[/([0-9][0-9\\s\\u00a0\\u202f,.]*)\\s*(?:₽|руб\\.?|RUB)\\b/i,/(?:₽|руб\\.?|RUB)\\s*([0-9][0-9\\s\\u00a0\\u202f,.]*)/i,/["'](?:price|currentPrice|salePrice|finalPrice)["']\\s*:\\s*["']?([0-9][0-9\\s.,\\u00a0\\u202f]*)/i];
              let price=null; for(const re of patterns){const m=text.match(re);if(!m)continue;const n=String(m[1]).replace(/[\\s\\u00a0\\u202f]/g,'').replace(',','.').replace(/[^0-9.]/g,'');const p=parseFloat(n);if(!Number.isNaN(p)&&p>0&&p<100000000){price=p;break}}
              return JSON.stringify({title,price,currency:meta('product:price:currency')||'RUB',description:meta('og:description')||meta('twitter:description'),finalUrl:location.href,pageTitle:clean(document.title)});
            })();
        """.trimIndent()
        try {
            view.evaluateJavascript(script) { raw -> handler.post {
                var title: String? = null; var price: Double? = null; var currency: String? = null; var description: String? = null
                try {
                    val value = if (!raw.isNullOrBlank() && raw != "null") JSONTokener(raw).nextValue() else null
                    if (value is String) {
                        val json = org.json.JSONObject(value)
                        title = json.optString("title", null); price = if (json.has("price") && !json.isNull("price")) json.getDouble("price") else null
                        currency = json.optString("currency", null); description = json.optString("description", null)
                        finalUrl = json.optString("finalUrl", null) ?: finalUrl; pageTitle = json.optString("pageTitle", null) ?: pageTitle
                    }
                } catch (_: Exception) {}
                finish(linkedMapOf("title" to title, "price" to price, "currency" to currency, "description" to description, "originalUrl" to active?.url, "finalUrl" to (finalUrl ?: view.url), "pageTitle" to (pageTitle ?: view.title), "screenshotUri" to screenshotUri), if (title != null || price != null || screenshotUri != null) "success" else "no_data")
            }}
        } catch (_: Exception) { finish(mapOf("screenshotUri" to screenshotUri, "finalUrl" to finalUrl, "pageTitle" to pageTitle), "js_exception") }
    }

    private fun isScreenshotAllowed(url: String?, title: String?): Boolean {
        val u = (url ?: "").lowercase(); val t = (title ?: "").lowercase()
        if (u.isBlank()) return false
        return listOf("captcha", "challenge", "access denied", "forbidden", "403", "antibot", "robot").none { u.contains(it) || t.contains(it) }
    }

    private fun prepareWebViewForScreenshot(view: WebView, callback: (String?) -> Unit) {
        val script = """(function(){return Math.min(Math.max(Math.max(document.documentElement?.scrollHeight||0,document.body?.scrollHeight||0,document.documentElement?.offsetHeight||0),1600),2800);})();"""
        try {
            view.evaluateJavascript(script) { raw ->
                val height = raw?.toIntOrNull()?.coerceIn(1600, 2800) ?: 1600
                view.post {
                    (view.layoutParams as? FrameLayout.LayoutParams)?.let { it.width = 900; it.height = height; view.layoutParams = it }
                    view.measure(View.MeasureSpec.makeMeasureSpec(900, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                    view.layout(0, 0, 900, height)
                    handler.postDelayed({ callback(captureScreenshot(view)) }, 250L)
                }
            }
        } catch (_: Exception) { callback(captureScreenshot(view)) }
    }

    private fun captureScreenshot(view: WebView): String? {
        try {
            if (view.width <= 0 || view.height <= 0) return null
            view.measure(View.MeasureSpec.makeMeasureSpec(view.width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(view.height, View.MeasureSpec.EXACTLY))
            view.layout(0, 0, view.width, view.height)
            view.scrollTo(0, 0)
            val oldAlpha = view.alpha
            view.alpha = 1f
            view.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
            view.invalidate()
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(android.graphics.Color.WHITE)
            view.draw(canvas)
            view.alpha = oldAlpha
            val file = File(cacheDir, "pinzon_screenshot_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)) {
                    bitmap.recycle()
                    return null
                }
                out.flush()
            }
            val bytes = file.length()
            bitmap.recycle()
            log("SCREENSHOT_SAVED", mapOf("uri" to file.toURI().toString(), "width" to view.width, "height" to view.height, "bytes" to bytes))
            return if (bytes > 4096) file.toURI().toString() else null
        } catch (error: Exception) {
            log("SCREENSHOT_FAILED", mapOf("error" to error.toString()))
            return null
        }
    }

    private fun log(stage: String, details: Map<String, Any?> = emptyMap()) {
        val event = linkedMapOf<String, Any?>("stage" to stage, "timestampMs" to System.currentTimeMillis())
        event.putAll(details)
        events.add(event)
        if (events.size > 200) events.removeAt(0)
    }

    private fun finish(data: Map<String, Any?>?, reason: String) {
        if (finished) return
        finished = true
        val request = active
        val payload = linkedMapOf<String, Any?>()
        if (data != null) payload.putAll(data)
        payload["originalUrl"] = payload["originalUrl"] ?: request?.url
        payload["finalUrl"] = payload["finalUrl"] ?: finalUrl ?: webView?.url
        payload["pageTitle"] = payload["pageTitle"] ?: pageTitle ?: webView?.title
        payload["reason"] = reason
        payload["attempts"] = attempt
        payload["screenshotUri"] = payload["screenshotUri"] ?: screenshotUri
        payload["diagnostics"] = events.toList()
        val result = request?.result
        cleanupWebView()
        active = null
        handler.removeCallbacksAndMessages(null)
        result?.success(payload)
        startNext()
    }

    private fun cleanupWebView() {
        webView?.stopLoading()
        (webView?.parent as? FrameLayout)?.removeView(webView)
        webView?.destroy()
        webView = null
    }

    private fun extractUrl(text: String): String? = Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE).find(text)?.value?.trimEnd('.', ',', ';', ')', ']', '}')

    @Suppress("DEPRECATION")
    private fun getStreamUri(intent: Intent): Uri? = if (android.os.Build.VERSION.SDK_INT >= 33) {
        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
    } else {
        intent.getParcelableExtra(Intent.EXTRA_STREAM)
    }
}
