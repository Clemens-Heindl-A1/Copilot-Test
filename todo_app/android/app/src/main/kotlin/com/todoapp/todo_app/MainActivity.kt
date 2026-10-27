package com.todoapp.todo_app

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.todoapp.todo_app/youtube"
        var pendingCinemaTokens: Int?  = null
        var pendingCinemaJokerTokens: Int? = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleBlockerIntent(intent)
    }

    private fun handleBlockerIntent(intent: Intent?) {
        when (intent?.action) {
            YouTubeBlockerService.ACTION_CINEMA_OPENED -> {
                pendingCinemaTokens      = intent.getIntExtra(YouTubeBlockerService.EXTRA_CINEMA_TOKENS, 0)
                pendingCinemaJokerTokens = intent.getIntExtra(YouTubeBlockerService.EXTRA_JOKER_TOKENS, 0)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Handle the intent that arrived before Flutter was ready.
        handleBlockerIntent(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingCinemaAction" -> {
                        val ct = pendingCinemaTokens
                        val cj = pendingCinemaJokerTokens
                        if (ct != null && cj != null) {
                            result.success(mapOf("cinema_tokens" to ct, "joker_tokens" to cj))
                        } else {
                            result.success(null)
                        }
                    }
                    "clearPendingCinemaAction" -> {
                        pendingCinemaTokens      = null
                        pendingCinemaJokerTokens = null
                        result.success(null)
                    }
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
                    "hasAccessibilityPermission" -> {
                        val component = ComponentName(this, YouTubeBlockerService::class.java)
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                        )?.contains(component.flattenToString()) == true
                        result.success(enabled)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        if (android.os.Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
