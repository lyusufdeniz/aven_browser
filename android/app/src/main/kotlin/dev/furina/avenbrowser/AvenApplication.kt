package dev.furina.avenbrowser

import android.app.Application
import android.os.Build
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

class AvenApplication : Application() {
    override fun onCreate() {
        EngineHooks.installEarly(this)
        super.onCreate()
        keepCrashReports()
    }

    /**
     * Writes an uncaught crash to files/aven_reports so Settings can show and
     * share it on the next launch, then lets Android handle the crash as usual.
     */
    private fun keepCrashReports() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }
                val dir = File(filesDir, "aven_reports").apply { mkdirs() }
                File(dir, "crash-${System.currentTimeMillis()}.txt").writeText(
                    buildString {
                        append("Aven crash (Android)\n")
                        append("Build: ${BuildConfig.FLAVOR} ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})\n")
                        append("Device: ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}\n")
                        append("Thread: ${thread.name}\n\n")
                        append(trace)
                    },
                )
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }
}
