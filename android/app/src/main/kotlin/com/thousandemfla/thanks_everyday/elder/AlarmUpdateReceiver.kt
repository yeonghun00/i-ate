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
            
            // CRITICAL FIX: Validate location permissions and system readiness first
            if (!validateLocationPermissions(context)) {
                Log.e(TAG, "❌ GPS alarm scheduling failed: Missing location permissions")
                return
            }
            
            if (!isLocationServiceEnabled(context)) {
                Log.w(TAG, "⚠️ Location service is disabled on device")
            }
            
            // CRITICAL FIX: Add fallback for GPS just like survival monitoring
            var useExactAlarms = true
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.w(TAG, "⚠️ Exact alarms not permitted for GPS, using fallback scheduling")
                    useExactAlarms = false
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
            
            val intervalMillis = 2 * 60 * 1000L // 2 minutes
            val triggerAtMillis = SystemClock.elapsedRealtime() + intervalMillis
            
            Log.d(TAG, "📅 Scheduling GPS alarm:")
            Log.d(TAG, "  - Current time: ${System.currentTimeMillis()}")
            Log.d(TAG, "  - Trigger at (elapsed): $triggerAtMillis")
            Log.d(TAG, "  - Interval: ${intervalMillis / 1000} seconds")
            Log.d(TAG, "  - Use exact alarms: $useExactAlarms")
            
            // CRITICAL FIX: Use same robust scheduling logic as survival monitoring
            if (useExactAlarms) {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                    Log.d(TAG, "  - Using: setExactAndAllowWhileIdle (exact permitted)")
                } else {
                    alarmManager.setExact(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                    Log.d(TAG, "  - Using: setExact (Android 5-)")
                }
            } else {
                // Fallback: Use inexact but reliable scheduling
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                    Log.d(TAG, "  - Using: setAndAllowWhileIdle (fallback)")
                } else {
                    alarmManager.set(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                    Log.d(TAG, "  - Using: set (fallback Android 5-)")
                }
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
            
            val intervalMillis = 2 * 60 * 1000L // 15 minutes
            val triggerAtMillis = SystemClock.elapsedRealtime() + intervalMillis
            
            Log.d(TAG, "📅 Scheduling survival alarm:")
            Log.d(TAG, "  - Current time: ${System.currentTimeMillis()}")
            Log.d(TAG, "  - Trigger at (elapsed): $triggerAtMillis")
            Log.d(TAG, "  - Interval: ${intervalMillis / 1000} seconds")
            
            // Use the most aggressive scheduling available for survival monitoring
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    // Android 12+ with exact alarm permission
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                    Log.d(TAG, "  - Using: setExactAndAllowWhileIdle (Android 12+)")
                } else {
                    // Fallback: Use inexact but more reliable for survival monitoring
                    Log.w(TAG, "❌ Exact alarms not permitted, using setAndAllowWhileIdle")
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                    Log.d(TAG, "  - Using: setAndAllowWhileIdle (fallback)")
                }
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                // Android 6-11: Use setExactAndAllowWhileIdle for doze mode bypass
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
                Log.d(TAG, "  - Using: setExactAndAllowWhileIdle (Android 6-11)")
            } else {
                // Android 5 and below
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
                Log.d(TAG, "  - Using: setExact (Android 5-)")
            }
            
            Log.d(TAG, "✅ Survival signal alarm scheduled successfully for ${intervalMillis / 1000 / 60} minutes interval")
        }
        
        // Smart alarm scheduling - RESTORED: Uses reliable AlarmManager approach
        fun scheduleAlarms(context: Context) {
            val locationEnabled = isLocationTrackingEnabled(context)
            val survivalEnabled = isSurvivalSignalEnabled(context)
            
            Log.d(TAG, "🔄 Smart alarm scheduling - GPS: $locationEnabled, Survival: $survivalEnabled")
            
            if (locationEnabled) {
                // RESTORED: Use proven GPS alarm approach that survives app termination
                Log.d(TAG, "🌍 Scheduling GPS location alarm (reliable AlarmManager approach)")
                scheduleGpsAlarm(context)
            }
            
            if (survivalEnabled) {
                scheduleSurvivalAlarm(context)
            }
            
            if (!locationEnabled && !survivalEnabled) {
                Log.d(TAG, "⚠️ No services enabled - no GPS or survival alarms")
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
        
        // Enable GPS tracking - RESTORED: Uses proven alarm approach
        fun enableLocationTracking(context: Context) {
            Log.d(TAG, "🌍 Enabling GPS location tracking (alarm-based approach)")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", true).apply()
            
            // CRITICAL FIX: Cancel any existing alarm first to avoid duplicates
            cancelGpsAlarm(context)
            
            // RESTORED: Use proven GPS alarm approach that survives app termination
            Log.d(TAG, "🚀 Scheduling GPS alarm for reliable tracking")
            scheduleGpsAlarm(context)
            Log.d(TAG, "✅ GPS alarm scheduled - survives app termination!")
        }
        
        // Disable GPS tracking - RESTORED: Cancels GPS alarms
        fun disableLocationTracking(context: Context) {
            Log.d(TAG, "🌍 Disabling GPS location tracking (cancelling alarms)")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.location_tracking_enabled", false).apply()
            
            // Cancel GPS alarms
            cancelGpsAlarm(context)
            Log.d(TAG, "❌ GPS tracking fully disabled (alarms cancelled)")
        }
        
        // Enable survival signal monitoring
        fun enableSurvivalMonitoring(context: Context) {
            Log.d(TAG, "💓💓💓 ENABLING SURVIVAL SIGNAL MONITORING")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            // Save the setting
            prefs.edit().putBoolean("flutter.survival_signal_enabled", true).apply()
            Log.d(TAG, "✅ Saved flutter.survival_signal_enabled = true to SharedPreferences")
            
            // Initialize screen state for unlock detection
            val currentScreenState = isScreenOn(context)
            setLastScreenState(context, currentScreenState)
            Log.d(TAG, "🔄 Initialized screen state tracking - Current state: ${if (currentScreenState) "ON" else "OFF"}")
            
            // Verify the setting was saved
            val verifyEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            Log.d(TAG, "🔍 Verification: flutter.survival_signal_enabled = $verifyEnabled")
            
            // CRITICAL FIX: Cancel any existing alarm first to avoid duplicates
            cancelSurvivalAlarm(context)
            Log.d(TAG, "❌ Cancelled any existing survival signal alarms")
            
            // Start the initial alarm
            Log.d(TAG, "🚀 Starting initial survival signal alarm...")
            scheduleSurvivalAlarm(context)
            Log.d(TAG, "✅ Initial survival signal alarm scheduled - monitoring will start in 15 minutes")
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
        
        // Track last known screen state to detect unlock events
        private fun getLastScreenState(context: Context): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            return prefs.getBoolean("flutter.last_screen_state", false)
        }
        
        private fun setLastScreenState(context: Context, isOn: Boolean) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.last_screen_state", isOn).apply()
        }
        
        // CRITICAL FIX: Validate all location permissions are granted
        private fun validateLocationPermissions(context: Context): Boolean {
            val fineLocation = ActivityCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            
            val coarseLocation = ActivityCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            
            val backgroundLocation = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                ActivityCompat.checkSelfPermission(
                    context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                true // Not required for API < 29
            }
            
            Log.d(TAG, "📍 Location permissions check:")
            Log.d(TAG, "  - Fine location: $fineLocation")
            Log.d(TAG, "  - Coarse location: $coarseLocation") 
            Log.d(TAG, "  - Background location: $backgroundLocation")
            
            val allGranted = fineLocation && coarseLocation && backgroundLocation
            Log.d(TAG, "  - All permissions granted: $allGranted")
            
            return allGranted
        }
        
        // CRITICAL FIX: Check if device location service is enabled
        private fun isLocationServiceEnabled(context: Context): Boolean {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
            val networkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            
            Log.d(TAG, "📍 Location services check:")
            Log.d(TAG, "  - GPS provider enabled: $gpsEnabled")
            Log.d(TAG, "  - Network provider enabled: $networkEnabled")
            
            val anyEnabled = gpsEnabled || networkEnabled
            Log.d(TAG, "  - Any location service enabled: $anyEnabled")
            
            return anyEnabled
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🔔 AlarmUpdateReceiver triggered with action: ${intent.action}")
        
        when (intent.action) {
            ACTION_GPS_UPDATE -> {
                // RESTORED: GPS alarm handling - this is the reliable approach
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
        
        // CRITICAL FIX: Re-validate permissions at runtime (they can be revoked)
        if (!validateLocationPermissions(context)) {
            Log.e(TAG, "❌ GPS update failed: Location permissions were revoked")
            Log.e(TAG, "💡 GPS tracking will stop until permissions are restored")
            return
        }
        
        // Check if location services are available
        if (!isLocationServiceEnabled(context)) {
            Log.w(TAG, "⚠️ Location services are disabled, GPS update may fail")
        }
        
        Log.d(TAG, "✅ GPS tracking is enabled and permissions validated, proceeding with location update")
        
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
        Log.d(TAG, "💓💓💓 SURVIVAL ALARM TRIGGERED - 15-minute check")
        
        // Check if survival signal is still enabled
        if (!isSurvivalSignalEnabled(context)) {
            Log.d(TAG, "⚠️ Survival signal disabled, skipping update and NOT scheduling next alarm")
            return
        }
        
        Log.d(TAG, "✅ Survival signal enabled, proceeding with 15-minute check")
        
        try {
            // Check current screen state
            val isScreenCurrentlyOn = isScreenOn(context)
            val wasScreenOn = getLastScreenState(context)
            
            Log.d(TAG, "📱 Screen state - Currently: ${if (isScreenCurrentlyOn) "ON" else "OFF"}, Previously: ${if (wasScreenOn) "ON" else "OFF"}")
            
            // Detect unlock event: screen went from OFF to ON
            if (isScreenCurrentlyOn && !wasScreenOn) {
                Log.d(TAG, "🔓🔓🔓 UNLOCK DETECTED - Screen went from OFF to ON!")
                Log.d(TAG, "⚡ This simulates the immediate unlock detection that failed when app was killed")
                updateFirebaseWithSurvivalStatus(context, "unlock_detected")
            } else if (isScreenCurrentlyOn) {
                Log.d(TAG, "✅ Screen ON (continued usage) - Updating Firebase")
                updateFirebaseWithSurvivalStatus(context, "active")
            } else {
                Log.d(TAG, "📱 Screen OFF - NOT updating Firebase (keeps last timestamp)")
            }
            
            // Update stored screen state for next check
            setLastScreenState(context, isScreenCurrentlyOn)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in survival signal update: ${e.message}")
        }
        
        // ALWAYS schedule next alarm (like GPS) - runs every 15 minutes regardless
        try {
            scheduleSurvivalAlarm(context)
            Log.d(TAG, "🔄 Next 15-minute alarm scheduled")
        } catch (e: Exception) {
            Log.e(TAG, "❌ CRITICAL: Failed to schedule next 15-minute alarm: ${e.message}")
        }
    }
    
    private fun updateFirebaseWithLocation(context: Context) {
        // CRITICAL FIX: Add comprehensive startup validation
        Log.d(TAG, "🔍 GPS Update - Performing startup validation...")
        
        // Get family ID
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null)
        
        // DEBUG: List all keys to debug SharedPreferences issue
        val allKeys = prefs.all
        Log.d(TAG, "🔍 All SharedPreferences keys: $allKeys")
        Log.d(TAG, "🔍 Looking for flutter.family_id: $familyId")
        
        // CRITICAL DEBUG: Try different key variations to find the actual key
        val testKeys = listOf("flutter.family_id", "family_id", "flutter.flutter.family_id")
        for (testKey in testKeys) {
            val testValue = prefs.getString(testKey, null)
            Log.d(TAG, "🧪 Test key '$testKey': $testValue")
        }
        
        // CRITICAL DEBUG: Check if key exists in different ways
        val keyExists = prefs.contains("flutter.family_id")
        Log.d(TAG, "🔍 Key 'flutter.family_id' exists: $keyExists")
        
        // CRITICAL DEBUG: Try to get the exact key from the all keys map
        val exactValue = allKeys["flutter.family_id"]
        Log.d(TAG, "🔍 Direct map access allKeys['flutter.family_id']: $exactValue")
        
        // CRITICAL FIX: Enhanced debug logging to verify the key fix
        if (familyId != null) {
            Log.d(TAG, "✅ FIXED: Successfully retrieved family_id from SharedPreferences: $familyId")
        } else {
            Log.e(TAG, "❌ STILL NULL: family_id not found - checking all family-related keys...")
            val familyKeys = prefs.all.filterKeys { it.contains("family") }
            Log.e(TAG, "🔍 All family-related keys: $familyKeys")
        }
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for GPS update")
            return
        }
        
        // CRITICAL FIX: Verify location tracking is still enabled (could be disabled during reboot)
        val locationTrackingEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
        if (!locationTrackingEnabled) {
            Log.w(TAG, "⚠️ Location tracking was disabled during reboot - cancelling GPS alarms")
            cancelGpsAlarm(context)
            return
        }
        
        Log.d(TAG, "📍 Getting GPS location for family: $familyId")
        Log.d(TAG, "✅ Location tracking confirmed enabled after reboot")
        
        try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            // CRITICAL FIX: Enhanced permission checking with detailed logging
            val fineLocationGranted = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val coarseLocationGranted = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val backgroundLocationGranted = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
            } else {
                true // Not required on Android 9 and below
            }
            
            Log.d(TAG, "🔐 Location permissions status:")
            Log.d(TAG, "  - Fine location: $fineLocationGranted")
            Log.d(TAG, "  - Coarse location: $coarseLocationGranted")
            Log.d(TAG, "  - Background location: $backgroundLocationGranted (required for Android 10+)")
            
            if (!fineLocationGranted && !coarseLocationGranted) {
                Log.e(TAG, "❌ No location permissions granted - cannot get GPS location")
                return
            }
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q && !backgroundLocationGranted) {
                Log.w(TAG, "⚠️ Background location permission not granted - may not work after reboot on Android 10+")
                // Continue anyway - some devices may still work
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
                        
                        // CRITICAL FIX: Add retry mechanism for Firebase connectivity issues during boot
                        if (e.message?.contains("network") == true || e.message?.contains("unavailable") == true) {
                            Log.d(TAG, "🔄 GPS: Network/Firebase not ready, scheduling retry in 30 seconds...")
                            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                // Retry GPS update
                                updateFirebaseWithLocation(context)
                            }, 30000)
                        }
                    }
            } else {
                Log.d(TAG, "⚠️ No location available - skipping Firebase update")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting GPS location: ${e.message}")
            // Don't update Firebase on error - keep original behavior
        }
    }
    
    private fun updateFirebaseWithSurvivalStatus(context: Context, status: String) {
        // Get family ID
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val familyId = prefs.getString("flutter.family_id", null)
        
        // CRITICAL FIX: Enhanced debug logging to verify the key fix
        if (familyId != null) {
            Log.d(TAG, "✅ FIXED: Successfully retrieved family_id for survival signal: $familyId")
        } else {
            Log.e(TAG, "❌ STILL NULL: family_id not found for survival signal - checking all family-related keys...")
            val familyKeys = prefs.all.filterKeys { it.contains("family") }
            Log.e(TAG, "🔍 All family-related keys: $familyKeys")
        }
        
        if (familyId.isNullOrEmpty()) {
            Log.e(TAG, "❌ No family ID found for survival signal update")
            return
        }
        
        Log.d(TAG, "🔥 Updating Firebase with original structure for family: $familyId")
        
        try {
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
                    
                    // CRITICAL FIX: Add retry mechanism for Firebase connectivity issues during boot
                    if (e.message?.contains("network") == true || e.message?.contains("unavailable") == true) {
                        Log.d(TAG, "🔄 Network/Firebase not ready, scheduling retry in 30 seconds...")
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            updateFirebaseWithSurvivalStatus(context, status)
                        }, 30000)
                    }
                }
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ Critical error in Firebase update: ${e.message}")
            // Don't crash - survival monitoring should continue
        }
    }
}