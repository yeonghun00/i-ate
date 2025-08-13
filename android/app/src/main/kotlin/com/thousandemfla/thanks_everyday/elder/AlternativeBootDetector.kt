package com.thousandemfla.thanks_everyday.elder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.SystemClock
import android.util.Log
import java.io.File

object AlternativeBootDetector {
    private const val TAG = "AlternativeBootDetector"
    private const val PREFS_NAME = "AlternativeBootPrefs"
    private const val KEY_LAST_BOOT_TIME = "last_boot_time"
    private const val KEY_LAST_UPTIME = "last_uptime"
    private const val KEY_LAST_CHECK_TIME = "last_check_time"
    private const val KEY_DETECTOR_ACTIVE = "detector_active"
    
    private const val BOOT_CHECK_INTERVAL = 30 * 60 * 1000L // 30 minutes
    
    fun startAlternativeDetection(context: Context) {
        try {
            Log.d(TAG, "🔄 Starting alternative boot detection system...")
            
            val prefs = getPrefs(context)
            prefs.edit()
                .putBoolean(KEY_DETECTOR_ACTIVE, true)
                .putLong(KEY_LAST_CHECK_TIME, System.currentTimeMillis())
                .apply()
            
            // Store current boot time and uptime as baseline
            storeCurrentBootInfo(context)
            
            // Schedule periodic boot checks
            schedulePeriodicBootCheck(context)
            
            // Enable network boot detection
            enableNetworkBootDetection(context)
            
            logToFile(context, "Alternative boot detection started")
            Log.d(TAG, "✅ Alternative boot detection system active")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start alternative boot detection: ${e.message}")
            logToFile(context, "Alternative boot detection start failed: ${e.message}")
        }
    }
    
