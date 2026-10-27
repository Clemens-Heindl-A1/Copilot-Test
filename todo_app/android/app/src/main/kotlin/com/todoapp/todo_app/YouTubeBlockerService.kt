package com.todoapp.todo_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

class YouTubeBlockerService : AccessibilityService() {
    companion object {
        const val ACTION_CINEMA_OPENED = "com.todoapp.todo_app.CINEMA_OPENED"
        const val EXTRA_CINEMA_TOKENS = "cinema_tokens"
        const val EXTRA_JOKER_TOKENS = "joker_tokens"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_CINEMA_TOKENS = "flutter.reward_cinema"
        private const val KEY_MYSTERY_TOKENS = "flutter.reward_mystery"
        private const val KEY_CINEMA_PROCESSED = "flutter.cinema_processed_date"
        private const val KEY_CINEMA_DAILY_MS = "flutter.cinema_daily_ms"
        private const val KEY_CINEMA_TRACK_DATE = "flutter.cinema_track_date"
        private const val CINEMA_THRESHOLD_MS = 30L * 60 * 1000
        private const val CHROME_PACKAGE = "com.android.chrome"
        private const val CHROME_PACKAGE_ALT = "com.google.android.apps.chrome"
        private const val DEBOUNCE_MS = 8_000L
        private const val NOTIF_CHANNEL_ID = "app_watcher_channel"
        private const val NOTIF_ID_CINEMA = 1002
        private val BROWSER_PACKAGES = setOf(CHROME_PACKAGE, CHROME_PACKAGE_ALT)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var cinemaSessionStart = 0L
    private var lastChromeFireMs = 0L
    private val cinemaThresholdRunnable = Runnable { onCinemaThresholdReached() }

    override fun onServiceConnected() {
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            packageNames = null
            notificationTimeout = 0
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    NOTIF_CHANNEL_ID, "App-Wächter", NotificationManager.IMPORTANCE_HIGH
                )
            )
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (cinemaSessionStart == 0L && pkg !in BROWSER_PACKAGES) return
        if (pkg in BROWSER_PACKAGES) handleBrowser(pkg)
        else stopCinemaSession(getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))
    }

    private fun handleBrowser(pkg: String) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isChrome = pkg == CHROME_PACKAGE || pkg == CHROME_PACKAGE_ALT
        if (isChrome && isChromeIncognitoActive()) {
            val today = todayStr()
            if (prefs.getString(KEY_CINEMA_PROCESSED, "") != today) {
                val now = System.currentTimeMillis()
                if (now - lastChromeFireMs < DEBOUNCE_MS) return
                lastChromeFireMs = now
                performGlobalAction(GLOBAL_ACTION_BACK)
                showBlockNotification(
                    prefs.getInt(KEY_CINEMA_TOKENS, 0),
                    prefs.getInt(KEY_MYSTERY_TOKENS, 0)
                )
            } else if (cinemaSessionStart == 0L) {
                cinemaSessionStart = System.currentTimeMillis()
                scheduleThreshold(prefs)
            }
        } else {
            stopCinemaSession(prefs)
        }
    }

    private fun onCinemaThresholdReached() {
        if (cinemaSessionStart == 0L) return
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val elapsed = System.currentTimeMillis() - cinemaSessionStart
        cinemaSessionStart = 0L
        accumulateDailyUsage(prefs, elapsed)
        lastChromeFireMs = System.currentTimeMillis()
        performGlobalAction(GLOBAL_ACTION_BACK)
        showBlockNotification(
            prefs.getInt(KEY_CINEMA_TOKENS, 0), prefs.getInt(KEY_MYSTERY_TOKENS, 0)
        )
    }

    private fun scheduleThreshold(prefs: android.content.SharedPreferences) {
        val today = todayStr()
        val previousMs = if (prefs.getString(KEY_CINEMA_TRACK_DATE, "") == today) {
            prefs.getLong(KEY_CINEMA_DAILY_MS, 0L)
        } else 0L
        val remainingMs = CINEMA_THRESHOLD_MS - previousMs % CINEMA_THRESHOLD_MS
        handler.removeCallbacks(cinemaThresholdRunnable)
        handler.postDelayed(cinemaThresholdRunnable, remainingMs)
    }

    private fun stopCinemaSession(prefs: android.content.SharedPreferences) {
        handler.removeCallbacks(cinemaThresholdRunnable)
        if (cinemaSessionStart == 0L) return
        val elapsed = System.currentTimeMillis() - cinemaSessionStart
        cinemaSessionStart = 0L
        accumulateDailyUsage(prefs, elapsed)
    }

    private fun accumulateDailyUsage(prefs: android.content.SharedPreferences, elapsedMs: Long) {
        if (elapsedMs <= 0) return
        val today = todayStr()
        val previousMs = if (prefs.getString(KEY_CINEMA_TRACK_DATE, "") == today) {
            prefs.getLong(KEY_CINEMA_DAILY_MS, 0L)
        } else 0L
        val newTotalMs = previousMs + elapsedMs
        prefs.edit().putString(KEY_CINEMA_TRACK_DATE, today)
            .putLong(KEY_CINEMA_DAILY_MS, newTotalMs).apply()
        if (newTotalMs / CINEMA_THRESHOLD_MS > previousMs / CINEMA_THRESHOLD_MS) {
            prefs.edit().remove(KEY_CINEMA_PROCESSED).apply()
        }
    }

    private fun showBlockNotification(tokens: Int, jokers: Int) {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_CINEMA_OPENED
            putExtra(EXTRA_CINEMA_TOKENS, tokens)
            putExtra(EXTRA_JOKER_TOKENS, jokers)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        try { startActivity(intent) } catch (_: Exception) {}
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val pendingIntent = PendingIntent.getActivity(
            this, NOTIF_ID_CINEMA, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIF_CHANNEL_ID)
        } else Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        manager.notify(
            NOTIF_ID_CINEMA,
            builder.setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("Film - Token erforderlich")
                .setContentText(if (tokens > 0 || jokers > 0) "Tippe hier, um einen Token einzulösen."
                else "Kein Token verfügbar - zuerst einen verdienen!")
                .setAutoCancel(true).setContentIntent(pendingIntent)
                .setFullScreenIntent(pendingIntent, true).build()
        )
    }

    private fun isChromeIncognitoActive(): Boolean = try {
        windows.any { window ->
            val title = window.title?.toString()?.lowercase() ?: ""
            title.contains("incognito") || title.contains("inkognito")
        }
    } catch (_: Exception) { false }

    private fun todayStr(): String = java.text.SimpleDateFormat(
        "yyyy-MM-dd", java.util.Locale.getDefault()
    ).format(java.util.Date())

    override fun onInterrupt() {
        handler.removeCallbacks(cinemaThresholdRunnable)
    }
}
