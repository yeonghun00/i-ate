package com.thousandemfla.thanks_everyday.elder

import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.*

class EnhancedUsageMonitor(
    private val context: Context,
    private val methodChannel: MethodChannel
) {
    companion object {
        private const val TAG = "EnhancedUsageMonitor"
        private const val USAGE_CHECK_INTERVAL = 15 * 60 * 1000L // 15 minutes
    }
    
    private var isMonitoring = false
    private var screenReceiver: ScreenStateReceiver? = null
    private var usageCheckHandler: Handler? = null
    private var usageCheckRunnable: Runnable? = null
    
    // Usage tracking
    private var lastUsageCheckTime = System.currentTimeMillis()
    private var lastInteractionTime = System.currentTimeMillis()
    
    fun startMonitoring() {
        if (isMonitoring) {
            Log.w(TAG, "Already monitoring")
            return
        }
        
        Log.d(TAG, "🚀 Starting Enhanced Usage Monitoring...")
        
        try {
            // Register screen state receiver for immediate events
            registerScreenReceiver()
            
            // Start periodic usage checks
            startPeriodicUsageChecks()
            
            isMonitoring = true
            Log.d(TAG, "✅ Enhanced Usage Monitoring started successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start monitoring", e)
        }
    }
    
    fun stopMonitoring() {
        if (!isMonitoring) return
        
        Log.d(TAG, "🛑 Stopping Enhanced Usage Monitoring...")
        
        try {
            // Unregister receivers
            if (screenReceiver != null) {
                context.unregisterReceiver(screenReceiver)
                screenReceiver = null
            }
            
            // Stop periodic checks
            usageCheckHandler?.removeCallbacks(usageCheckRunnable ?: return)
            usageCheckHandler = null
            usageCheckRunnable = null
            
            isMonitoring = false
            Log.d(TAG, "✅ Enhanced Usage Monitoring stopped")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping monitoring", e)
        }
    }
    
    private fun registerScreenReceiver() {
        screenReceiver = ScreenStateReceiver()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT) // Screen unlock
        }
        
        context.registerReceiver(screenReceiver, filter)
        Log.d(TAG, "📱 Screen state receiver registered")
    }
    
    private fun startPeriodicUsageChecks() {
        usageCheckHandler = Handler(Looper.getMainLooper())
        usageCheckRunnable = object : Runnable {
            override fun run() {
                checkAppUsageStats()
                usageCheckHandler?.postDelayed(this, USAGE_CHECK_INTERVAL)
            }
        }
        
        // Start first check
        usageCheckHandler?.post(usageCheckRunnable ?: return)
        Log.d(TAG, "⏰ Periodic phone usage checks started (every 15 minutes)")
    }
    
    private fun checkAppUsageStats() {
        try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            if (usageStatsManager == null) {
                Log.w(TAG, "UsageStatsManager not available")
                return
            }
            
            val currentTime = System.currentTimeMillis()
            val checkWindow = currentTime - lastUsageCheckTime // Check since last check
            
            // Get usage stats for the check window - focus on ANY phone usage
            val usageStats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                lastUsageCheckTime,
                currentTime
            )
            
            var hasRecentPhoneActivity = false
            var totalPhoneUsageTime = 0L
            var recentApps = 0
            var latestActivityTime = lastInteractionTime
            
            // Check for ANY app usage (system-wide phone activity)
            for (stats in usageStats) {
                // Count ANY foreground time as phone usage (not just our app)
                if (stats.totalTimeInForeground > 0 || stats.lastTimeUsed > lastUsageCheckTime) {
                    totalPhoneUsageTime += stats.totalTimeInForeground
                    
                    // Any app usage in the window means phone was being used
                    if (stats.lastTimeUsed > lastUsageCheckTime) {
                        hasRecentPhoneActivity = true
                        latestActivityTime = maxOf(latestActivityTime, stats.lastTimeUsed)
                        recentApps++
                        
                        Log.d(TAG, "📱 Phone activity detected via: ${stats.packageName} (used: ${stats.lastTimeUsed - lastUsageCheckTime}ms ago)")
                    }
                }
            }
            
            // Update interaction time if we found recent activity
            if (hasRecentPhoneActivity) {
                lastInteractionTime = latestActivityTime
                notifyFlutterPhoneUsage(totalPhoneUsageTime, recentApps)
            }
            
            // Update last check time
            lastUsageCheckTime = currentTime
            
            Log.d(TAG, "📊 Phone usage check completed - Activity: $hasRecentPhoneActivity, Apps used: $recentApps, Total usage: ${totalPhoneUsageTime}ms")
            
        } catch (e: SecurityException) {
            Log.w(TAG, "Usage stats permission denied - falling back to screen-only monitoring")
        } catch (e: Exception) {
            Log.e(TAG, "Error checking phone usage stats", e)
        }
    }
    
    private fun notifyFlutterPhoneUsage(totalUsageTime: Long, appsUsed: Int) {
        try {
            val arguments = mapOf(
                "phone_usage_time_ms" to totalUsageTime,
                "apps_used" to appsUsed,
                "last_interaction_time" to lastInteractionTime,
                "check_timestamp" to System.currentTimeMillis()
            )
            
            methodChannel.invokeMethod("onPhoneUsage", arguments)
            Log.d(TAG, "📤 Notified Flutter of phone usage")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify Flutter of phone usage", e)
        }
    }
    
    fun getUsageStats(): Map<String, Any> {
        val currentTime = System.currentTimeMillis()
        val timeSinceLastInteraction = currentTime - lastInteractionTime
        
        return mapOf(
            "hasRecentActivity" to (timeSinceLastInteraction < USAGE_CHECK_INTERVAL),
            "lastInteractionTime" to lastInteractionTime,
            "timeSinceLastInteraction" to timeSinceLastInteraction,
            "isMonitoring" to isMonitoring
        )
    }
    
    // Inner class for screen state events
    private inner class ScreenStateReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    Log.d(TAG, "📱 Screen ON detected")
                    lastInteractionTime = System.currentTimeMillis()
                    methodChannel.invokeMethod("onScreenOn", null)
                }
                
                Intent.ACTION_SCREEN_OFF -> {
                    Log.d(TAG, "📱 Screen OFF detected")
                    lastInteractionTime = System.currentTimeMillis()
                    methodChannel.invokeMethod("onScreenOff", null)
                }
                
                Intent.ACTION_USER_PRESENT -> {
                    Log.d(TAG, "🔓 Screen UNLOCKED detected")
                    lastInteractionTime = System.currentTimeMillis()
                    methodChannel.invokeMethod("onScreenUnlock", null)
                }
            }
        }
    }
}