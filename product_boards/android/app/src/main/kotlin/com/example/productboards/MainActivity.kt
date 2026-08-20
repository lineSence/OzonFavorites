package com.example.productboards

import android.content.Intent
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
        webView.alpha = 0f
        webView.layoutParams = FrameLayout.LayoutParams(720, 1280)
        webView.isVerticalScrollBarEnabled = false
        webView.isHorizontalScrollBarEnabled = false

        (findViewById<FrameLayout>(android.R.id.content))?.addView(webView)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                browserFinalUrl = url ?: browserFinalUrl
                logBrowserEvent("PAGE_STARTED", mapOf(
                    "url" to url,
                    "title" to view?.title,
                ))
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                browserFinalUrl = view?.url ?: url ?: browserFinalUrl
                browserPageTitle = view?.title
                logBrowserEvent("PAGE_FINISHED", mapOf(
                    "url" to browserFinalUrl,
                    "title" to browserPageTitle,
                    "attempt" to browserAttempt,
                ))
                browserHandler.postDelayed({ extractBrowserData(webView) }, 2200L)
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
                ))
                finishBrowserResolve(null, "timeout")
            }
        }, 20000L)

        try {
            webView.loadUrl(request.url)
            logBrowserEvent("LOAD_URL", mapOf("url" to request.url))
        } catch (error: Exception) {
            logBrowserEvent("LOAD_URL_EXCEPTION", mapOf(
                "url" to request.url,
                "error" to error.toString(),
            ))
            finishBrowserResolve(null, "loadUrl_exception")
        }
    }

    private fun logBrowserEvent(stage: String, details: Map<String, Any?> = emptyMap()) {
        val event = linkedMapOf<String, Any?>(
            "stage" to stage,
            "timestampMs" to System.currentTimeMillis(),
        )
        event.putAll(details)
        browserEvents.add(event)
        if (browserEvents.size > 200) browserEvents.removeAt(0)
    }

    private fun extractBrowserData(webView: WebView) {
        if (browserFinished) return
        browserAttempt++
        logBrowserEvent("JS_EXTRACT_START", mapOf(
            "attempt" to browserAttempt,
            "url" to webView.url,
            "title" to webView.title,
        ))

        val script = """
            (function() {
              const clean = v => v == null ? null : String(v).replace(/\\s+/g, ' ').trim();
              const host = location.host.toLowerCase();
              const isAvito = host.includes('avito');
              const meta = name => {
                const a = document.querySelector('meta[property="' + name + '"]');
                const b = document.querySelector('meta[name="' + name + '"]');
                return clean((a || b)?.content);
              };
              const normalizeUrl = v => {
                if (!v) return null;
                v = String(v).trim().replace(/\\u002F/g, '/').replace(/\\\\\//g, '/');
                if (v.startsWith('//')) v = location.protocol + v;
                return /^https?:\\/\\//i.test(v) ? v : null;
              };
              const genericImage = v => {
                if (!v) return true;
                const s = String(v).toLowerCase();
                if (/(logo|favicon|sprite|avatar|placeholder|brand)/i.test(s)) return true;
                if (isAvito && /(avito\\.(?:ru|st)|static|cdn).*?(logo|favicon|brand)/i.test(s)) return true;
                return false;
              };
              const attrs = el => {
                if (!el) return null;
                for (const k of ['src','data-src','data-original','data-lazy-src','content','href']) {
                  const v = normalizeUrl(el.getAttribute(k));
                  if (v && !genericImage(v)) return v;
                }
                const srcset = el.getAttribute('srcset') || el.getAttribute('data-srcset');
                if (srcset) {
                  for (const part of srcset.split(',')) {
                    const v = normalizeUrl(part.trim().split(/\\s+/)[0]);
                    if (v && !genericImage(v)) return v;
                  }
                }
                return null;
              };
              const visible = el => {
                if (!el) return false;
                const r = el.getBoundingClientRect();
                return r.width >= 80 && r.height >= 80;
              };
              const textOf = selector => {
                const el = document.querySelector(selector);
                return clean(el?.innerText || el?.textContent);
              };

              let title = meta('og:title') || meta('twitter:title');
              const titleSelectors = host.includes('wildberries')
                ? ['h1[class*="product-page"]','h1[class*="ProductCard"]','h1']
                : ['[data-widget="webProductHeading"] h1','[data-widget="webProductHeading"] h2','h1'];
              for (const selector of titleSelectors) {
                if (!title) title = textOf(selector);
              }
              if (!title) title = clean(document.title);

              let image = genericImage(meta('og:image')) ? null : meta('og:image');
              if (!image) image = genericImage(meta('twitter:image')) ? null : meta('twitter:image');
              if (!image) image = attrs(document.querySelector('[itemprop="image"]'));
              const imageSelectors = isAvito
                ? ['[data-marker*="item"] img','[class*="gallery"] img','[class*="photo"] img','picture img','img']
                : host.includes('wildberries')
                  ? ['[class*="photo"] img','[class*="productCard"] img','picture img','img']
                  : ['[data-widget*="Gallery"] img','[class*="gallery"] img','picture img','img'];
              if (!image) {
                for (const selector of imageSelectors) {
                  for (const el of document.querySelectorAll(selector)) {
                    if (!visible(el) && selector.endsWith('img')) continue;
                    const src = attrs(el);
                    if (src) {
                      image = src;
                      break;
                    }
                  }
                  if (image) break;
                }
              }

              let currency = meta('product:price:currency') || (host.includes('wildberries') || isAvito ? 'RUB' : null);
              let price = null;
              const priceSelectors = isAvito
                ? ['[itemprop="price"]','[data-marker*="item-price"]','[data-marker*="price"]','[class*="price"]']
                : host.includes('wildberries')
                  ? ['[class*="price-block"]','[class*="priceBlock"]','[class*="price"]','[data-testid*="price"]']
                  : ['[data-widget*="price"]','[class*="price"]','[data-testid*="price"]'];
              const priceTexts = [];
              for (const selector of priceSelectors) {
                for (const el of document.querySelectorAll(selector)) {
                  const t = clean(el.innerText || el.textContent);
                  if (t && /\\d/.test(t)) priceTexts.push(t);
                  if (priceTexts.length >= 20) break;
                }
                if (priceTexts.length >= 20) break;
              }
              const bodyText = clean(document.body?.innerText || '');
              const scriptText = Array.from(document.scripts).map(s => s.textContent || '').join(' ');
              const allText = priceTexts.join(' ') + ' ' + bodyText.slice(0, 120000) + ' ' + scriptText.slice(0, 250000);

              const rubPatterns = [
                /([0-9][0-9\\s\\u00a0\\u202f,.]*)\\s*(?:₽|руб\\.?|RUB)\\b/i,
                /(?:₽|руб\\.?|RUB)\\s*([0-9][0-9\\s\\u00a0\\u202f,.]*)/i
              ];
              const quotedPatterns = [
                /["'](?:price|currentPrice|salePrice|finalPrice)["']\\s*:\\s*["']?([0-9][0-9\\s.,\\u00a0\\u202f]*)/i,
                /["']priceFormatted["']\\s*:\\s*["']([^"']+)["']/i
              ];
              let candidate = null;
              for (const re of rubPatterns) {
                const m = allText.match(re);
                if (m) { candidate = m[1]; break; }
              }
              if (!candidate) {
                for (const re of quotedPatterns) {
                  const m = allText.match(re);
                  if (m) { candidate = m[1]; break; }
                }
              }
              if (candidate) {
                const normalized = candidate.replace(/[\\s\\u00a0\\u202f]/g, '').replace(/(?<=\\d),(?=\\d)/g, '.').replace(/[^0-9.]/g, '');
                const parsed = parseFloat(normalized);
                if (!Number.isNaN(parsed) && parsed > 0 && parsed < 100000000) price = parsed;
              }

              return JSON.stringify({
                title,
                imageUrl:image,
                price,
                currency,
                description:meta('og:description') || meta('twitter:description'),
                host,
                finalUrl:location.href,
                pageTitle:clean(document.title),
                readyState:document.readyState,
                bodyLength:document.body?.innerText?.length || 0,
                scriptCount:document.scripts?.length || 0,
              });
            })();
        """.trimIndent()

        try {
            webView.evaluateJavascript("window.scrollTo(0, Math.min(document.body.scrollHeight, 1400)); $script") { rawResult ->
                browserHandler.post {
                    try {
                        if (rawResult.isNullOrBlank() || rawResult == "null") {
                            logBrowserEvent("JS_RESULT_EMPTY", mapOf("attempt" to browserAttempt, "url" to webView.url))
                            scheduleRetryOrFinish(webView, null, "js_empty")
                            return@post
                        }
                        val jsonString = JSONTokener(rawResult).nextValue()
                        val json = if (jsonString is String) org.json.JSONObject(jsonString) else null
                        if (json == null) {
                            logBrowserEvent("JS_JSON_INVALID", mapOf("attempt" to browserAttempt, "rawLength" to rawResult.length))
                            scheduleRetryOrFinish(webView, null, "js_json_invalid")
                            return@post
                        }
                        browserFinalUrl = json.optString("finalUrl", null) ?: webView.url ?: browserFinalUrl
                        browserPageTitle = json.optString("pageTitle", null) ?: webView.title ?: browserPageTitle
                        val price = if (json.has("price") && !json.isNull("price")) json.getDouble("price") else null
                        val result = mapOf<String, Any?>(
                            "title" to json.optString("title", null),
                            "imageUrl" to json.optString("imageUrl", null),
                            "price" to price,
                            "currency" to json.optString("currency", null),
                            "description" to json.optString("description", null),
                        )
                        logBrowserEvent("JS_RESULT", mapOf(
                            "attempt" to browserAttempt,
                            "finalUrl" to browserFinalUrl,
                            "pageTitle" to browserPageTitle,
                            "title" to result["title"],
                            "imageUrl" to result["imageUrl"],
                            "price" to result["price"],
                            "currency" to result["currency"],
                            "readyState" to json.optString("readyState", null),
                            "bodyLength" to json.optInt("bodyLength", 0),
                            "scriptCount" to json.optInt("scriptCount", 0),
                        ))
                        val hasUsefulData = result.values.any { it != null && it.toString().isNotBlank() && it.toString() != "null" }
                        if (!hasUsefulData && browserAttempt < 3) {
                            browserHandler.postDelayed({ extractBrowserData(webView) }, 1800L)
                        } else {
                            finishBrowserResolve(result, if (hasUsefulData) "success" else "no_data")
                        }
                    } catch (error: Exception) {
                        logBrowserEvent("JS_PARSE_EXCEPTION", mapOf(
                            "attempt" to browserAttempt,
                            "error" to error.toString(),
                            "url" to webView.url,
                        ))
                        scheduleRetryOrFinish(webView, null, "js_parse_exception")
                    }
                }
            }
        } catch (error: Exception) {
            logBrowserEvent("JS_EVALUATE_EXCEPTION", mapOf(
                "attempt" to browserAttempt,
                "error" to error.toString(),
                "url" to webView.url,
            ))
            scheduleRetryOrFinish(webView, null, "js_evaluate_exception")
        }
    }

    private fun scheduleRetryOrFinish(webView: WebView, data: Map<String, Any?>?, reason: String) {
        if (browserFinished) return
        if (browserAttempt < 3) {
            browserHandler.postDelayed({ extractBrowserData(webView) }, 1800L)
        } else {
            finishBrowserResolve(data, reason)
        }
    }

    private fun finishBrowserResolve(data: Map<String, Any?>?, reason: String) {
        if (browserFinished) return
        browserFinished = true
        val request = activeBrowserRequest
        val payload = linkedMapOf<String, Any?>()
        if (data != null) payload.putAll(data)
        payload["originalUrl"] = request?.url
        payload["finalUrl"] = browserFinalUrl ?: activeBrowser?.url
        payload["pageTitle"] = browserPageTitle ?: activeBrowser?.title
        payload["reason"] = reason
        payload["attempts"] = browserAttempt
        payload["diagnostics"] = browserEvents.toList()
        logBrowserEvent("FINISH", mapOf(
            "reason" to reason,
            "originalUrl" to request?.url,
            "finalUrl" to payload["finalUrl"],
            "pageTitle" to payload["pageTitle"],
            "attempts" to browserAttempt,
        ))
        payload["diagnostics"] = browserEvents.toList()

        activeBrowser?.stopLoading()
        (activeBrowser?.parent as? FrameLayout)?.removeView(activeBrowser)
        activeBrowser?.destroy()
        activeBrowser = null
        request?.result?.success(payload)
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
