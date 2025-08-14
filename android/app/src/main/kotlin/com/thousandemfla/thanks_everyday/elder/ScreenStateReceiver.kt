package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

class ScreenStateReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "ScreenStateReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Screen event: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_USER_PRESENT -> {
                Log.d(TAG, "🔓 USER UNLOCKED - Updating Firebase + Restarting services")
                
                // Update Firebase immediately
                updateFirebase(context)
                
                // Restart services (simple approach)
                restartServicesIfNeeded(context)
            }
        }
    }
    
    private fun updateFirebase(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val familyId = prefs.getString("flutter.family_id", null) ?: prefs.getString("family_id", null)
            
            if (familyId.isNullOrEmpty()) {
                Log.w(TAG, "No family ID found")
                return
            }
            
            val firestore = FirebaseFirestore.getInstance()
            
            // Update survival signal
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            if (survivalEnabled) {
                firestore.collection("families").document(familyId)
                    .update("lastPhoneActivity", FieldValue.serverTimestamp())
                    .addOnSuccessListener { Log.d(TAG, "✅ Survival signal updated") }
                    .addOnFailureListener { Log.e(TAG, "Failed to update survival signal") }
            }
            
            // Update GPS location - ALWAYS update even if location is null
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            if (locationEnabled) {
                val location = getCurrentLocation(context)
                if (location != null) {
                    val locationData = mapOf(
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "accuracy" to location.accuracy,
                        "timestamp" to FieldValue.serverTimestamp(),
                        "provider" to (location.provider ?: "unknown")
                    )
                    
                    firestore.collection("families").document(familyId)
                        .update(mapOf("location" to locationData))
                        .addOnSuccessListener { Log.d(TAG, "✅ GPS location updated") }
                        .addOnFailureListener { Log.e(TAG, "Failed to update GPS location") }
                } else {
                    // CRITICAL FIX: Update timestamp even without location (like AlarmUpdateReceiver)
                    Log.w(TAG, "⚠️ No GPS location available on unlock - updating timestamp")
                    firestore.collection("families").document(familyId)
                        .update("lastGpsCheck", FieldValue.serverTimestamp())
                        .addOnSuccessListener { Log.d(TAG, "✅ GPS timestamp updated on unlock") }
                        .addOnFailureListener { Log.e(TAG, "Failed to update GPS timestamp") }
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error updating Firebase: ${e.message}")
        }
    }
    
    private fun restartServicesIfNeeded(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val debugPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            val currentTime = System.currentTimeMillis()
            val threshold = 4 * 60 * 1000L // 4 minutes
            
            // Check survival service
            if (survivalEnabled) {
                val lastExecution = debugPrefs.getLong("last_survival_execution", 0)
                if (lastExecution == 0L || (currentTime - lastExecution) > threshold) {
                    Log.w(TAG, "🔄 Restarting survival service")
                    AlarmUpdateReceiver.enableSurvivalMonitoring(context)
                }
            }
            
            // Check GPS service
            if (locationEnabled) {
                val lastExecution = debugPrefs.getLong("last_gps_execution", 0)
                if (lastExecution == 0L || (currentTime - lastExecution) > threshold) {
                    Log.w(TAG, "🔄 Restarting GPS service")
                    AlarmUpdateReceiver.enableLocationTracking(context)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error restarting services: ${e.message}")
        }
    }
    
    private fun getCurrentLocation(context: Context): android.location.Location? {
        return try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            
            val hasPermission = androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_FINE_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED ||
            androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_COARSE_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            
            if (!hasPermission) return null
            
            var location: android.location.Location? = null
            
            if (locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)) {
                location = locationManager.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
            }
            
            if (location == null && locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)) {
                location = locationManager.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
            }
            
            location
            
        } catch (e: Exception) {
            Log.e(TAG, "Error getting location: ${e.message}")
            null
        }
    }
}