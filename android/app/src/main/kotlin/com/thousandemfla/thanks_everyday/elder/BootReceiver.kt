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
            // 기본값 true로 설정 - Flutter 초기화 전에도 작동하도록
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", true)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", true)
            
            Log.i(TAG, "Settings: Survival=$survivalEnabled, GPS=$locationEnabled")
            
            // CRITICAL: Start foreground service first (for notification)
            if (survivalEnabled) {
                Log.i(TAG, "Starting ScreenMonitorService (notification)...")
                startScreenMonitoringService(context)
            }
            
            if (survivalEnabled) {
                Log.i(TAG, "Starting survival monitoring...")
                AlarmUpdateReceiver.enableSurvivalMonitoring(context)
                Log.i(TAG, "✅ Survival started")
            }
            
            if (locationEnabled) {
                Log.i(TAG, "🌍 Starting GPS tracking (service + alarm)...")
                try {
                    // ★ 핵심 수정: 포그라운드 서비스 먼저 시작
                    try {
                        GpsTrackingService.startService(context)
                        Log.i(TAG, "✅ GpsTrackingService started successfully")
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ Could not start GpsTrackingService: ${e.message}")
                    }
                    
                    // 백업용 알람도 스케줄
                    AlarmUpdateReceiver.enableLocationTracking(context)
                    Log.i(TAG, "✅ GPS alarm scheduled as backup")
                    
                    // Verify it was actually scheduled
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        val debugPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
                        val lastScheduled = debugPrefs.getLong("last_gps_alarm_scheduled", 0)
                        if (lastScheduled > 0) {
                            Log.i(TAG, "✅ GPS service + alarm successfully started at boot")
                        } else {
                            Log.e(TAG, "❌ GPS alarm NOT scheduled at boot - FAILED")
                        }
                    }, 3000)
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ FAILED to start GPS tracking: ${e.message}", e)
                }
            } else {
                Log.w(TAG, "⚠️ GPS tracking is DISABLED in settings - not starting")
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