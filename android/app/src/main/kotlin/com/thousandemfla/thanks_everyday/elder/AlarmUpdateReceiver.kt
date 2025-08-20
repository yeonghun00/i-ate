package com.thousandemfla.thanks_everyday.elder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import androidx.core.app.ActivityCompat
import android.content.pm.PackageManager
import android.Manifest
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

class AlarmUpdateReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "AlarmUpdateReceiver"
        
        // Request codes for different alarm types
        private const val GPS_REQUEST_CODE = 1001
        private const val SURVIVAL_REQUEST_CODE = 1002
        
        // Actions for each service type
        private const val ACTION_GPS_UPDATE = "com.thousandemfla.thanks_everyday.GPS_UPDATE"
        private const val ACTION_SURVIVAL_UPDATE = "com.thousandemfla.thanks_everyday.SURVIVAL_UPDATE"
        
        // 2-minute interval for both services
        private const val INTERVAL_MILLIS = 2 * 60 * 1000L
        
        /**
         * Enable GPS location tracking - ALWAYS updates regardless of screen
         */
        fun enableLocationTracking(context: Context) {
            Log.i(TAG, "🌍 Enabling GPS location tracking...")
            
            // Save preference
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", true).apply()
            
            // Start GPS alarms
            scheduleGpsAlarm(context)
            
            Log.i(TAG, "✅ GPS location tracking enabled - will update every 2 minutes ALWAYS")
        }
        
        /**
         * Disable GPS location tracking and cancel alarms
         */
        fun disableLocationTracking(context: Context) {
            Log.i(TAG, "🌍 Disabling GPS location tracking...")
            
            // Save preference
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", false).apply()
            
            // Cancel GPS alarms
            cancelGpsAlarm(context)
            
            Log.i(TAG, "❌ GPS location tracking disabled")
        }
        
        /**
         * Enable survival signal monitoring with alarm scheduling
         */
        fun enableSurvivalMonitoring(context: Context) {
            Log.i(TAG, "💓 Enabling survival signal monitoring...")
            
            // Save preference
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.survival_signal_enabled", true).apply()
            
            // Initialize screen state tracking
            val currentScreenState = isScreenOn(context)
            prefs.edit().putBoolean("flutter.last_screen_state", currentScreenState).apply()
            
            // Start survival alarms
            scheduleSurvivalAlarm(context)
            
            Log.i(TAG, "✅ Survival signal monitoring enabled with 2-minute intervals")
        }
        
        /**
         * Disable survival signal monitoring and cancel alarms
         */
        fun disableSurvivalMonitoring(context: Context) {
            Log.i(TAG, "💓 Disabling survival signal monitoring...")
            
            // Save preference
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.survival_signal_enabled", false).apply()
            
            // Cancel survival alarms
            cancelSurvivalAlarm(context)
            
            Log.i(TAG, "❌ Survival signal monitoring disabled")
        }
        
        /**
         * Schedule GPS location alarm
         */
        fun scheduleGpsAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                
                val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                    action = ACTION_GPS_UPDATE
                }
                
                val pendingIntent = createPendingIntent(context, GPS_REQUEST_CODE, intent)
                val triggerAtMillis = SystemClock.elapsedRealtime() + INTERVAL_MILLIS
                
                scheduleAlarmWithBestMethod(alarmManager, triggerAtMillis, pendingIntent)
                
                Log.d(TAG, "✅ GPS alarm scheduled for 2 minutes")
                
                // Record scheduling time
                recordAlarmScheduled(context, "gps")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to schedule GPS alarm: ${e.message}")
                throw e
            }
        }
        
        /**
         * Schedule survival signal alarm
         */
        fun scheduleSurvivalAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                
                val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                    action = ACTION_SURVIVAL_UPDATE
                }
                
                val pendingIntent = createPendingIntent(context, SURVIVAL_REQUEST_CODE, intent)
                val triggerAtMillis = SystemClock.elapsedRealtime() + INTERVAL_MILLIS
                
                scheduleAlarmWithBestMethod(alarmManager, triggerAtMillis, pendingIntent)
                
                Log.d(TAG, "✅ Survival alarm scheduled for 2 minutes")
                
                // Record scheduling time
                recordAlarmScheduled(context, "survival")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to schedule survival alarm: ${e.message}")
                throw e
            }
        }
        
        /**
         * Cancel GPS alarm
         */
        fun cancelGpsAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                    action = ACTION_GPS_UPDATE
                }
                val pendingIntent = createPendingIntent(context, GPS_REQUEST_CODE, intent)
                alarmManager.cancel(pendingIntent)
                
                Log.d(TAG, "❌ GPS alarm cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error cancelling GPS alarm: ${e.message}")
            }
        }
        
        /**
         * Cancel survival alarm
         */
        fun cancelSurvivalAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                    action = ACTION_SURVIVAL_UPDATE
                }
                val pendingIntent = createPendingIntent(context, SURVIVAL_REQUEST_CODE, intent)
                alarmManager.cancel(pendingIntent)
                
                Log.d(TAG, "❌ Survival alarm cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error cancelling survival alarm: ${e.message}")
            }
        }
        
        /**
         * Legacy method for backward compatibility - should not be used in new code
         * Use enableLocationTracking() and enableSurvivalMonitoring() instead
         */
        @Deprecated("Use enableLocationTracking() and enableSurvivalMonitoring() instead")
        fun scheduleAlarms(context: Context) {
            Log.w(TAG, "⚠️ scheduleAlarms() is deprecated - this should be handled by BootReceiver")
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            if (survivalEnabled) {
                enableSurvivalMonitoring(context)
            }
            
            if (locationEnabled) {
                enableLocationTracking(context)
            }
        }
        
        // Helper methods
        
        private fun createPendingIntent(context: Context, requestCode: Int, intent: Intent): PendingIntent {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }
        
        private fun scheduleAlarmWithBestMethod(
            alarmManager: AlarmManager,
            triggerAtMillis: Long,
            pendingIntent: PendingIntent
        ) {
            try {
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                        // MIUI FIX: Always try exact alarms first, ignore canScheduleExactAlarms() 
                        // because MIUI returns false after reboot even when permission exists
                        try {
                            Log.d(TAG, "📱 Android 12+ detected - trying setExactAndAllowWhileIdle first")
                            alarmManager.setExactAndAllowWhileIdle(
                                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                                triggerAtMillis,
                                pendingIntent
                            )
                            Log.d(TAG, "✅ Exact alarm scheduled successfully")
                        } catch (e: SecurityException) {
                            Log.w(TAG, "⚠️ Exact alarm permission denied - falling back to inexact: ${e.message}")
                            alarmManager.setAndAllowWhileIdle(
                                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                                triggerAtMillis,
                                pendingIntent
                            )
                        }
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                        Log.d(TAG, "📱 Android 6+ detected - using setExactAndAllowWhileIdle")
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.ELAPSED_REALTIME_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                    }
                    else -> {
                        Log.d(TAG, "📱 Legacy Android - using setExact")
                        alarmManager.setExact(
                            AlarmManager.ELAPSED_REALTIME_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to schedule alarm with any method: ${e.message}")
                throw e
            }
        }
        
        private fun isScreenOn(context: Context): Boolean {
            return try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                    powerManager.isInteractive
                } else {
                    @Suppress("DEPRECATION")
                    powerManager.isScreenOn
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to check screen state: ${e.message}")
                false
            }
        }
        
        private fun recordAlarmScheduled(context: Context, type: String) {
            try {
                val prefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
                prefs.edit()
                    .putLong("last_${type}_alarm_scheduled", System.currentTimeMillis())
                    .apply()
            } catch (e: Exception) {
                Log.w(TAG, "Could not record alarm scheduling time: ${e.message}")
            }
        }
        
        private fun recordAlarmExecution(context: Context, type: String) {
            try {
                val prefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
                prefs.edit()
                    .putLong("last_${type}_execution", System.currentTimeMillis())
                    .apply()
                Log.i(TAG, "📊 Recorded $type execution at ${System.currentTimeMillis()}")
            } catch (e: Exception) {
                Log.w(TAG, "Could not record alarm execution time: ${e.message}")
            }
        }
        
        /**
         * Get debug status for troubleshooting
         */
        fun getDebugStatus(context: Context): String {
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val debugPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
                
                val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
                val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
                
                val lastSurvivalExecution = debugPrefs.getLong("last_survival_execution", 0)
                val lastGpsExecution = debugPrefs.getLong("last_gps_execution", 0)
                val lastSurvivalScheduled = debugPrefs.getLong("last_survival_alarm_scheduled", 0)
                val lastGpsScheduled = debugPrefs.getLong("last_gps_alarm_scheduled", 0)
                
                val currentTime = System.currentTimeMillis()
                
                val status = StringBuilder()
                status.appendLine("🔍 ALARM DEBUG STATUS")
                status.appendLine("=====================")
                status.appendLine("Survival Enabled: $survivalEnabled")
                status.appendLine("GPS Enabled: $locationEnabled")
                status.appendLine("")
                
                if (survivalEnabled) {
                    status.appendLine("SURVIVAL SIGNAL:")
                    if (lastSurvivalScheduled > 0) {
                        val schedMinAgo = (currentTime - lastSurvivalScheduled) / 60000
                        status.appendLine("  Last Scheduled: $schedMinAgo min ago")
                    } else {
                        status.appendLine("  Last Scheduled: NEVER")
                    }
                    
                    if (lastSurvivalExecution > 0) {
                        val execMinAgo = (currentTime - lastSurvivalExecution) / 60000
                        status.appendLine("  Last Executed: $execMinAgo min ago")
                        status.appendLine("  Status: ${if (execMinAgo < 5) "✅ WORKING" else "⚠️ STALE"}")
                    } else {
                        status.appendLine("  Last Executed: NEVER")
                        status.appendLine("  Status: ❌ NOT WORKING")
                    }
                    status.appendLine("")
                }
                
                if (locationEnabled) {
                    status.appendLine("GPS TRACKING:")
                    if (lastGpsScheduled > 0) {
                        val schedMinAgo = (currentTime - lastGpsScheduled) / 60000
                        status.appendLine("  Last Scheduled: $schedMinAgo min ago")
                    } else {
                        status.appendLine("  Last Scheduled: NEVER")
                    }
                    
                    if (lastGpsExecution > 0) {
                        val execMinAgo = (currentTime - lastGpsExecution) / 60000
                        status.appendLine("  Last Executed: $execMinAgo min ago")
                        status.appendLine("  Status: ${if (execMinAgo < 5) "✅ WORKING" else "⚠️ STALE"}")
                    } else {
                        status.appendLine("  Last Executed: NEVER")
                        status.appendLine("  Status: ❌ NOT WORKING")
                    }
                }
                
                return status.toString()
            } catch (e: Exception) {
                return "Error getting debug status: ${e.message}"
            }
        }
        
        /**
         * Force restart both services for debugging
         */
        fun forceRestartAllServices(context: Context) {
            Log.i(TAG, "🔄 FORCE RESTARTING ALL SERVICES...")
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            try {
                // Cancel all existing alarms
                if (survivalEnabled) {
                    cancelSurvivalAlarm(context)
                    Thread.sleep(1000)
                }
                
                if (locationEnabled) {
                    cancelGpsAlarm(context)
                    Thread.sleep(1000)
                }
                
                // Restart with clean slate
                if (survivalEnabled) {
                    Log.i(TAG, "🔄 Restarting survival monitoring...")
                    enableSurvivalMonitoring(context)
                }
                
                if (locationEnabled) {
                    Log.i(TAG, "🔄 Restarting GPS tracking...")
                    enableLocationTracking(context)
                }
                
                Log.i(TAG, "✅ Force restart completed")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Force restart failed: ${e.message}")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🔔 Alarm triggered: ${intent.action}")
        
        // CRITICAL DEBUG: Log if we're being called after boot
        val uptimeMillis = SystemClock.elapsedRealtime()
        val isEarlyBoot = uptimeMillis < 5 * 60 * 1000L // Within 5 minutes of boot
        if (isEarlyBoot) {
            Log.i(TAG, "📱 EARLY BOOT ALARM (${uptimeMillis/1000}s after boot): ${intent.action}")
        }
        
        when (intent.action) {
            ACTION_GPS_UPDATE -> {
                handleGpsUpdate(context)
            }
            ACTION_SURVIVAL_UPDATE -> {
                handleSurvivalUpdate(context)
            }
            else -> {
                Log.w(TAG, "⚠️ Unknown alarm action: ${intent.action}")
            }
        }
    }
    
    /**
     * Handle GPS location update alarm - EXACTLY like survival signal
     */
    private fun handleGpsUpdate(context: Context) {
        Log.d(TAG, "🌍 GPS alarm triggered")
        
        try {
            // Check if GPS tracking is still enabled
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            if (!locationEnabled) {
                Log.d(TAG, "⚠️ GPS tracking disabled - stopping alarms")
                return
            }
            
            // GPS ALWAYS WORKS - screen on OR off (unlike survival signal)
            // CRITICAL FIX: Use direct LocationManager instead of service dependency
            Log.d(TAG, "🌍 GPS alarm triggered - ALWAYS updating location (service-free)")
            
            try {
                updateFirebaseWithLocation(context)
                Log.d(TAG, "✅ GPS location updated (works regardless of screen state)")
            } catch (e: Exception) {
                Log.w(TAG, "GPS location update failed but continuing: ${e.message}")
            }
            
            // ALWAYS record execution and schedule next alarm - SAME AS SURVIVAL
            recordAlarmExecution(context, "gps")
            scheduleGpsAlarm(context)
            
            Log.d(TAG, "✅ GPS update completed, next alarm scheduled")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in GPS update: ${e.message}")
            // Try to reschedule even if update failed
            try {
                scheduleGpsAlarm(context)
            } catch (rescheduleError: Exception) {
                Log.e(TAG, "❌ Failed to reschedule GPS alarm: ${rescheduleError.message}")
            }
        }
    }
    
    /**
     * Handle survival signal update alarm
     */
    private fun handleSurvivalUpdate(context: Context) {
        Log.d(TAG, "💓 Survival alarm triggered")
        
        try {
            // Check if survival signal is still enabled
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            
            if (!survivalEnabled) {
                Log.d(TAG, "⚠️ Survival signal disabled - stopping alarms")
                return
            }
            
            // Check screen state and update Firebase
            checkScreenStateAndUpdateFirebase(context)
            
            // Record execution and schedule next alarm
            recordAlarmExecution(context, "survival")
            scheduleSurvivalAlarm(context)
            
            Log.d(TAG, "✅ Survival signal updated, next alarm scheduled")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in survival update: ${e.message}")
            // Try to reschedule even if update failed
            try {
                scheduleSurvivalAlarm(context)
            } catch (rescheduleError: Exception) {
                Log.e(TAG, "❌ Failed to reschedule survival alarm: ${rescheduleError.message}")
            }
        }
    }
    
    /**
     * Check screen state and update Firebase with survival signal
     */
    private fun checkScreenStateAndUpdateFirebase(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        val isScreenCurrentlyOn = isScreenOn(context)
        val wasScreenOn = prefs.getBoolean("flutter.last_screen_state", false)
        
        Log.d(TAG, "📱 Screen: ${if (isScreenCurrentlyOn) "ON" else "OFF"} (was: ${if (wasScreenOn) "ON" else "OFF"})")
        
        // Update Firebase if screen is on (indicating activity)
        if (isScreenCurrentlyOn) {
            updateFirebaseWithSurvivalStatus(context)
        }
        
        // Update stored screen state
        prefs.edit().putBoolean("flutter.last_screen_state", isScreenCurrentlyOn).apply()
    }
    
    /**
     * Update Firebase with GPS location
     */
    private fun updateFirebaseWithLocation(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null) 
            ?: prefs.getString("family_id", null)
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for GPS update")
            return
        }
        
        try {
            val db = FirebaseFirestore.getInstance()
            val location = getCurrentLocation(context)
            
            if (location != null) {
                val locationData = mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy,
                    "timestamp" to FieldValue.serverTimestamp(),
                    "provider" to (location.provider ?: "unknown")
                )
                
                db.collection("families").document(familyId)
                    .update(mapOf("location" to locationData))
                    .addOnSuccessListener {
                        Log.d(TAG, "✅ GPS location updated in Firebase")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ Failed to update GPS location: ${e.message}")
                    }
            } else {
                // CRITICAL FIX: Still update Firebase even without location
                Log.w(TAG, "⚠️ No location available - updating timestamp to show GPS is running")
                
                db.collection("families").document(familyId)
                    .update("lastGpsCheck", FieldValue.serverTimestamp())
                    .addOnSuccessListener {
                        Log.d(TAG, "✅ GPS timestamp updated (no location available)")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ Failed to update GPS timestamp: ${e.message}")
                    }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting location: ${e.message}")
        }
    }
    
    
    /**
     * Update Firebase with survival signal
     */
    private fun updateFirebaseWithSurvivalStatus(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null)
            ?: prefs.getString("family_id", null)
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for survival signal")
            return
        }
        
        try {
            val db = FirebaseFirestore.getInstance()
            
            db.collection("families").document(familyId)
                .update("lastPhoneActivity", FieldValue.serverTimestamp())
                .addOnSuccessListener {
                    Log.d(TAG, "✅ Survival signal updated in Firebase")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "❌ Failed to update survival signal: ${e.message}")
                }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating survival signal: ${e.message}")
        }
    }
    
    /**
     * Get current location from LocationManager
     */
    private fun getCurrentLocation(context: Context): Location? {
        try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            // Check permissions
            val hasPermission = ActivityCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED ||
            ActivityCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            
            if (!hasPermission) {
                Log.w(TAG, "⚠️ No location permissions")
                return null
            }
            
            // Try GPS first, then network
            var location: Location? = null
            
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            }
            
            if (location == null && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            }
            
            return location
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting location: ${e.message}")
            return null
        }
    }
}