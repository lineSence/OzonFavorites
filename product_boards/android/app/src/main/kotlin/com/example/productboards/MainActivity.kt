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
            val payload: Map<String, Any?> = mapOf(
                "originalUrl" to activeBrowserRequest?.url?.toString(),
                "finalUrl" to (browserFinalUrl ?: webView.url),
                "pageTitle" to (browserPageTitle ?: webView.title),
                "screenshotUri" to browserScreenshotUri,
            )
            finishBrowserResolve(payload, if (browserScreenshotUri != null) "screenshot_only" else "js_exception")
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
