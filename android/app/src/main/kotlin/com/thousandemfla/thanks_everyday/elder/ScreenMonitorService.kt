package com.thousandemfla.thanks_everyday.elder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.*
import kotlin.concurrent.timer

class ScreenMonitorService : Service() {
    private var screenReceiver: BroadcastReceiver? = null
    private var timer: Timer? = null
    private lateinit var sharedPreferences: SharedPreferences
    private lateinit var powerManager: PowerManager
    
    companion object {
        private const val TAG = "ScreenMonitorService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "screen_monitor_channel"
        private const val PREFS_NAME = "screen_monitor_prefs"
        private const val LAST_SCREEN_ON_KEY = "last_screen_on"
        private const val SCREEN_ON_COUNT_KEY = "screen_on_count"
        private const val SERVICE_ENABLED_KEY = "survival_signal_enabled"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        
        sharedPreferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        
        // Create notification channel and start foreground service
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Use background service approach for better compatibility
        setupScreenReceiver()
        startPeriodicCheck()
        
        Log.d(TAG, "Screen monitoring service initialized successfully as foreground service")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service started")
        return START_STICKY // Restart if killed
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
        
        screenReceiver?.let {
            unregisterReceiver(it)
        }
        timer?.cancel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "생존 신호 모니터링",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "휴대폰 사용을 감지하여 안전 상태를 모니터링합니다"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("생존 신호 감지 중")
            .setContentText("휴대폰 사용을 모니터링하고 있습니다")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun setupScreenReceiver() {
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_ON -> {
                        Log.d(TAG, "Screen turned ON")
                        recordScreenActivity()
                    }
                    Intent.ACTION_USER_PRESENT -> {
                        Log.d(TAG, "User unlocked device")
                        recordScreenActivity()
                    }
                    Intent.ACTION_SCREEN_OFF -> {
                        Log.d(TAG, "Screen turned OFF")
                        // Don't record screen off, we only care about active usage
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        
        registerReceiver(screenReceiver, filter)
    }

    private fun recordScreenActivity() {
        val currentTime = System.currentTimeMillis()
        val currentCount = sharedPreferences.getInt(SCREEN_ON_COUNT_KEY, 0)
        
        sharedPreferences.edit()
            .putLong(LAST_SCREEN_ON_KEY, currentTime)
            .putInt(SCREEN_ON_COUNT_KEY, currentCount + 1)
            .apply()
        
        Log.d(TAG, "Screen activity recorded: $currentTime, count: ${currentCount + 1}")
        
        // Update Flutter app's SharedPreferences as well
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        flutterPrefs.edit()
            .putLong("flutter.last_screen_on_timestamp", currentTime)
            .putInt("flutter.screen_on_count", currentCount + 1)
            .apply()
    }

    private fun startPeriodicCheck() {
        // Periodic checks are now handled by WorkManager
        // This service only handles real-time screen events
        Log.d(TAG, "Screen event monitoring active")
    }

    private fun isServiceEnabled(): Boolean {
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return flutterPrefs.getBoolean("flutter.survival_signal_enabled", false)
    }

    private fun checkForInactivity() {
        val lastActivity = sharedPreferences.getLong(LAST_SCREEN_ON_KEY, 0)
        val currentTime = System.currentTimeMillis()
        val timeDiff = currentTime - lastActivity
        
        // Get alert hours from Flutter SharedPreferences (default 12 hours)
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val alertHours = flutterPrefs.getInt("flutter.alert_hours", 12)
        val alertMillis = alertHours * 60 * 60 * 1000L
        
        if (timeDiff > alertMillis) {
            Log.w(TAG, "No screen activity for ${alertHours}+ hours, should alert family")
            // This would trigger the Firebase alert in the Flutter app
            // We can send a broadcast to the Flutter app
            sendInactivityAlert(alertHours)
        }
    }

    private fun sendInactivityAlert(hours: Int) {
        val intent = Intent("com.thousandemfla.thanks_everyday.elder.INACTIVITY_ALERT")
        intent.putExtra("hours_inactive", hours)
        sendBroadcast(intent)
        Log.d(TAG, "Inactivity alert broadcast sent for $hours hours")
    }
}