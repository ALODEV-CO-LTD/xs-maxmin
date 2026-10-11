package vn.mamba.mamba_app

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var screenshotChannel: MethodChannel? = null
    private var captureCallback: Activity.ScreenCaptureCallback? = null

    // Android 14+: tell Dart when a screenshot was taken (the chat warns the friend). Other versions: no callback.
    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= 34) {
            val cb = Activity.ScreenCaptureCallback { screenshotChannel?.invokeMethod("screenshot", null) }
            captureCallback = cb
            try {
                registerScreenCaptureCallback(mainExecutor, cb)
            } catch (_: SecurityException) {
                captureCallback = null
            }
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= 34) captureCallback?.let { unregisterScreenCaptureCallback(it) }
        captureCallback = null
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Secure by default (no screenshots / screen recording / recents thumbnail) until the app says otherwise.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        screenshotChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mamba/screenshot")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.mamba/secure").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    runOnUiThread {
                        if (enabled) {
                            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
