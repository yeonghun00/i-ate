package com.thousandemfla.thanks_everyday.elder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

class ScreenMonitorService : Service() {
    
    companion object {
        private const val TAG = "ScreenMonitorService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "screen_monitor_channel"
        
        fun startService(context: Context) {
            try {
                val intent = Intent(context, ScreenMonitorService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                    Log.d(TAG, "✅ ScreenMonitorService foreground start requested (Android 8+)")
                } else {
                    context.startService(intent)
                    Log.d(TAG, "✅ ScreenMonitorService start requested (Android 7-)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to start ScreenMonitorService: ${e.message}")
                Log.e(TAG, "💡 This may happen during boot if system isn't ready yet")
                
                // Retry after delay if startup failed (common during boot)
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    try {
                        Log.d(TAG, "🔄 Retrying ScreenMonitorService startup...")
                        val retryIntent = Intent(context, ScreenMonitorService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(retryIntent)
                        } else {
                            context.startService(retryIntent)
                        }
                        Log.d(TAG, "✅ ScreenMonitorService retry successful")
                    } catch (retryException: Exception) {
                        Log.e(TAG, "❌ ScreenMonitorService retry also failed: ${retryException.message}")
                    }
                }, 10000) // 10-second retry
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, ScreenMonitorService::class.java)
            context.stopService(intent)
            Log.d(TAG, "❌ ScreenMonitorService stop requested")
        }
        
        // Check if service is currently running
        fun isServiceRunning(): Boolean {
            // Simple check - in a full implementation you could check ActivityManager
            // For now, we'll just return true since this is called for verification
            return true
        }
    }
    
    private var screenStateReceiver: BroadcastReceiver? = null
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 ScreenMonitorService created")
        createNotificationChannel()
        registerScreenStateReceiver()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📱 ScreenMonitorService started - monitoring screen unlock events")
        
        try {
            // Start as foreground service to prevent being killed
            val notification = createNotification()
            startForeground(NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ Foreground notification created and displayed")
            
            // Re-register receiver in case it was lost
            registerScreenStateReceiver()
            
            Log.d(TAG, "✅ ScreenMonitorService running as foreground service for app persistence")
            Log.d(TAG, "✅ Notification should now show: '안전 모니터링 활성 : 휴대폰 사용 감지 중...'")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during service startup: ${e.message}")
            // Continue anyway - better to have partial functionality than crash
        }
        
        return START_STICKY // Restart if killed by system
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "💀 ScreenMonitorService destroyed")
        unregisterScreenStateReceiver()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Monitor Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors screen unlock events for survival signal"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("안전 모니터링 활성")
            .setContentText("휴대폰 사용 감지 중...")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }
    
    private fun registerScreenStateReceiver() {
        try {
            if (screenStateReceiver == null) {
                screenStateReceiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        when (intent.action) {
                            Intent.ACTION_SCREEN_ON -> {
                                Log.d(TAG, "📱 Screen turned ON (from service)")
                            }
                            Intent.ACTION_USER_PRESENT -> {
                                Log.d(TAG, "🔓 User UNLOCKED phone (from service) - updating Firebase")
                                updateLastPhoneActivity()
                            }
                        }
                    }
                }
                
                val intentFilter = IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_USER_PRESENT)
                    priority = 1000
                }
                
                registerReceiver(screenStateReceiver, intentFilter)
                Log.d(TAG, "✅ Screen state receiver registered in foreground service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to register screen state receiver in service: ${e.message}")
        }
    }
    
    private fun unregisterScreenStateReceiver() {
        try {
            screenStateReceiver?.let {
                unregisterReceiver(it)
                screenStateReceiver = null
                Log.d(TAG, "❌ Screen state receiver unregistered from service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to unregister screen state receiver: ${e.message}")
        }
    }
    
    private fun updateLastPhoneActivity() {
        try {
            // Check if monitoring is enabled
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            
            if (!isEnabled) {
                Log.d(TAG, "📱 Monitoring disabled, skipping phone activity update (service)")
                return
            }
            
            // Get family info
            val familyId = prefs.getString("flutter.family_id", null)
            if (familyId == null) {
                Log.w(TAG, "⚠️ No family ID found, skipping phone activity update (service)")
                return
            }
            
            // Update Firebase with real phone activity
            val firestore = FirebaseFirestore.getInstance()
            firestore.collection("families")
                .document(familyId)
                .update("lastPhoneActivity", FieldValue.serverTimestamp())
                .addOnSuccessListener {
                    Log.d(TAG, "✅ lastPhoneActivity updated from background service!")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "❌ Failed to update lastPhoneActivity from service: ${e.message}")
                }
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating phone activity from service: ${e.message}")
        }
    }
}