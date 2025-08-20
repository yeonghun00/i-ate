package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.os.Handler
import android.os.Looper

class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
            return
        }
        
        Log.i(TAG, "🚀 BOOT COMPLETED - Starting services in 10 seconds")
        
        // Simple approach: Wait 10 seconds, then start both services
        Handler(Looper.getMainLooper()).postDelayed({
            startServices(context)
        }, 10000L)
    }
    
    private fun startServices(context: Context) {
        try {
            Log.i(TAG, "⚡ STARTING SERVICES NOW")
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            // CRITICAL DEBUG: Check all preference keys to understand what's stored
            val allPrefs = prefs.all
            Log.i(TAG, "🔍 ALL STORED PREFERENCES:")
            for ((key, value) in allPrefs) {
                Log.i(TAG, "  $key = $value")
            }
            
            // CRITICAL FIX: Use correct default values matching Flutter app behavior  
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false) 
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            Log.i(TAG, "🎯 FINAL Settings: Survival=$survivalEnabled, GPS=$locationEnabled")
            
            // CRITICAL: Start foreground service for survival monitoring only (notification)
            if (survivalEnabled) {
                Log.i(TAG, "Starting ScreenMonitorService (survival monitoring notification)...")
                startScreenMonitoringService(context)
            }
            
            if (survivalEnabled) {
                Log.i(TAG, "Starting survival monitoring...")
                AlarmUpdateReceiver.enableSurvivalMonitoring(context)
                Log.i(TAG, "✅ Survival started")
            }
            
            if (locationEnabled) {
                Log.i(TAG, "🌍 Starting GPS tracking (pure alarm approach)...")
                try {
                    // CRITICAL FIX: Use only alarm-based GPS tracking (no service dependency)
                    AlarmUpdateReceiver.enableLocationTracking(context)
                    Log.i(TAG, "✅ GPS alarm scheduled (service-free)")
                    
                    // Verify it was actually scheduled
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        val debugPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
                        val lastScheduled = debugPrefs.getLong("last_gps_alarm_scheduled", 0)
                        val currentTime = System.currentTimeMillis()
                        
                        if (lastScheduled > 0 && (currentTime - lastScheduled) < 30000) {
                            Log.i(TAG, "✅ GPS alarm successfully started at boot (${currentTime - lastScheduled}ms ago)")
                        } else {
                            Log.e(TAG, "❌ GPS alarm NOT scheduled at boot - FAILED (last: $lastScheduled, now: $currentTime)")
                            
                            // Try to reschedule immediately as backup
                            try {
                                Log.w(TAG, "🔄 Attempting GPS alarm rescue...")
                                AlarmUpdateReceiver.enableLocationTracking(context)
                            } catch (rescueError: Exception) {
                                Log.e(TAG, "❌ GPS rescue failed: ${rescueError.message}")
                            }
                        }
                    }, 5000) // Give more time for scheduling
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ FAILED to start GPS tracking: ${e.message}", e)
                }
            } else {
                // CRITICAL DEBUG: Check if GPS was previously working
                val debugPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
                val lastGpsExecution = debugPrefs.getLong("last_gps_execution", 0)
                val lastGpsScheduled = debugPrefs.getLong("last_gps_alarm_scheduled", 0)
                
                if (lastGpsExecution > 0 || lastGpsScheduled > 0) {
                    Log.w(TAG, "⚠️ GPS tracking DISABLED but previously worked - FORCING START as rescue")
                    Log.w(TAG, "   Last GPS execution: $lastGpsExecution, Last scheduled: $lastGpsScheduled")
                    
                    try {
                        // Force enable GPS tracking and save preference
                        prefs.edit().putBoolean("flutter.location_tracking_enabled", true).apply()
                        AlarmUpdateReceiver.enableLocationTracking(context)
                        Log.i(TAG, "✅ GPS rescue mode activated successfully")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ GPS rescue mode failed: ${e.message}")
                    }
                } else {
                    Log.w(TAG, "⚠️ GPS tracking is DISABLED in settings - not starting (never worked before)")
                }
            }
            
            Log.i(TAG, "🎉 BOOT SERVICES COMPLETED")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Boot service error: ${e.message}", e)
        }
    }
    
    private fun startScreenMonitoringService(context: Context) {
        try {
            Log.i(TAG, "🔧 Starting ScreenMonitorService...")
            
            val serviceIntent = Intent(context, ScreenMonitorService::class.java)
            serviceIntent.putExtra("start_source", "boot_receiver")
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                try {
                    context.startForegroundService(serviceIntent)
                    Log.i(TAG, "✅ ScreenMonitorService started")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not start foreground service: ${e.message}")
                }
            } else {
                context.startService(serviceIntent)
                Log.i(TAG, "✅ ScreenMonitorService started (legacy)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting ScreenMonitorService: ${e.message}")
        }
    }
}