    fun stopAlternativeDetection(context: Context) {
        try {
            Log.d(TAG, "🛑 Stopping ALL boot detection systems...")
            
            val prefs = getPrefs(context)
            prefs.edit().putBoolean(KEY_DETECTOR_ACTIVE, false).apply()
            
            // Cancel periodic boot checks
            cancelPeriodicBootCheck(context)
            
            // CRITICAL MIUI ENHANCEMENT: Stop all additional detection mechanisms
            try {
                // Stop JobScheduler-based detection
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                    // PersistentBootJobService.cancelBootDetectionJobs(context)
                    Log.d(TAG, "✅ JobScheduler boot detection stopped")
                }
                
                // Stop WorkManager-based detection
                // BootDetectionWorker.cancelBootDetectionWork(context)
                Log.d(TAG, "✅ WorkManager boot detection stopped")
                
                // Stop notification-based detection
                // BootNotificationService.stopBootNotificationService(context)
                Log.d(TAG, "✅ Notification boot detection stopped")
                
                Log.d(TAG, "🎉 ALL MIUI BYPASS MECHANISMS STOPPED!")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to stop some enhanced detection mechanisms: ${e.message}")
            }
            
            logToFile(context, "All boot detection systems stopped")
            Log.d(TAG, "✅ All boot detection systems stopped")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to stop boot detection: ${e.message}")
        }
    }
    
    fun checkForMissedBoot(context: Context): Boolean {
        return try {
            Log.d(TAG, "🔍 Checking for missed boot events...")
            
            val currentBootTime = SystemClock.elapsedRealtime()
            val currentUptime = SystemClock.uptimeMillis()
            val currentSystemTime = System.currentTimeMillis()
            
            val prefs = getPrefs(context)
            val lastBootTime = prefs.getLong(KEY_LAST_BOOT_TIME, 0L)
            val lastUptime = prefs.getLong(KEY_LAST_UPTIME, 0L)
            val lastCheckTime = prefs.getLong(KEY_LAST_CHECK_TIME, 0L)
            
            Log.d(TAG, "Boot time comparison:")
            Log.d(TAG, "  Current boot time: $currentBootTime")
            Log.d(TAG, "  Last recorded boot time: $lastBootTime")
            Log.d(TAG, "  Current uptime: $currentUptime")
            Log.d(TAG, "  Last recorded uptime: $lastUptime")
            Log.d(TAG, "  Time since last check: ${currentSystemTime - lastCheckTime}ms")
            
            var bootDetected = false
            var detectionMethod = ""
            
            // Method 1: Boot time changed significantly
            if (lastBootTime > 0) {
                val bootTimeDiff = Math.abs(currentBootTime - lastBootTime)
                if (bootTimeDiff > 60000) { // More than 1 minute difference
                    bootDetected = true
                    detectionMethod = "boot_time_change"
                    Log.d(TAG, "🔥 Boot detected via boot time change: ${bootTimeDiff}ms difference")
                }
            }
            
            // Method 2: Uptime reset (much smaller than expected)
            if (!bootDetected && lastUptime > 0 && lastCheckTime > 0) {
                val expectedUptime = lastUptime + (currentSystemTime - lastCheckTime)
                val uptimeDiff = expectedUptime - currentUptime
                if (uptimeDiff > 60000) { // Expected uptime is more than 1 minute higher
                    bootDetected = true
                    detectionMethod = "uptime_reset"
                    Log.d(TAG, "🔥 Boot detected via uptime reset: expected ${expectedUptime}, got ${currentUptime}")
                }
            }
            
            // Method 3: Very low uptime with significant time gap
            if (!bootDetected && currentUptime < 10 * 60 * 1000) { // Less than 10 minutes uptime
                val timeSinceLastCheck = currentSystemTime - lastCheckTime
                if (timeSinceLastCheck > 2 * 60 * 60 * 1000) { // More than 2 hours since last check
                    bootDetected = true
                    detectionMethod = "low_uptime_time_gap"
                    Log.d(TAG, "🔥 Boot detected via low uptime with time gap: uptime=${currentUptime}ms, gap=${timeSinceLastCheck}ms")
                }
            }
            
            if (bootDetected) {
                Log.e(TAG, "🚨🚨🚨 MISSED BOOT DETECTED via $detectionMethod")
                logToFile(context, "MISSED BOOT DETECTED via $detectionMethod")
                
                // Trigger boot restoration
                handleMissedBoot(context, detectionMethod)
                
                // Update stored boot info
                storeCurrentBootInfo(context)
                
                return true
            } else {
                Log.d(TAG, "✅ No missed boot detected")
                // Update last check time
                prefs.edit().putLong(KEY_LAST_CHECK_TIME, currentSystemTime).apply()
                return false
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking for missed boot: ${e.message}")
            false
        }
    }
    
    fun handleNetworkBootDetection(context: Context) {
        try {
            Log.e(TAG, "🌐 Network connectivity boot detection triggered")
            logToFile(context, "Network connectivity boot detection triggered")
            
            // Network comes up early in boot process, so this is a good indicator
            val currentUptime = SystemClock.uptimeMillis()
            val currentBootTime = SystemClock.elapsedRealtime()
            
            Log.e(TAG, "🌐 Network boot check - Uptime: ${currentUptime}ms, BootTime: ${currentBootTime}ms")
            logToFile(context, "Network boot check - Uptime: ${currentUptime}ms, BootTime: ${currentBootTime}ms")
            
            // If uptime is less than 10 minutes, this might be a fresh boot
            if (currentUptime < 10 * 60 * 1000) {
                Log.e(TAG, "🔥 Potential boot detected via network (uptime: ${currentUptime}ms)")
                logToFile(context, "Potential boot detected via network (uptime: ${currentUptime}ms)")
                
                // Wait a bit for system to stabilize, then check for missed boot
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    Log.e(TAG, "🔍 Network boot detection: Checking for missed boot after stabilization")
                    val bootDetected = checkForMissedBoot(context)
                    if (!bootDetected) {
                        // Even if boot time didn't change much, network trigger + low uptime suggests boot
                        Log.e(TAG, "🔥 Network trigger + low uptime = FORCED BOOT DETECTION")
                        logToFile(context, "Network trigger + low uptime = FORCED BOOT DETECTION")
                        handleMissedBoot(context, "network_low_uptime")
                        storeCurrentBootInfo(context)
                    } else {
                        Log.e(TAG, "✅ Boot already detected by missed boot check")
                    }
                }, 30000) // 30 second delay
            } else {
                Log.d(TAG, "✅ Network trigger with high uptime (${currentUptime}ms) - not a boot")
                logToFile(context, "Network trigger with high uptime - not a boot")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in network boot detection: ${e.message}")
            logToFile(context, "Error in network boot detection: ${e.message}")
            e.printStackTrace()
        }
    }
    
    private fun handleMissedBoot(context: Context, detectionMethod: String) {
        try {
            Log.e(TAG, "🚨 HANDLING MISSED BOOT - Method: $detectionMethod")
            logToFile(context, "HANDLING MISSED BOOT - Method: $detectionMethod")
            
            // Same restoration logic as BootReceiver
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val survivalSignalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            val locationTrackingEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            Log.e(TAG, "📱 Alternative boot restoration - Settings check:")
            Log.e(TAG, "  - Survival signal enabled: $survivalSignalEnabled")
            Log.e(TAG, "  - Location tracking enabled: $locationTrackingEnabled")
            logToFile(context, "Boot settings: survival=$survivalSignalEnabled, location=$locationTrackingEnabled")
            
            if (!survivalSignalEnabled && !locationTrackingEnabled) {
                Log.e(TAG, "❌ No monitoring services enabled, skipping boot restoration")
                logToFile(context, "No monitoring services enabled, skipping restoration")
                return
            }
            
            Log.e(TAG, "✅ Monitoring services enabled - proceeding with restoration")
            logToFile(context, "Monitoring services enabled - proceeding with restoration")
            
            // Try immediate restoration first (since we're already in a delayed context from detection)
            try {
                Log.e(TAG, "🚀 IMMEDIATE: Alternative boot restoration starting now")
                logToFile(context, "IMMEDIATE: Alternative boot restoration starting now")
                
                // Use specific enable methods instead of generic scheduleAlarms
                if (survivalSignalEnabled) {
                    Log.e(TAG, "🚀 IMMEDIATE: Starting survival monitoring via AlarmUpdateReceiver")
                    logToFile(context, "IMMEDIATE: Starting survival monitoring via AlarmUpdateReceiver")
                    AlarmUpdateReceiver.enableSurvivalMonitoring(context)
                    Log.e(TAG, "✅ IMMEDIATE: Survival monitoring alarm enabled")
                    logToFile(context, "IMMEDIATE: Survival monitoring alarm enabled")
                }
                
                if (locationTrackingEnabled) {
                    Log.e(TAG, "🌍 IMMEDIATE: Starting location tracking via AlarmUpdateReceiver")
                    logToFile(context, "IMMEDIATE: Starting location tracking via AlarmUpdateReceiver")
                    AlarmUpdateReceiver.enableLocationTracking(context)
                    Log.e(TAG, "✅ IMMEDIATE: Location tracking alarm enabled")
                    logToFile(context, "IMMEDIATE: Location tracking alarm enabled")
                }
                
                Log.e(TAG, "✅ IMMEDIATE: AlarmManager restoration completed")
                logToFile(context, "IMMEDIATE: AlarmManager restoration completed")
                
                // Final verification log
                Log.e(TAG, "🎉 IMMEDIATE: Alternative boot restoration completed!")
                Log.e(TAG, "  - Survival monitoring: ${if (survivalSignalEnabled) "RESTORED" else "DISABLED"}")
                Log.e(TAG, "  - Location tracking: ${if (locationTrackingEnabled) "RESTORED" else "DISABLED"}")
                logToFile(context, "IMMEDIATE: Alternative boot restoration completed - survival=$survivalSignalEnabled, location=$locationTrackingEnabled")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ IMMEDIATE: Alternative boot restoration failed: ${e.message}")
                logToFile(context, "IMMEDIATE: Alternative boot restoration failed: ${e.message}")
                e.printStackTrace()
            }
            
            // Also try delayed ScreenMonitorService if survival signal enabled
            if (survivalSignalEnabled) {
                Log.e(TAG, "🔍 DELAYED: Survival signal enabled - scheduling ScreenMonitorService")
                logToFile(context, "DELAYED: Survival signal enabled - scheduling ScreenMonitorService")
                
                try {
                    // Try immediate service start first
                    Log.e(TAG, "🚀 IMMEDIATE: Attempting ScreenMonitorService start")
                    logToFile(context, "IMMEDIATE: Attempting ScreenMonitorService start")
                    
                    ScreenMonitorService.startService(context)
                    
                    Log.e(TAG, "✅ IMMEDIATE: ScreenMonitorService started successfully")
                    logToFile(context, "IMMEDIATE: ScreenMonitorService started successfully")
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ IMMEDIATE: ScreenMonitorService failed: ${e.message}")
                    logToFile(context, "IMMEDIATE: ScreenMonitorService failed: ${e.message}")
                    
                    // Fallback: Try with Handler on main thread
                    try {
                        Log.e(TAG, "🔄 FALLBACK: Trying Handler-based delayed start")
                        logToFile(context, "FALLBACK: Trying Handler-based delayed start")
                        
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            try {
                                Log.e(TAG, "🚀 DELAYED: Starting ScreenMonitorService (Handler)")
                                logToFile(context, "DELAYED: Starting ScreenMonitorService (Handler)")
                                
                                ScreenMonitorService.startService(context)
                                
                                Log.e(TAG, "✅ DELAYED: ScreenMonitorService started (Handler)")
                                logToFile(context, "DELAYED: ScreenMonitorService started (Handler)")
                                
                            } catch (handlerE: Exception) {
                                Log.e(TAG, "❌ DELAYED: ScreenMonitorService failed (Handler): ${handlerE.message}")
                                logToFile(context, "DELAYED: ScreenMonitorService failed (Handler): ${handlerE.message}")
                            }
                        }, 10000) // 10 second delay
                        
                    } catch (handlerSetupE: Exception) {
                        Log.e(TAG, "❌ Failed to setup Handler for delayed service: ${handlerSetupE.message}")
                        logToFile(context, "Failed to setup Handler for delayed service: ${handlerSetupE.message}")
                    }
                }
            } else {
                Log.e(TAG, "ℹ️ DELAYED: Survival signal disabled - skipping ScreenMonitorService")
                logToFile(context, "DELAYED: Survival signal disabled - skipping ScreenMonitorService")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error handling missed boot: ${e.message}")
            logToFile(context, "Error handling missed boot: ${e.message}")
            e.printStackTrace()
        }
    }
    
    private fun storeCurrentBootInfo(context: Context) {
        try {
            val prefs = getPrefs(context)
            val currentBootTime = SystemClock.elapsedRealtime()
            val currentUptime = SystemClock.uptimeMillis()
            val currentSystemTime = System.currentTimeMillis()
            
            prefs.edit()
                .putLong(KEY_LAST_BOOT_TIME, currentBootTime)
                .putLong(KEY_LAST_UPTIME, currentUptime)
                .putLong(KEY_LAST_CHECK_TIME, currentSystemTime)
                .apply()
            
            Log.d(TAG, "📝 Stored boot info: bootTime=$currentBootTime, uptime=$currentUptime")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error storing boot info: ${e.message}")
        }
    }
    
    private fun schedulePeriodicBootCheck(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, BootCheckReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context, 
                0, 
                intent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val triggerAtMillis = SystemClock.elapsedRealtime() + BOOT_CHECK_INTERVAL
            
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
            
            Log.d(TAG, "✅ Scheduled periodic boot check in ${BOOT_CHECK_INTERVAL / 60000} minutes")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to schedule periodic boot check: ${e.message}")
        }
    }
    
    private fun cancelPeriodicBootCheck(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, BootCheckReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context, 
                0, 
                intent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "✅ Cancelled periodic boot check")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to cancel periodic boot check: ${e.message}")
        }
    }
    
    private fun enableNetworkBootDetection(context: Context) {
        try {
            // Network boot detection is handled by NetworkBootDetectorReceiver
            // registered in AndroidManifest.xml
            Log.d(TAG, "✅ Network boot detection enabled via manifest receiver")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error enabling network boot detection: ${e.message}")
        }
    }
    
    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    
    private fun logToFile(context: Context, message: String) {
        try {
            val bootLogFile = File(context.filesDir, "boot_debug_log.txt")
            val timestamp = System.currentTimeMillis()
            val readableTime = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(timestamp))
            
            bootLogFile.appendText("[$readableTime] ALT: $message\n", Charsets.UTF_8)
        } catch (e: Exception) {
            // Ignore file errors
        }
    }
    
    fun isAlternativeDetectionActive(context: Context): Boolean {
        return try {
            getPrefs(context).getBoolean(KEY_DETECTOR_ACTIVE, false)
        } catch (e: Exception) {
            false
        }
    }
    
    fun getAlternativeDetectionStatus(context: Context): Map<String, Any> {
        return try {
            val prefs = getPrefs(context)
            mapOf(
                "active" to prefs.getBoolean(KEY_DETECTOR_ACTIVE, false),
                "lastBootTime" to prefs.getLong(KEY_LAST_BOOT_TIME, 0L),
                "lastUptime" to prefs.getLong(KEY_LAST_UPTIME, 0L),
                "lastCheckTime" to prefs.getLong(KEY_LAST_CHECK_TIME, 0L),
                "currentBootTime" to SystemClock.elapsedRealtime(),
                "currentUptime" to SystemClock.uptimeMillis()
            )
        } catch (e: Exception) {
            mapOf("error" to e.message.toString())
        }
    }
}