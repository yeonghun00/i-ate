package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Boot receiver triggered: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                
                // Check which services are enabled
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val survivalSignalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
                val locationTrackingEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
                
                Log.d(TAG, "📱 Boot settings: survivalSignal=$survivalSignalEnabled, locationTracking=$locationTrackingEnabled")
                
                // Use new smart scheduling - automatically schedules what's enabled
                AlarmUpdateReceiver.scheduleAlarms(context)
                
                // Log what got started
                if (locationTrackingEnabled && survivalSignalEnabled) {
                    Log.d(TAG, "✅ Independent services started after boot:")
                    Log.d(TAG, "  - GPS location tracking: ENABLED (separate alarm)")
                    Log.d(TAG, "  - Survival signal monitoring: ENABLED (separate alarm)")
                } else if (locationTrackingEnabled) {
                    Log.d(TAG, "✅ GPS location tracking started after boot (independent)")
                    Log.d(TAG, "  - Survival signal: DISABLED")
                } else if (survivalSignalEnabled) {
                    Log.d(TAG, "✅ Survival signal monitoring started after boot (independent)")
                    Log.d(TAG, "  - GPS location: DISABLED")
                } else {
                    Log.d(TAG, "❌ Both services disabled, no alarms scheduled")
                }
                
                // Log family info for debugging
                val familyId = prefs.getString("flutter.family_id", null)
                Log.d(TAG, "Family ID found: $familyId")
            }
        }
    }
}