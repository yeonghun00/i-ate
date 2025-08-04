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
        
        // Separate actions for each service
        private const val ACTION_GPS_UPDATE = "com.thousandemfla.thanks_everyday.GPS_UPDATE"
        private const val ACTION_SURVIVAL_UPDATE = "com.thousandemfla.thanks_everyday.SURVIVAL_UPDATE"
        
        // Schedule GPS location tracking alarm
        fun scheduleGpsAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            Log.d(TAG, "🌍 Scheduling GPS location alarm...")
            
            // Check if we can schedule exact alarms (Android 12+)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.e(TAG, "❌ Cannot schedule GPS exact alarms - permission denied")
                    return
                }
            }
            
            val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = ACTION_GPS_UPDATE
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                GPS_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val intervalMillis = 2 * 60 * 1000L // 2 minutes for testing
            val triggerAtMillis = SystemClock.elapsedRealtime() + intervalMillis
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            }
            
            Log.d(TAG, "✅ GPS alarm scheduled successfully for ${intervalMillis / 1000 / 60} minutes interval")
        }
        
        // Schedule survival signal monitoring alarm
        fun scheduleSurvivalAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            Log.d(TAG, "💓 Scheduling survival signal alarm...")
            
            val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = ACTION_SURVIVAL_UPDATE
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                SURVIVAL_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val intervalMillis = 2 * 60 * 1000L // 2 minutes for testing
            
            // Check if we can schedule exact alarms (Android 12+)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.e(TAG, "❌ Cannot schedule exact alarms - using inexact alarms as fallback")
                    // Use inexact alarm as fallback
                    alarmManager.setInexactRepeating(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        SystemClock.elapsedRealtime() + intervalMillis,
                        intervalMillis,
                        pendingIntent
                    )
                    Log.d(TAG, "✅ Survival signal inexact alarm scheduled (fallback)")
                    return
                }
            }
            val triggerAtMillis = SystemClock.elapsedRealtime() + intervalMillis
            
            Log.d(TAG, "📅 Scheduling survival alarm:")
            Log.d(TAG, "  - Current time: ${System.currentTimeMillis()}")
            Log.d(TAG, "  - Trigger at (elapsed): $triggerAtMillis")
            Log.d(TAG, "  - Interval: ${intervalMillis / 1000} seconds")
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
                Log.d(TAG, "  - Using: setExactAndAllowWhileIdle")
            } else {
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
                Log.d(TAG, "  - Using: setExact")
            }
            
            Log.d(TAG, "✅ Survival signal alarm scheduled successfully for ${intervalMillis / 1000 / 60} minutes interval")
        }
        
        // Smart alarm scheduling - schedule based on what's enabled
        fun scheduleAlarms(context: Context) {
            val locationEnabled = isLocationTrackingEnabled(context)
            val survivalEnabled = isSurvivalSignalEnabled(context)
            
            Log.d(TAG, "🔄 Smart alarm scheduling - GPS: $locationEnabled, Survival: $survivalEnabled")
            
            if (locationEnabled) {
                scheduleGpsAlarm(context)
            }
            
            if (survivalEnabled) {
                scheduleSurvivalAlarm(context)
            }
            
            if (!locationEnabled && !survivalEnabled) {
                Log.d(TAG, "⚠️ No services enabled - no alarms scheduled")
            }
        }
        
        // Cancel GPS alarm only
        fun cancelGpsAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = ACTION_GPS_UPDATE
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                GPS_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "❌ GPS alarm cancelled")
        }
        
        // Cancel survival signal alarm only
        fun cancelSurvivalAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val intent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = ACTION_SURVIVAL_UPDATE
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                SURVIVAL_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "❌ Survival signal alarm cancelled")
        }
        
        // Cancel all alarms (for compatibility)
        fun cancelAlarms(context: Context) {
            Log.d(TAG, "❌ Cancelling all alarms")
            cancelGpsAlarm(context)
            cancelSurvivalAlarm(context)
        }
        
        // Enable GPS tracking
        fun enableLocationTracking(context: Context) {
            Log.d(TAG, "🌍 Enabling GPS location tracking")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", true).apply()
            
            // CRITICAL FIX: Cancel any existing alarm first to avoid duplicates
            cancelGpsAlarm(context)
            
            // Start the initial alarm
            scheduleGpsAlarm(context)
            Log.d(TAG, "✅ Initial GPS alarm scheduled - location tracking will start immediately")
        }
        
        // Disable GPS tracking
        fun disableLocationTracking(context: Context) {
            Log.d(TAG, "🌍 Disabling GPS location tracking")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", false).apply()
            cancelGpsAlarm(context)
        }
        
        // Enable survival signal monitoring
        fun enableSurvivalMonitoring(context: Context) {
            Log.d(TAG, "💓💓💓 ENABLING SURVIVAL SIGNAL MONITORING")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            // Save the setting
            prefs.edit().putBoolean("flutter.survival_signal_enabled", true).apply()
            Log.d(TAG, "✅ Saved flutter.survival_signal_enabled = true to SharedPreferences")
            
            // Verify the setting was saved
            val verifyEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            Log.d(TAG, "🔍 Verification: flutter.survival_signal_enabled = $verifyEnabled")
            
            // CRITICAL FIX: Cancel any existing alarm first to avoid duplicates
            cancelSurvivalAlarm(context)
            Log.d(TAG, "❌ Cancelled any existing survival signal alarms")
            
            // Start the initial alarm
            Log.d(TAG, "🚀 Starting initial survival signal alarm...")
            scheduleSurvivalAlarm(context)
            Log.d(TAG, "✅ Initial survival signal alarm scheduled - monitoring will start in 2 minutes")
        }
        
        // Disable survival signal monitoring
        fun disableSurvivalMonitoring(context: Context) {
            Log.d(TAG, "💓 Disabling survival signal monitoring")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.survival_signal_enabled", false).apply()
            cancelSurvivalAlarm(context)
        }
        
        // Check if location tracking is enabled
        private fun isLocationTrackingEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            return prefs.getBoolean("flutter.location_tracking_enabled", false)
        }
        
        // Check if survival signal is enabled
        private fun isSurvivalSignalEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            Log.d(TAG, "🔍 SharedPreferences check: flutter.survival_signal_enabled = $isEnabled")
            
            // Debug: Show all survival-related keys
            val allKeys = prefs.all.filterKeys { it.contains("survival") }
            Log.d(TAG, "🔍 All survival keys in SharedPreferences: $allKeys")
            
            return isEnabled
        }
        
        // Check if screen is currently ON
        private fun isScreenOn(context: Context): Boolean {
            return try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT_WATCH) {
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
        Log.d(TAG, "🌍 GPS ALARM TRIGGERED - Handling GPS location update")
        
        // Check if GPS is still enabled
        if (!isLocationTrackingEnabled(context)) {
            Log.d(TAG, "⚠️ GPS tracking disabled, skipping update")
            return
        }
        
        Log.d(TAG, "✅ GPS tracking is enabled, proceeding with location update")
        
        try {
            // Update Firebase with GPS location
            updateFirebaseWithLocation(context)
            
            // Schedule next GPS alarm
            scheduleGpsAlarm(context)
            Log.d(TAG, "🔄 Next GPS alarm scheduled for 2 minutes")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in GPS update: ${e.message}")
            // Still schedule next update even if this one failed
            scheduleGpsAlarm(context)
            Log.d(TAG, "🔄 Next GPS alarm scheduled despite error")
        }
    }
    
    private fun handleSurvivalUpdate(context: Context) {
        Log.d(TAG, "💓💓💓 SURVIVAL ALARM TRIGGERED - Starting survival signal update")
        
        // Check if survival signal is still enabled
        val isEnabled = isSurvivalSignalEnabled(context)
        Log.d(TAG, "🔍 Survival signal enabled check: $isEnabled")
        
        if (!isEnabled) {
            Log.d(TAG, "⚠️ Survival signal disabled, skipping update and NOT scheduling next alarm")
            return
        }
        
        Log.d(TAG, "✅ Survival signal is enabled, proceeding with update")
        
        try {
            // Check screen state
            val isScreenOn = isScreenOn(context)
            val screenState = if (isScreenOn) "on" else "off"
            
            Log.d(TAG, "📱 Screen is currently: $screenState")
            
            // Always update Firebase - this shows current activity status
            if (isScreenOn) {
                Log.d(TAG, "✅ Screen is ON - User is actively using phone")
                updateFirebaseWithSurvivalStatus(context, "active", screenState)
            } else {
                Log.d(TAG, "📱 Screen is OFF - User not currently active, keeping last activity time")
                // Don't update lastPhoneActivity when screen is off - this preserves the timestamp
                // of when user was last actually active
            }
            
            // Schedule next survival signal alarm
            Log.d(TAG, "🔄 Scheduling next survival signal alarm in 2 minutes...")
            scheduleSurvivalAlarm(context)
            Log.d(TAG, "✅ Next survival signal alarm scheduled successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in survival signal update: ${e.message}")
            // Still schedule next update even if this one failed
            scheduleSurvivalAlarm(context)
        }
    }
    
    private fun updateFirebaseWithLocation(context: Context) {
        // Get family ID
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null)
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for GPS update")
            return
        }
        
        Log.d(TAG, "📍 Getting GPS location for family: $familyId")
        
        try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            // Check if we have location permissions
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "❌ Location permissions not granted")
                return
            }
            
            // Try to get last known location from GPS provider
            var location: Location? = null
            
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                Log.d(TAG, "📡 GPS provider location: $location")
            }
            
            // Fallback to network provider
            if (location == null && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                Log.d(TAG, "📶 Network provider location: $location")
            }
            
            // Update Firebase with location data
            val db = FirebaseFirestore.getInstance()
            
            if (location != null) {
                val locationData = mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy,
                    "timestamp" to FieldValue.serverTimestamp(),
                    "provider" to location.provider,
                    "speed" to if (location.hasSpeed()) location.speed else null,
                    "altitude" to if (location.hasAltitude()) location.altitude else null
                )
                
                val data = mapOf(
                    "location" to locationData  // Keep original structure - just location field
                )
                
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
            // Don't update Firebase on error - keep original behavior
        }
    }
    
    private fun updateFirebaseWithSurvivalStatus(context: Context, status: String, screenState: String) {
        // Get family ID
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null)
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for survival signal update")
            return
        }
        
        Log.d(TAG, "🔥 Updating Firebase with original structure for family: $familyId")
        
        val db = FirebaseFirestore.getInstance()
        
        // Keep original structure - just update lastPhoneActivity
        val data = mapOf(
            "lastPhoneActivity" to FieldValue.serverTimestamp()
        )
        
        db.collection("families").document(familyId)
            .update(data)
            .addOnSuccessListener {
                Log.d(TAG, "✅ Survival signal Firebase update successful - lastPhoneActivity updated")
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "❌ Survival signal Firebase update failed: ${e.message}")
            }
    }
}