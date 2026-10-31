package com.todoapp.todo_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.todoapp.todo_app/youtube"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchChromeIncognito" -> {
                        try {
                            // Open Chrome in incognito via the dedicated intent extra.
                            val chromeIntent = Intent(Intent.ACTION_VIEW).apply {
                                data = android.net.Uri.parse("https://www.google.com")
                                setPackage("com.android.chrome")
                                putExtra("com.android.chrome.open_new_incognito_tab", true)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(chromeIntent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("LAUNCH_FAILED", e.message, null)
                        }
                    }
                    "launchYouTube" -> {
                        try {
                            val launch = packageManager
                                .getLaunchIntentForPackage("com.google.android.youtube")
                                ?: Intent(Intent.ACTION_VIEW).apply {
                                    data = android.net.Uri.parse("https://www.youtube.com")
                                }
                            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launch)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("LAUNCH_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
