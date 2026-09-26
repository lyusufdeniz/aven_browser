package com.avenbrowser.aven_browser

import android.app.Application

class AvenApplication : Application() {
    override fun onCreate() {
        // Chromium CommandLine + cache dir before any WebView exists.
        WebViewEngine.installEarly(this)
        super.onCreate()
    }
}
