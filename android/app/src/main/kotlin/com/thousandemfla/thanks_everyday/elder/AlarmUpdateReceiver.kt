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
        private const val GPS_REQUEST_CODE = 1001
        private const val SURVIVAL_REQUEST_CODE = 1002
        
        // Actions for each service type
        private const val ACTION_GPS_UPDATE = "com.thousandemfla.thanks_everyday.GPS_UPDATE"
        private const val ACTION_SURVIVAL_UPDATE = "com.thousandemfla.thanks_everyday.SURVIVAL_UPDATE"
        
        // 2-minute interval for both GPS and survival monitoring
        private const val INTERVAL_MILLIS = 2 * 60 * 1000L
        
        /**
         * Schedule GPS location tracking alarm - runs every 2 minutes
         */
        fun scheduleGpsAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                
                Log.d(TAG, "🌍 Scheduling GPS alarm with 2-minute interval")
                
                val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                    action = ACTION_GPS_UPDATE
                }
                
                val pendingIntent = createPendingIntent(context, GPS_REQUEST_CODE, intent)
                val triggerAtMillis = SystemClock.elapsedRealtime() + INTERVAL_MILLIS
                
                scheduleAlarmWithBestMethod(alarmManager, triggerAtMillis, pendingIntent, "GPS")
                
                Log.d(TAG, "✅ GPS alarm scheduled for ${INTERVAL_MILLIS / 1000 / 60} minutes")
                
                // Record scheduling time for debugging
                try {
                    val miuiPrefs = context.getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
                    miuiPrefs.edit()
                        .putLong("last_gps_alarm_scheduled", System.currentTimeMillis())
                        .putString("gps_schedule_trigger", "boot_or_manual")
                        .apply()
                } catch (prefError: Exception) {
                    Log.w(TAG, "Could not record GPS scheduling time: ${prefError.message}")
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to schedule GPS alarm: ${e.message}")
                throw e
            }
        }
        
        /**
         * Schedule survival signal monitoring alarm - runs every 2 minutes
         */
        fun scheduleSurvivalAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                
                Log.d(TAG, "💓 Scheduling survival alarm with 2-minute interval")
                
                val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                    action = ACTION_SURVIVAL_UPDATE
                }
                
                val pendingIntent = createPendingIntent(context, SURVIVAL_REQUEST_CODE, intent)
                val triggerAtMillis = SystemClock.elapsedRealtime() + INTERVAL_MILLIS
                
                scheduleAlarmWithBestMethod(alarmManager, triggerAtMillis, pendingIntent, "Survival")
                
                Log.d(TAG, "✅ Survival alarm scheduled for ${INTERVAL_MILLIS / 1000 / 60} minutes")
                
                // Record scheduling time for debugging
                try {
                    val miuiPrefs = context.getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
                    miuiPrefs.edit()
                        .putLong("last_survival_alarm_scheduled", System.currentTimeMillis())
                        .putString("survival_schedule_trigger", "boot_or_manual")
                        .apply()
                } catch (prefError: Exception) {
                    Log.w(TAG, "Could not record survival scheduling time: ${prefError.message}")
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to schedule survival alarm: ${e.message}")
                throw e
            }
        }
        
        /**
         * Schedule both alarms after device boot - SIMPLIFIED FOR BOOT RELIABILITY
         */
        fun scheduleAlarms(context: Context) {
            Log.d(TAG, "🚀 BOOT: Scheduling alarms after device boot")
            
            try {
                // CRITICAL FIX: Always schedule both alarms after boot regardless of preferences
                // This ensures monitoring is restored even if SharedPreferences aren't immediately available
                // The individual alarm handlers will check preferences before executing
                
                Log.d(TAG, "📍 BOOT: Force-scheduling GPS alarm (will check preferences during execution)")
                scheduleGpsAlarm(context)
                
                Log.d(TAG, "💓 BOOT: Force-scheduling survival alarm (will check preferences during execution)")
                scheduleSurvivalAlarm(context)
                
                Log.d(TAG, "✅ BOOT: Both alarms scheduled - they will self-check preferences during execution")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ BOOT: Error scheduling alarms after boot: ${e.message}")
                // Don't give up - try individual scheduling
                try {
                    Log.d(TAG, "🔄 BOOT: Trying individual alarm scheduling as fallback...")
                    scheduleGpsAlarm(context)
                } catch (gpsError: Exception) {
                    Log.e(TAG, "❌ BOOT: GPS alarm fallback failed: ${gpsError.message}")
                }
                
                try {
                    scheduleSurvivalAlarm(context)
                } catch (survivalError: Exception) {
                    Log.e(TAG, "❌ BOOT: Survival alarm fallback failed: ${survivalError.message}")
                }
            }
        }
        
        /**
         * Cancel GPS alarm
         */
        fun cancelGpsAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = ACTION_GPS_UPDATE
            }
            
            val pendingIntent = createPendingIntent(context, GPS_REQUEST_CODE, intent)
            alarmManager.cancel(pendingIntent)
            
            Log.d(TAG, "❌ GPS alarm cancelled")
        }
        
        /**
         * Cancel survival signal alarm
         */
        fun cancelSurvivalAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = ACTION_SURVIVAL_UPDATE
            }
            
            val pendingIntent = createPendingIntent(context, SURVIVAL_REQUEST_CODE, intent)
            alarmManager.cancel(pendingIntent)
            
            Log.d(TAG, "❌ Survival alarm cancelled")
        }
        
        /**
         * Cancel all alarms
         */
        fun cancelAlarms(context: Context) {
            Log.d(TAG, "❌ Cancelling all alarms")
            cancelGpsAlarm(context)
            cancelSurvivalAlarm(context)
        }
        
        /**
         * Enable GPS tracking and start alarms
         */
        fun enableLocationTracking(context: Context) {
            Log.d(TAG, "🌍 Enabling GPS location tracking")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", true).apply()
            
            cancelGpsAlarm(context) // Cancel existing alarm to avoid duplicates
            scheduleGpsAlarm(context)
            
            Log.d(TAG, "✅ GPS tracking enabled with 2-minute intervals")
        }
        
        /**
         * Disable GPS tracking and stop alarms
         */
        fun disableLocationTracking(context: Context) {
            Log.d(TAG, "🌍 Disabling GPS location tracking")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", false).apply()
            
            cancelGpsAlarm(context)
            
            Log.d(TAG, "❌ GPS tracking disabled")
        }
        
        /**
         * Enable survival monitoring and start alarms
         */
        fun enableSurvivalMonitoring(context: Context) {
            Log.d(TAG, "💓 Enabling survival signal monitoring")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.survival_signal_enabled", true).apply()
            
            // Initialize screen state tracking
            val currentScreenState = isScreenOn(context)
            setLastScreenState(context, currentScreenState)
            
            cancelSurvivalAlarm(context) // Cancel existing alarm to avoid duplicates
            scheduleSurvivalAlarm(context)
            
            Log.d(TAG, "✅ Survival monitoring enabled with 2-minute intervals")
        }
        
        /**
         * Disable survival monitoring and stop alarms
         */
        fun disableSurvivalMonitoring(context: Context) {
            Log.d(TAG, "💓 Disabling survival signal monitoring")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.survival_signal_enabled", false).apply()
            
            cancelSurvivalAlarm(context)
            
            Log.d(TAG, "❌ Survival monitoring disabled")
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
            pendingIntent: PendingIntent,
            type: String
        ) {
            try {
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                        if (alarmManager.canScheduleExactAlarms()) {
                            alarmManager.setExactAndAllowWhileIdle(
                                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                                triggerAtMillis,
                                pendingIntent
                            )
                            Log.d(TAG, "$type alarm: Using setExactAndAllowWhileIdle (Android 12+)")
                        } else {
                            alarmManager.setAndAllowWhileIdle(
                                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                                triggerAtMillis,
                                pendingIntent
                            )
                            Log.d(TAG, "$type alarm: Using setAndAllowWhileIdle (fallback)")
                        }
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.ELAPSED_REALTIME_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                        Log.d(TAG, "$type alarm: Using setExactAndAllowWhileIdle (Android 6+)")
                    }
                    else -> {
                        alarmManager.setExact(
                            AlarmManager.ELAPSED_REALTIME_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                        Log.d(TAG, "$type alarm: Using setExact")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to schedule $type alarm: ${e.message}")
                throw e
            }
        }
        
        private fun isLocationTrackingEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            return prefs.getBoolean("flutter.location_tracking_enabled", false)
        }
        
        private fun isSurvivalSignalEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            return prefs.getBoolean("flutter.survival_signal_enabled", false)
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
        
        private fun getLastScreenState(context: Context): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            return prefs.getBoolean("flutter.last_screen_state", false)
        }
        
        private fun setLastScreenState(context: Context, isOn: Boolean) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.last_screen_state", isOn).apply()
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🔔 AlarmUpdateReceiver triggered with action: ${intent.action}")
        
        when (intent.action) {
            ACTION_GPS_UPDATE -> {
                handleGpsUpdate(context)
            }
            ACTION_SURVIVAL_UPDATE -> {
                handleSurvivalUpdate(context)
            }
            else -> {
                Log.w(TAG, "⚠️ Unknown action: ${intent.action}")
            }
        }
    }
    
    private fun handleGpsUpdate(context: Context) {
        Log.d(TAG, "🌍 GPS alarm triggered - 2-minute check")
        
        // Check if GPS tracking is still enabled - ENHANCED WITH FALLBACK
        val locationEnabled = try {
            isLocationTrackingEnabled(context)
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Could not check GPS preferences, defaulting to enabled: ${e.message}")
            true // Default to enabled if we can't check preferences
        }
        
        if (!locationEnabled) {
            Log.d(TAG, "⚠️ GPS tracking disabled, skipping update")
            return
        }
        
        Log.d(TAG, "✅ GPS tracking enabled, updating location")
        
        try {
            updateFirebaseWithLocation(context)
            
            // Record execution time for debugging
            try {
                val miuiPrefs = context.getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
                miuiPrefs.edit()
                    .putLong("last_gps_execution", System.currentTimeMillis())
                    .apply()
                Log.d(TAG, "📝 GPS execution time recorded")
            } catch (prefError: Exception) {
                Log.w(TAG, "Could not record GPS execution time: ${prefError.message}")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating GPS location: ${e.message}")
        }
        
        // Schedule next GPS alarm
        try {
            scheduleGpsAlarm(context)
            Log.d(TAG, "🔄 Next GPS alarm scheduled")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to schedule next GPS alarm: ${e.message}")
        }
    }
    
    private fun handleSurvivalUpdate(context: Context) {
        Log.d(TAG, "💓 Survival alarm triggered - 2-minute check")
        
        // Check if survival signal is still enabled - ENHANCED WITH FALLBACK
        val survivalEnabled = try {
            isSurvivalSignalEnabled(context)
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Could not check survival preferences, defaulting to enabled: ${e.message}")
            true // Default to enabled if we can't check preferences
        }
        
        if (!survivalEnabled) {
            Log.d(TAG, "⚠️ Survival signal disabled, skipping update")
            return
        }
        
        Log.d(TAG, "✅ Survival signal enabled, checking screen state")
        
        try {
            // Check screen state for unlock detection
            val isScreenCurrentlyOn = isScreenOn(context)
            val wasScreenOn = getLastScreenState(context)
            
            Log.d(TAG, "📱 Screen state - Currently: ${if (isScreenCurrentlyOn) "ON" else "OFF"}, Previously: ${if (wasScreenOn) "ON" else "OFF"}")
            
            // Detect unlock event: screen went from OFF to ON
            if (isScreenCurrentlyOn && !wasScreenOn) {
                Log.d(TAG, "🔓 UNLOCK DETECTED - Screen went from OFF to ON!")
                updateFirebaseWithSurvivalStatus(context, "unlock_detected")
            } else if (isScreenCurrentlyOn) {
                Log.d(TAG, "✅ Screen ON (continued usage)")
                updateFirebaseWithSurvivalStatus(context, "active")
            } else {
                Log.d(TAG, "📱 Screen OFF - keeping last timestamp")
            }
            
            // Update stored screen state for next check
            setLastScreenState(context, isScreenCurrentlyOn)
            
            // Record execution time for debugging
            try {
                val miuiPrefs = context.getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
                miuiPrefs.edit()
                    .putLong("last_survival_execution", System.currentTimeMillis())
                    .apply()
                Log.d(TAG, "📝 Survival execution time recorded")
            } catch (prefError: Exception) {
                Log.w(TAG, "Could not record survival execution time: ${prefError.message}")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in survival signal update: ${e.message}")
        }
        
        // Schedule next survival alarm
        try {
            scheduleSurvivalAlarm(context)
            Log.d(TAG, "🔄 Next survival alarm scheduled")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to schedule next survival alarm: ${e.message}")
        }
    }
    
    private fun updateFirebaseWithLocation(context: Context) {
        Log.d(TAG, "🔍 Updating Firebase with GPS location")
        
        // Get family ID
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null) 
            ?: prefs.getString("family_id", null)
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for GPS update")
            return
        }
        
        Log.d(TAG, "📍 Getting GPS location for family: $familyId")
        
        try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            // Check location permissions
            val hasLocationPermission = ActivityCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED ||
            ActivityCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            
            if (!hasLocationPermission) {
                Log.d(TAG, "⚠️ No location permissions - skipping GPS update")
                return
            }
            
            // Get last known location
            var location: Location? = null
            
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                Log.d(TAG, "📡 GPS provider location: $location")
            }
            
            if (location == null && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                Log.d(TAG, "📶 Network provider location: $location")
            }
            
            // Update Firebase
            if (location != null) {
                val db = FirebaseFirestore.getInstance()
                
                val locationData = mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy,
                    "timestamp" to FieldValue.serverTimestamp(),
                    "provider" to location.provider,
                    "speed" to if (location.hasSpeed()) location.speed else null,
                    "altitude" to if (location.hasAltitude()) location.altitude else null
                )
                
                val data = mapOf("location" to locationData)
                
                db.collection("families").document(familyId)
                    .update(data)
                    .addOnSuccessListener {
                        Log.d(TAG, "✅ GPS Firebase update successful - Lat: ${location.latitude}, Lng: ${location.longitude}")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ GPS Firebase update failed: ${e.message}")
                    }
            } else {
                Log.d(TAG, "⚠️ No location available - skipping Firebase update")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting GPS location: ${e.message}")
        }
    }
    
    private fun updateFirebaseWithSurvivalStatus(context: Context, status: String) {
        // Get family ID
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null)
            ?: prefs.getString("family_id", null)
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for survival signal update")
            return
        }
        
        Log.d(TAG, "🔥 Updating Firebase survival signal for family: $familyId")
        
        try {
            val db = FirebaseFirestore.getInstance()
            
            val data = mapOf("lastPhoneActivity" to FieldValue.serverTimestamp())
            
            db.collection("families").document(familyId)
                .update(data)
                .addOnSuccessListener {
                    Log.d(TAG, "✅ Survival signal Firebase update successful - lastPhoneActivity updated")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "❌ Survival signal Firebase update failed: ${e.message}")
                }
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ Critical error in Firebase survival update: ${e.message}")
        }
    }
}