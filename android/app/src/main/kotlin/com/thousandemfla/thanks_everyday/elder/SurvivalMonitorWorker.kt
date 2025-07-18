package com.thousandemfla.thanks_everyday.elder

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

class SurvivalMonitorWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    
    companion object {
        private const val TAG = "SurvivalMonitorWorker"
        private const val PREFS_NAME = "screen_monitor_prefs"
        private const val LAST_SCREEN_ON_KEY = "last_screen_on"
        private const val WORK_NAME = "survival_monitor_work"
        
        fun scheduleWork(context: Context) {
            val workRequest = PeriodicWorkRequestBuilder<SurvivalMonitorWorker>(
                30, TimeUnit.MINUTES,  // Check every 30 minutes
                5, TimeUnit.MINUTES    // Flex interval
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .build()
            
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                workRequest
            )
            
            Log.d(TAG, "Survival monitor work scheduled")
        }
        
        fun cancelWork(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "Survival monitor work cancelled")
        }
    }
    
    override fun doWork(): Result {
        Log.d(TAG, "Checking for inactivity...")
        
        if (!isServiceEnabled()) {
            Log.d(TAG, "Service disabled, skipping check")
            return Result.success()
        }
        
        val alertHours = getAlertHours()
        if (checkForInactivity(alertHours)) {
            sendInactivityAlert(alertHours)
        }
        
        return Result.success()
    }
    
    private fun isServiceEnabled(): Boolean {
        val flutterPrefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return flutterPrefs.getBoolean("flutter.survival_signal_enabled", false)
    }
    
    private fun getAlertHours(): Int {
        val flutterPrefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return flutterPrefs.getInt("flutter.alert_hours", 12)
    }
    
    private fun checkForInactivity(alertHours: Int): Boolean {
        val sharedPreferences = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val lastActivity = sharedPreferences.getLong(LAST_SCREEN_ON_KEY, 0)
        val currentTime = System.currentTimeMillis()
        val timeDiff = currentTime - lastActivity
        
        val alertMillis = alertHours * 60 * 60 * 1000L
        
        if (timeDiff > alertMillis) {
            Log.w(TAG, "No screen activity for ${alertHours}+ hours, sending alert")
            return true
        }
        
        Log.d(TAG, "Activity detected within ${alertHours} hours, no alert needed")
        return false
    }
    
    private fun sendInactivityAlert(hours: Int) {
        val intent = Intent("com.thousandemfla.thanks_everyday.elder.INACTIVITY_ALERT")
        intent.putExtra("hours_inactive", hours)
        applicationContext.sendBroadcast(intent)
        Log.d(TAG, "Inactivity alert broadcast sent for $hours hours")
    }
}