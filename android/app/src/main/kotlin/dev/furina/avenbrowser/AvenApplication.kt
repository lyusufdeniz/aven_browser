package dev.furina.avenbrowser

import android.app.Application

class AvenApplication : Application() {
    override fun onCreate() {
        EngineHooks.installEarly(this)
        super.onCreate()
    }
}
