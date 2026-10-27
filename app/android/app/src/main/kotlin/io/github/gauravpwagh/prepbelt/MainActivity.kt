package io.github.gauravpwagh.prepbelt

import android.content.Intent
import android.os.Bundle
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The only hand-written native code (plan item 41): two methods on the
 * `prepbelt/device` channel.
 *
 * - isIgnoringBatteryOptimizations: permission_handler only reports this when
 *   REQUEST_IGNORE_BATTERY_OPTIMIZATIONS is declared, which the app must not do.
 * - takeShareSubject: receive_sharing_intent does not pass EXTRA_SUBJECT on.
 */
class MainActivity : FlutterActivity() {
    private var shareSubject: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prepbelt/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "takeShareSubject" -> {
                        result.success(shareSubject)
                        shareSubject = null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        storeShareSubject(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        storeShareSubject(intent)
        super.onNewIntent(intent)
    }

    private fun storeShareSubject(intent: Intent?) {
        val action = intent?.action
        if (action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE) {
            shareSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        }
    }
}
