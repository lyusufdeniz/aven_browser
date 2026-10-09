package dev.furina.avenbrowser

import android.app.Activity
import android.app.Application
import io.flutter.embedding.engine.FlutterEngine

/** TV build: system WebView. Gecko classes are not on this classpath. */
internal object EngineHooks {
    fun installEarly(app: Application) {
        WebViewEngine.installEarly(app)
    }

    fun install(engine: FlutterEngine, activity: Activity) = Unit

    fun engineVersion(): String? = null

    fun pausePage(): Boolean = false

    fun resumePage(): Boolean = false

    fun tapPage(x: Float, y: Float): Boolean = false

    fun scrollPage(x: Float, y: Float, dx: Float, dy: Float): Boolean = false

    fun onRuntimePermissionResult(grantResults: IntArray) = Unit
}
