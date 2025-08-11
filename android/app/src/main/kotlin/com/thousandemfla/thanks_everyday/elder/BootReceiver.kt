package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.thousandemfla.thanks_everyday.elder.ScreenMonitorService

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        // CRITICAL: Force immediate log to verify BootReceiver is working
        android.util.Log.e(TAG, "🚀🚀🚀 BOOT RECEIVER TRIGGERED: ${intent.action}")
        println("🚀🚀🚀 BOOT RECEIVER TRIGGERED: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                
                // CRITICAL: Force error logs to ensure visibility
                android.util.Log.e(TAG, "📱📱📱 DEVICE REBOOT DETECTED - STARTING RESTORATION")
                
                // Check which services are enabled
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val survivalSignalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
                val locationTrackingEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
                val familyId = prefs.getString("flutter.family_id", null)
                
                android.util.Log.e(TAG, "📱 Boot settings: survival=$survivalSignalEnabled, location=$locationTrackingEnabled, family=$familyId")
                
                if (!survivalSignalEnabled && !locationTrackingEnabled) {
                    android.util.Log.e(TAG, "❌ No monitoring services enabled, skipping boot restoration")
                    return
                }
                
                // CRITICAL: Check battery optimization status after boot
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                val isBatteryOptimized = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M && powerManager != null) {
                    !powerManager.isIgnoringBatteryOptimizations(context.packageName)
                } else {
                    false
                }
                
                if (isBatteryOptimized) {
                    android.util.Log.e(TAG, "⚠️⚠️⚠️ CRITICAL: App is battery optimized - services may be killed!")
                    android.util.Log.e(TAG, "💡 User needs to whitelist app in battery settings")
                } else {
                    android.util.Log.e(TAG, "✅ Battery optimization disabled - services should work reliably")
                }
                
                // CRITICAL: Check Android 3.1+ app launch state
                checkAppLaunchState(context)
                
                // CRITICAL: Check OEM-specific restrictions
                val manufacturer = android.os.Build.MANUFACTURER.lowercase()
                if (manufacturer.contains("xiaomi")) {
                    android.util.Log.e(TAG, "⚠️⚠️⚠️ MIUI DEVICE DETECTED!")
                    android.util.Log.e(TAG, "💡 Ensure auto-start is enabled AND app is opened after install!")
                } else if (manufacturer.contains("oppo") || manufacturer.contains("vivo") || manufacturer.contains("huawei")) {
                    android.util.Log.e(TAG, "⚠️⚠️⚠️ OEM RESTRICTIONS DETECTED: $manufacturer")
                    android.util.Log.e(TAG, "💡 Check auto-start and battery optimization settings!")
                }
                
                // CRITICAL FIX: Staged initialization with system readiness checks
                Log.d(TAG, "⏳ Starting staged boot restoration with system readiness verification...")
                
                // Phase 1: Immediate alarm scheduling (most reliable)
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    try {
                        android.util.Log.e(TAG, "🚀🚀🚀 PHASE 1: Starting alarms (3 seconds after boot)")
                        AlarmUpdateReceiver.scheduleAlarms(context)
                        android.util.Log.e(TAG, "✅✅✅ PHASE 1 COMPLETE: AlarmManager restored")
                    } catch (e: Exception) {
                        android.util.Log.e(TAG, "❌❌❌ PHASE 1 FAILED: ${e.message}")
                    }
                }, 3000) // Quick start for alarms
                
                // Phase 2: Foreground service with system readiness check
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    try {
                        android.util.Log.e(TAG, "📱📱📱 PHASE 2: Starting ScreenMonitorService (12 seconds after boot)")
                        
                        // Check if system is ready for foreground services
                        if (isSystemReadyForServices(context)) {
                            if (survivalSignalEnabled) {
                                android.util.Log.e(TAG, "✅ System ready - starting ScreenMonitorService")
                                ScreenMonitorService.startService(context)
                                android.util.Log.e(TAG, "✅✅✅ ScreenMonitorService started - NOTIFICATION SHOULD APPEAR!")
                            }
                        } else {
                            android.util.Log.e(TAG, "⚠️⚠️⚠️ System not ready, scheduling retry...")
                            // Phase 3: Final retry if system wasn't ready
                            schedulePhase3Retry(context, survivalSignalEnabled, locationTrackingEnabled)
                        }
                        
                        android.util.Log.e(TAG, "✅✅✅ PHASE 2 COMPLETE")
                        
                    } catch (e: Exception) {
                        android.util.Log.e(TAG, "❌❌❌ PHASE 2 FAILED: ${e.message}")
                        schedulePhase3Retry(context, survivalSignalEnabled, locationTrackingEnabled)
                    }
                }, 12000) // Increased delay for system stability
                
                // Log what got started - RESTORED: Reflects reliable alarm approach
                if (locationTrackingEnabled && survivalSignalEnabled) {
                    Log.d(TAG, "✅ Independent services started after boot:")
                    Log.d(TAG, "  - GPS location tracking: ENABLED (AlarmManager - RELIABLE after reboot!)")
                    Log.d(TAG, "  - Survival signal monitoring: ENABLED (alarm-based backup)")
                    Log.d(TAG, "  - ScreenMonitorService: ENABLED (foreground service for persistence)")
                    Log.d(TAG, "  - ScreenStateReceiver: ENABLED (AndroidManifest registration)")
                } else if (locationTrackingEnabled) {
                    Log.d(TAG, "✅ GPS location tracking started after boot (AlarmManager)")
                    Log.d(TAG, "  - Survival signal: DISABLED")
                } else if (survivalSignalEnabled) {
                    Log.d(TAG, "✅ Survival signal monitoring started after boot (alarm-based)")
                    Log.d(TAG, "  - GPS location: DISABLED")
                    Log.d(TAG, "  - ScreenMonitorService: ENABLED (foreground service for persistence)")
                    Log.d(TAG, "  - ScreenStateReceiver: ENABLED (AndroidManifest registration)")
                } else {
                    Log.d(TAG, "❌ Both services disabled, no GPS alarms or survival alarms scheduled")
                    Log.d(TAG, "  - ScreenStateReceiver: Should still work (AndroidManifest)")
                }
                
                // Test if ScreenStateReceiver is working by logging
                Log.d(TAG, "📱 ScreenStateReceiver should now be listening for unlock events")
                Log.d(TAG, "📱 If you don't see unlock logs, the receiver may be restricted")
                
                // Log family info for debugging
                Log.d(TAG, "Family ID found: $familyId")
            }
        }
    }
    
    private fun isSystemReadyForServices(context: Context): Boolean {
        return try {
            // Check if NotificationManager is available and ready
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            if (notificationManager == null) {
                Log.w(TAG, "⚠️ NotificationManager not available yet")
                return false
            }
            
            // Check if we can access SharedPreferences (indicates system is stable)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val testAccess = prefs.getBoolean("flutter.system_ready_test", false)
            
            // System appears ready for services
            Log.d(TAG, "✅ System readiness check passed")
            true
            
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ System readiness check failed: ${e.message}")
            false
        }
    }
    
    private fun schedulePhase3Retry(context: Context, survivalSignalEnabled: Boolean, locationTrackingEnabled: Boolean) {
        // Phase 3: Final retry after extended delay
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            try {
                Log.d(TAG, "🔄 PHASE 3: Final retry for service startup")
                
                if (survivalSignalEnabled) {
                    Log.d(TAG, "🔄 Final attempt to start ScreenMonitorService")
                    ScreenMonitorService.startService(context)
                    Log.d(TAG, "✅ Phase 3: ScreenMonitorService start attempted")
                }
                
                // Verify alarm scheduling still active
                Log.d(TAG, "🔄 Re-verifying alarm scheduling...")
                AlarmUpdateReceiver.scheduleAlarms(context)
                
                Log.d(TAG, "✅ Phase 3 complete - boot restoration finished")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Phase 3 failed: ${e.message}")
                Log.e(TAG, "💡 Some services may require manual app opening to fully restore")
            }
        }, 20000) // Extended delay for final retry
    }
    
    private fun checkAppLaunchState(context: Context) {
        try {
            // Record that BootReceiver successfully triggered
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val currentTime = System.currentTimeMillis()
            
            prefs.edit()
                .putLong("flutter.last_boot_receiver_trigger", currentTime)
                .putBoolean("flutter.boot_receiver_working", true)
                .apply()
            
            android.util.Log.e(TAG, "✅ App launch state recorded - BootReceiver is working")
            android.util.Log.e(TAG, "📱 This proves app was opened after installation (Android 3.1+ requirement)")
            
            // Check if this is the first successful boot trigger
            val firstBootTrigger = prefs.getLong("flutter.first_boot_receiver_trigger", 0L)
            if (firstBootTrigger == 0L) {
                prefs.edit()
                    .putLong("flutter.first_boot_receiver_trigger", currentTime)
                    .apply()
                android.util.Log.e(TAG, "🎉 First successful boot trigger recorded!")
            }
            
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌ Failed to record app launch state: ${e.message}")
        }
    }
}