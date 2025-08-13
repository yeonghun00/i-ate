package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

class ScreenStateReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "ScreenStateReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🔔🔔🔔 SCREEN STATE RECEIVER TRIGGERED: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> {
                Log.d(TAG, "📱 Screen turned ON (but phone may still be locked)")
                // Screen on doesn't mean user is active (could still be locked)
                // We only update on USER_PRESENT for accuracy
            }
            Intent.ACTION_USER_PRESENT -> {
                Log.d(TAG, "🔓🔓🔓 USER UNLOCKED PHONE - IMMEDIATE FIREBASE UPDATE!")
                Log.d(TAG, "⚡ This catches brief usage like checking time!")
                updateLastPhoneActivity(context)
                
                // ADD GPS LOCATION UPDATE: Use the same screen-on trigger as survival signals
                updateGpsLocationOnScreenUnlock(context)
                
                // SIMPLE FIX: Use the same simple GPS backup mechanism as survival
                checkAndInitializeGpsAlarmsSimple(context)
            }
            else -> {
                Log.w(TAG, "⚠️ Unknown screen action received: ${intent.action}")
            }
        }
    }
    
    private fun updateLastPhoneActivity(context: Context) {
        try {
            Log.d(TAG, "⚡⚡⚡ PROCESSING IMMEDIATE UNLOCK DETECTION")
            
            // Check if monitoring is enabled
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            
            Log.d(TAG, "🔍 Survival signal monitoring enabled: $isEnabled")
            
            if (!isEnabled) {
                Log.d(TAG, "❌ Monitoring disabled - skipping immediate update")
                return
            }
            
            // Get family info - CRITICAL FIX: Try both key variations
            var familyId = prefs.getString("flutter.family_id", null)
            if (familyId == null) {
                familyId = prefs.getString("family_id", null)
                Log.d(TAG, "🔄 Using fallback key 'family_id': $familyId")
            }
            if (familyId == null) {
                Log.w(TAG, "⚠️ No family ID found - cannot update Firebase")
                return
            }
            
            Log.d(TAG, "🚀 Updating Firebase immediately for family: $familyId")
            Log.d(TAG, "💡 This update happens INSTANTLY when user unlocks (even for 2 seconds!)")
            
            // Update Firebase with real phone activity
            val firestore = FirebaseFirestore.getInstance()
            firestore.collection("families")
                .document(familyId)
                .update("lastPhoneActivity", FieldValue.serverTimestamp())
                .addOnSuccessListener {
                    Log.d(TAG, "✅✅✅ IMMEDIATE UPDATE SUCCESS - Firebase shows user was active NOW!")
                    Log.d(TAG, "🎯 Brief usage detected and recorded (like checking time)")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "❌ Immediate Firebase update failed: ${e.message}")
                }
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in immediate unlock detection: ${e.message}")
        }
    }
    
    // SIMPLE FIX: Simple GPS backup mechanism using the same pattern as survival monitoring  
    private fun checkAndInitializeGpsAlarmsSimple(context: Context) {
        try {
            Log.d(TAG, "🌍 SIMPLE: Checking GPS alarm status as backup...")
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            if (!locationEnabled) {
                Log.d(TAG, "⚠️ GPS tracking disabled - no backup initialization needed")
                return
            }
            
            Log.d(TAG, "✅ GPS tracking is enabled - checking if alarms are working...")
            
            // Simple stale check: If GPS hasn't executed recently, restart it
            val miuiAlarmPrefs = context.getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
            val lastGpsExecution = miuiAlarmPrefs.getLong("last_gps_execution", 0)
            val currentTime = System.currentTimeMillis()
            val timeSinceLastExecution = currentTime - lastGpsExecution
            
            // Simple threshold: 5 minutes (same as reduced MIUI survival threshold)
            val gpsStaleThreshold = 5 * 60 * 1000L
            
            if (lastGpsExecution == 0L || timeSinceLastExecution > gpsStaleThreshold) {
                Log.w(TAG, "🔄 GPS alarms appear stale - reinitializing...")
                Log.d(TAG, "  - Last GPS execution: ${if (lastGpsExecution == 0L) "NEVER" else "${timeSinceLastExecution / 1000 / 60} min ago"}")
                
                // Simple restart: Cancel and reschedule (just like survival)
                try {
                    AlarmUpdateReceiver.cancelGpsAlarm(context)
                    AlarmUpdateReceiver.scheduleGpsAlarm(context)
                    Log.d(TAG, "✅ GPS alarm backup initialization completed successfully")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Failed to restart GPS alarm: ${e.message}")
                }
            } else {
                Log.d(TAG, "✅ GPS alarms appear to be working normally")
                Log.d(TAG, "  - Last execution: ${timeSinceLastExecution / 1000 / 60} minutes ago")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in simple GPS alarm backup check: ${e.message}")
        }
    }
    
    // ADD GPS LOCATION UPDATE: Update GPS location when screen unlocks (same trigger as survival signals)
    private fun updateGpsLocationOnScreenUnlock(context: Context) {
        try {
            Log.d(TAG, "🌍🔓 SCREEN UNLOCK GPS UPDATE - Using same trigger as survival signals")
            
            // Check if GPS tracking is enabled (same pattern as survival signal check)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            Log.d(TAG, "🔍 GPS tracking enabled: $locationEnabled")
            
            if (!locationEnabled) {
                Log.d(TAG, "❌ GPS tracking disabled - skipping screen unlock GPS update")
                return
            }
            
            // Get family info - CRITICAL FIX: Try both key variations (same as survival)
            var familyId = prefs.getString("flutter.family_id", null)
            if (familyId == null) {
                familyId = prefs.getString("family_id", null)
                Log.d(TAG, "🔄 Using fallback key 'family_id' for GPS: $familyId")
            }
            if (familyId == null) {
                Log.w(TAG, "⚠️ No family ID found - cannot update GPS location")
                return
            }
            
            Log.d(TAG, "🚀 Updating GPS location immediately for family: $familyId")
            Log.d(TAG, "💡 This GPS update happens INSTANTLY when user unlocks (like survival signals!)")
            
            // Use existing GPS update method from AlarmUpdateReceiver
            updateGpsLocationImmediate(context, familyId)
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in screen unlock GPS update: ${e.message}")
        }
    }
    
    // Immediate GPS location update using existing location methods
    private fun updateGpsLocationImmediate(context: Context, familyId: String) {
        try {
            Log.d(TAG, "📍 Getting immediate GPS location for screen unlock...")
            
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            // Quick permission check - if no permissions, skip GPS update
            val hasLocationPermission = try {
                androidx.core.content.ContextCompat.checkSelfPermission(
                    context, android.Manifest.permission.ACCESS_FINE_LOCATION
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                androidx.core.content.ContextCompat.checkSelfPermission(
                    context, android.Manifest.permission.ACCESS_COARSE_LOCATION
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } catch (e: Exception) {
                false
            }
            
            if (!hasLocationPermission) {
                Log.d(TAG, "⚠️ No location permissions - skipping immediate GPS update")
                return
            }
            
            // Try to get location (GPS first, then network)
            var location: android.location.Location? = null
            
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                Log.d(TAG, "📡 GPS provider location: $location")
            }
            
            if (location == null && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                Log.d(TAG, "📶 Network provider location: $location")
            }
            
            // Update Firebase with location data (same structure as AlarmUpdateReceiver)
            if (location != null) {
                val firestore = FirebaseFirestore.getInstance()
                
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
                    "location" to locationData
                )
                
                firestore.collection("families").document(familyId)
                    .update(data)
                    .addOnSuccessListener {
                        Log.d(TAG, "✅✅✅ IMMEDIATE GPS UPDATE SUCCESS - Location updated on screen unlock!")
                        Log.d(TAG, "🎯 GPS coordinates: ${location.latitude}, ${location.longitude}")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ Immediate GPS update failed: ${e.message}")
                    }
            } else {
                Log.d(TAG, "⚠️ No location available for immediate GPS update")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in immediate GPS location update: ${e.message}")
        }
    }
    
    // ORIGINAL COMPLEX VERSION: Enhanced backup mechanism to aggressively initialize GPS alarms if they failed during boot
    private fun checkAndInitializeGpsAlarms(context: Context) {
        try {
            Log.d(TAG, "🌍 ENHANCED: Checking GPS alarm status as backup for boot failures...")
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            if (!locationEnabled) {
                Log.d(TAG, "⚠️ GPS tracking disabled - no backup initialization needed")
                
                // CRITICAL FIX: Clear any pending GPS initialization markers
                prefs.edit()
                    .remove("flutter.gps_needs_screen_init")
                    .remove("flutter.gps_screen_init_marked_time")
                    .remove("flutter.gps_screen_init_reason")
                    .apply()
                    
                return
            }
            
            // CRITICAL FIX: Check if GPS was specifically marked for screen initialization
            val gpsNeedsScreenInit = prefs.getBoolean("flutter.gps_needs_screen_init", false)
            val gpsScreenInitMarkedTime = prefs.getLong("flutter.gps_screen_init_marked_time", 0)
            val gpsScreenInitReason = prefs.getString("flutter.gps_screen_init_reason", "unknown")
            
            if (gpsNeedsScreenInit) {
                Log.w(TAG, "🔥 GPS was SPECIFICALLY MARKED for screen initialization!")
                Log.d(TAG, "  - Marked time: $gpsScreenInitMarkedTime")
                Log.d(TAG, "  - Reason: $gpsScreenInitReason")
                Log.d(TAG, "  - This indicates GPS boot initialization failed")
                
                // Clear the marker and force GPS initialization
                prefs.edit()
                    .remove("flutter.gps_needs_screen_init")
                    .remove("flutter.gps_screen_init_marked_time")
                    .remove("flutter.gps_screen_init_reason")
                    .putBoolean("flutter.gps_force_screen_init_performed", true)
                    .putLong("flutter.gps_force_screen_init_time", System.currentTimeMillis())
                    .apply()
                
                Log.d(TAG, "🚀 FORCING GPS initialization due to screen init marker...")
                
                // Cancel any existing GPS alarms
                try {
                    AlarmUpdateReceiver.cancelGpsAlarm(context)
                    Log.d(TAG, "❌ Cancelled any existing GPS alarms (force init)")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not cancel existing GPS alarms (force init): ${e.message}")
                }
                
                // Start fresh GPS alarm
                try {
                    AlarmUpdateReceiver.scheduleGpsAlarm(context)
                    Log.d(TAG, "✅ GPS FORCE initialization completed successfully")
                    
                    // Record in MIUI alarm prefs for tracking
                    val currentTime = System.currentTimeMillis()
                    val miuiAlarmPrefs = context.getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
                    miuiAlarmPrefs.edit()
                        .putLong("gps_force_init_time", currentTime)
                        .putLong("last_gps_alarm_scheduled", currentTime)
                        .putString("gps_force_init_trigger", "screen_unlock_marker")
                        .apply()
                        
                    return // Don't do regular stale check after force init
                        
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Failed to FORCE schedule GPS alarm: ${e.message}")
                    // Continue with regular stale check as fallback
                }
            }
            
            Log.d(TAG, "✅ GPS tracking is enabled - checking alarm status...")
            
            // Check if GPS alarms might have failed during boot
            val miuiAlarmPrefs = context.getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
            val lastGpsExecution = miuiAlarmPrefs.getLong("last_gps_execution", 0)
            val lastGpsScheduled = miuiAlarmPrefs.getLong("last_gps_alarm_scheduled", 0)
            val currentTime = System.currentTimeMillis()
            val timeSinceLastExecution = currentTime - lastGpsExecution
            val timeSinceLastScheduled = currentTime - lastGpsScheduled
            
            // CRITICAL FIX: More aggressive stale detection for MIUI devices
            val isMiuiDevice = try {
                MiuiPermissionHelper.isMiuiDevice()
            } catch (e: Exception) {
                false
            }
            
            // Reduced threshold for more aggressive recovery, especially on MIUI
            val gpsStaleThreshold = if (isMiuiDevice) {
                5 * 60 * 1000L // 5 minutes for MIUI devices
            } else {
                10 * 60 * 1000L // 10 minutes for other devices
            }
            
            val shouldReinitialize = when {
                lastGpsExecution == 0L -> {
                    Log.w(TAG, "⚠️ GPS has NEVER executed - definitely needs initialization")
                    true
                }
                timeSinceLastExecution > gpsStaleThreshold -> {
                    Log.w(TAG, "⚠️ GPS execution is stale (${timeSinceLastExecution / 1000 / 60} min > ${gpsStaleThreshold / 1000 / 60} min)")
                    true
                }
                lastGpsScheduled == 0L -> {
                    Log.w(TAG, "⚠️ GPS was never scheduled - needs initialization")
                    true
                }
                timeSinceLastScheduled > (2 * gpsStaleThreshold) -> {
                    Log.w(TAG, "⚠️ GPS hasn't been scheduled recently (${timeSinceLastScheduled / 1000 / 60} min)")
                    true
                }
                else -> false
            }
            
            if (shouldReinitialize) {
                Log.w(TAG, "🔄 GPS alarms need reinitialization:")
                Log.d(TAG, "  - Last GPS execution: $lastGpsExecution (${if (lastGpsExecution == 0L) "NEVER" else "${timeSinceLastExecution / 1000 / 60} min ago"})")
                Log.d(TAG, "  - Last GPS scheduled: $lastGpsScheduled (${if (lastGpsScheduled == 0L) "NEVER" else "${timeSinceLastScheduled / 1000 / 60} min ago"})")
                Log.d(TAG, "  - Threshold: ${gpsStaleThreshold / 1000 / 60} minutes")
                Log.d(TAG, "  - Is MIUI device: $isMiuiDevice")
                
                // CRITICAL FIX: Always validate permissions before attempting GPS restart
                val hasLocationPermissions = try {
                    val fineLocation = androidx.core.content.ContextCompat.checkSelfPermission(
                        context, android.Manifest.permission.ACCESS_FINE_LOCATION
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    
                    val coarseLocation = androidx.core.content.ContextCompat.checkSelfPermission(
                        context, android.Manifest.permission.ACCESS_COARSE_LOCATION
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    
                    fineLocation || coarseLocation
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not check location permissions: ${e.message}")
                    false
                }
                
                if (!hasLocationPermissions) {
                    Log.e(TAG, "❌ Cannot reinitialize GPS - location permissions not granted")
                    Log.e(TAG, "💡 User needs to grant location permissions for GPS tracking to work")
                    return
                }
                
                Log.d(TAG, "✅ Location permissions confirmed - proceeding with GPS reinitialization")
                
                // Cancel any existing GPS alarms first
                try {
                    AlarmUpdateReceiver.cancelGpsAlarm(context)
                    Log.d(TAG, "❌ Cancelled any existing GPS alarms")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not cancel existing GPS alarms: ${e.message}")
                }
                
                // Start fresh GPS alarm
                try {
                    AlarmUpdateReceiver.scheduleGpsAlarm(context)
                    Log.d(TAG, "✅ GPS alarm backup initialization completed successfully")
                    
                    // Store that we performed backup initialization
                    prefs.edit()
                        .putLong("flutter.last_gps_backup_init", currentTime)
                        .putBoolean("flutter.gps_backup_init_performed", true)
                        .putString("flutter.gps_backup_trigger", "screen_unlock")
                        .apply()
                        
                    // Also record in MIUI alarm prefs for tracking
                    miuiAlarmPrefs.edit()
                        .putLong("gps_backup_init_time", currentTime)
                        .putLong("last_gps_alarm_scheduled", currentTime)
                        .apply()
                        
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Failed to schedule GPS alarm during backup initialization: ${e.message}")
                }
                    
            } else {
                Log.d(TAG, "✅ GPS alarms appear to be working normally")
                Log.d(TAG, "  - Last execution: ${timeSinceLastExecution / 1000 / 60} minutes ago")
                Log.d(TAG, "  - Last scheduled: ${timeSinceLastScheduled / 1000 / 60} minutes ago")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in enhanced GPS alarm backup check: ${e.message}")
        }
    }
}