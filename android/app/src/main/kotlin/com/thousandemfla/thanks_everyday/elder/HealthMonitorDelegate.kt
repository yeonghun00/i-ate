package com.thousandemfla.thanks_everyday.elder

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import kotlinx.coroutines.*

class HealthMonitorDelegate private constructor(private val context: Context) {
    
    companion object {
        private const val TAG = "HealthMonitorDelegate"
        private const val HEALTH_CHECK_INTERVAL = 30000L // 30 seconds
        private const val CRITICAL_FAILURE_THRESHOLD = 3
        private const val GPS_UPDATE_TIMEOUT = 150000L // 2.5 minutes
        private const val SCREEN_CHECK_TIMEOUT = 150000L // 2.5 minutes
        private const val EMERGENCY_MODE_DURATION = 300000L // 5 minutes
        
        @Volatile
        private var INSTANCE: HealthMonitorDelegate? = null
        
        fun getInstance(context: Context): HealthMonitorDelegate {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: HealthMonitorDelegate(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
    
    private val safetyNet: SafetyNetManager = SafetyNetManager.getInstance(context)
    private val healthPrefs: SharedPreferences = context.getSharedPreferences("HealthStatus", Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private val monitoringScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    private var isMonitoring = false
    private var emergencyModeActive = false
    private var failureCount = 0
    private var lastHealthCheckTime = 0L
    
    data class HealthStatus(
        val isHealthy: Boolean,
        val gpsWorking: Boolean,
        val screenMonitorWorking: Boolean,
        val alarmsWorking: Boolean,
        val firebaseWorking: Boolean,
        val emergencyMode: Boolean,
        val lastIssues: List<String>,
        val timestamp: Long = System.currentTimeMillis()
    )
    
    fun startHealthMonitoring(): Boolean {
        return try {
            if (isMonitoring) {
                Log.i(TAG, "Health monitoring already running")
                return true
            }
            
            // Create initial backup before starting monitoring
            val initialSnapshot = safetyNet.createSystemSnapshot()
            safetyNet.saveSystemSnapshot(initialSnapshot, "INITIAL_HEALTH_MONITOR")
            
            isMonitoring = true
            lastHealthCheckTime = System.currentTimeMillis()
            
            // Start periodic health checks
            startPeriodicHealthCheck()
            
            // Record monitoring start
            healthPrefs.edit()
                .putBoolean("monitoring_active", true)
                .putLong("monitoring_started", System.currentTimeMillis())
                .putInt("failure_count", 0)
                .apply()
            
            Log.i(TAG, "Health monitoring started successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start health monitoring", e)
            false
        }
    }
    
    fun stopHealthMonitoring(): Boolean {
        return try {
            isMonitoring = false
            emergencyModeActive = false
            
            // Cancel all pending health checks
            handler.removeCallbacksAndMessages(null)
            
            healthPrefs.edit()
                .putBoolean("monitoring_active", false)
                .putLong("monitoring_stopped", System.currentTimeMillis())
                .apply()
            
            Log.i(TAG, "Health monitoring stopped")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping health monitoring", e)
            false
        }
    }
    
    fun performHealthCheck(): HealthStatus {
        return try {
            val currentTime = System.currentTimeMillis()
            val issues = mutableListOf<String>()
            
            // Check GPS functionality
            val gpsWorking = checkGpsHealth(currentTime, issues)
            
            // Check screen monitoring
            val screenWorking = checkScreenMonitorHealth(currentTime, issues)
            
            // Check alarms
            val alarmsWorking = checkAlarmsHealth(issues)
            
            // Check Firebase connectivity
            val firebaseWorking = checkFirebaseHealth(issues)
            
            val isHealthy = gpsWorking && screenWorking && alarmsWorking && firebaseWorking
            
            val healthStatus = HealthStatus(
                isHealthy = isHealthy,
                gpsWorking = gpsWorking,
                screenMonitorWorking = screenWorking,
                alarmsWorking = alarmsWorking,
                firebaseWorking = firebaseWorking,
                emergencyMode = emergencyModeActive,
                lastIssues = issues.toList(),
                timestamp = currentTime
            )
            
            // Handle health check results
            handleHealthCheckResult(healthStatus)
            
            // Update last check time
            lastHealthCheckTime = currentTime
            
            healthStatus
        } catch (e: Exception) {
            Log.e(TAG, "Error performing health check", e)
            HealthStatus(
                isHealthy = false,
                gpsWorking = false,
                screenMonitorWorking = false,
                alarmsWorking = false,
                firebaseWorking = false,
                emergencyMode = true,
                lastIssues = listOf("Health check exception: ${e.message}"),
                timestamp = System.currentTimeMillis()
            )
        }
    }
    
    fun activateEmergencyMode(reason: String): Boolean {
        return try {
            Log.w(TAG, "Activating emergency mode: $reason")
            
            emergencyModeActive = true
            
            // Create emergency backup
            safetyNet.createEmergencyBackup()
            
            // Record emergency activation
            healthPrefs.edit()
                .putBoolean("emergency_mode_active", true)
                .putLong("emergency_activated", System.currentTimeMillis())
                .putString("emergency_reason", reason)
                .apply()
            
            // Try to restart critical services
            attemptServiceRecovery()
            
            // Schedule emergency mode deactivation
            handler.postDelayed({
                deactivateEmergencyMode()
            }, EMERGENCY_MODE_DURATION)
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to activate emergency mode", e)
            false
        }
    }
    
    private fun deactivateEmergencyMode() {
        try {
            emergencyModeActive = false
            failureCount = 0
            
            healthPrefs.edit()
                .putBoolean("emergency_mode_active", false)
                .putLong("emergency_deactivated", System.currentTimeMillis())
                .apply()
            
            Log.i(TAG, "Emergency mode deactivated")
        } catch (e: Exception) {
            Log.e(TAG, "Error deactivating emergency mode", e)
        }
    }
    
    private fun startPeriodicHealthCheck() {
        val healthCheckRunnable = object : Runnable {
            override fun run() {
                if (isMonitoring) {
                    monitoringScope.launch {
                        try {
                            performHealthCheck()
                        } catch (e: Exception) {
                            Log.e(TAG, "Error in periodic health check", e)
                        }
                    }
                    
                    // Schedule next check
                    handler.postDelayed(this, HEALTH_CHECK_INTERVAL)
                }
            }
        }
        
        // Start first check
        handler.postDelayed(healthCheckRunnable, HEALTH_CHECK_INTERVAL)
    }
    
    private fun checkGpsHealth(currentTime: Long, issues: MutableList<String>): Boolean {
        return try {
            val alarmPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            val lastGpsUpdate = alarmPrefs.getLong("last_gps_update", 0L)
            
            if (lastGpsUpdate == 0L) {
                issues.add("GPS: No updates recorded")
                return false
            }
            
            val timeSinceLastUpdate = currentTime - lastGpsUpdate
            if (timeSinceLastUpdate > GPS_UPDATE_TIMEOUT) {
                issues.add("GPS: Last update ${timeSinceLastUpdate / 1000}s ago (timeout: ${GPS_UPDATE_TIMEOUT / 1000}s)")
                return false
            }
            
            // Check if GPS service is running
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val gpsServiceRunning = manager.getRunningServices(Integer.MAX_VALUE).any { 
                it.service.className.contains("GpsTracking") || it.service.className.contains("LocationService")
            }
            
            if (!gpsServiceRunning) {
                issues.add("GPS: Service not running")
                return false
            }
            
            true
        } catch (e: Exception) {
            issues.add("GPS: Health check failed - ${e.message}")
            false
        }
    }
    
    private fun checkScreenMonitorHealth(currentTime: Long, issues: MutableList<String>): Boolean {
        return try {
            val alarmPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            val lastScreenCheck = alarmPrefs.getLong("last_screen_check", 0L)
            
            if (lastScreenCheck == 0L) {
                issues.add("Screen Monitor: No checks recorded")
                return false
            }
            
            val timeSinceLastCheck = currentTime - lastScreenCheck
            if (timeSinceLastCheck > SCREEN_CHECK_TIMEOUT) {
                issues.add("Screen Monitor: Last check ${timeSinceLastCheck / 1000}s ago (timeout: ${SCREEN_CHECK_TIMEOUT / 1000}s)")
                return false
            }
            
            // Check if screen monitoring service is running
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val screenServiceRunning = manager.getRunningServices(Integer.MAX_VALUE).any { 
                it.service.className.contains("ScreenMonitor")
            }
            
            if (!screenServiceRunning) {
                issues.add("Screen Monitor: Service not running")
                return false
            }
            
            true
        } catch (e: Exception) {
            issues.add("Screen Monitor: Health check failed - ${e.message}")
            false
        }
    }
    
    private fun checkAlarmsHealth(issues: MutableList<String>): Boolean {
        return try {
            val alarmPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            val gpsAlarmActive = alarmPrefs.getBoolean("gps_alarm_active", false)
            val survivalAlarmActive = alarmPrefs.getBoolean("survival_alarm_active", false)
            
            if (!gpsAlarmActive) {
                issues.add("Alarms: GPS alarm not active")
            }
            
            if (!survivalAlarmActive) {
                issues.add("Alarms: Survival alarm not active")
            }
            
            gpsAlarmActive && survivalAlarmActive
        } catch (e: Exception) {
            issues.add("Alarms: Health check failed - ${e.message}")
            false
        }
    }
    
    private fun checkFirebaseHealth(issues: MutableList<String>): Boolean {
        return try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val firebaseConnected = flutterPrefs.getBoolean("firebase_connected", false)
            
            if (!firebaseConnected) {
                issues.add("Firebase: Not connected")
                return false
            }
            
            true
        } catch (e: Exception) {
            issues.add("Firebase: Health check failed - ${e.message}")
            false
        }
    }
    
    private fun handleHealthCheckResult(healthStatus: HealthStatus) {
        try {
            // Save health status
            healthPrefs.edit()
                .putBoolean("last_health_status", healthStatus.isHealthy)
                .putLong("last_health_check", healthStatus.timestamp)
                .putString("last_health_issues", healthStatus.lastIssues.joinToString(";"))
                .apply()
            
            if (!healthStatus.isHealthy) {
                failureCount++
                Log.w(TAG, "Health check failed (${failureCount}/${CRITICAL_FAILURE_THRESHOLD}): ${healthStatus.lastIssues}")
                
                if (failureCount >= CRITICAL_FAILURE_THRESHOLD && !emergencyModeActive) {
                    activateEmergencyMode("Critical health check failures: ${healthStatus.lastIssues.joinToString(", ")}")
                }
            } else {
                // Reset failure count on successful health check
                if (failureCount > 0) {
                    failureCount = 0
                    healthPrefs.edit().putInt("failure_count", 0).apply()
                    Log.i(TAG, "Health restored - failure count reset")
                }
            }
            
            healthPrefs.edit().putInt("failure_count", failureCount).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error handling health check result", e)
        }
    }
    
    private fun attemptServiceRecovery() {
        try {
            Log.i(TAG, "Attempting service recovery")
            
            // Try to restart GPS tracking
            val gpsIntent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = "com.thousandemfla.thanks_everyday.GPS_TRACKING_START"
            }
            val gpsPendingIntent = PendingIntent.getBroadcast(
                context, 1001, gpsIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.setRepeating(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 5000, // Start in 5 seconds
                900000, // 15 minutes (matches Firebase Function schedule)
                gpsPendingIntent
            )
            
            // Try to restart screen monitoring
            val screenIntent = Intent(context, AlarmUpdateReceiver::class.java).apply {
                action = "com.thousandemfla.thanks_everyday.SCREEN_MONITOR_START"
            }
            val screenPendingIntent = PendingIntent.getBroadcast(
                context, 1002, screenIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.setRepeating(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 10000, // Start in 10 seconds
                900000, // 15 minutes (matches Firebase Function schedule)
                screenPendingIntent
            )
            
            Log.i(TAG, "Service recovery attempted")
        } catch (e: Exception) {
            Log.e(TAG, "Service recovery failed", e)
        }
    }
    
    fun getHealthReport(): String {
        return try {
            val healthStatus = performHealthCheck()
            buildString {
                appendLine("=== HEALTH MONITOR REPORT ===")
                appendLine("Timestamp: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(healthStatus.timestamp))}")
                appendLine("Overall Health: ${if (healthStatus.isHealthy) "✓ HEALTHY" else "✗ UNHEALTHY"}")
                appendLine("Emergency Mode: ${if (healthStatus.emergencyMode) "✗ ACTIVE" else "✓ INACTIVE"}")
                appendLine()
                appendLine("Component Status:")
                appendLine("  GPS Tracking: ${if (healthStatus.gpsWorking) "✓" else "✗"}")
                appendLine("  Screen Monitor: ${if (healthStatus.screenMonitorWorking) "✓" else "✗"}")
                appendLine("  Alarms: ${if (healthStatus.alarmsWorking) "✓" else "✗"}")
                appendLine("  Firebase: ${if (healthStatus.firebaseWorking) "✓" else "✗"}")
                
                if (healthStatus.lastIssues.isNotEmpty()) {
                    appendLine()
                    appendLine("Issues Detected:")
                    healthStatus.lastIssues.forEach { issue ->
                        appendLine("  • $issue")
                    }
                }
                
                appendLine()
                appendLine("Monitoring Stats:")
                appendLine("  Failure Count: $failureCount/$CRITICAL_FAILURE_THRESHOLD")
                appendLine("  Last Check: ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(lastHealthCheckTime))}")
                appendLine("  Monitoring Active: ${if (isMonitoring) "Yes" else "No"}")
            }
        } catch (e: Exception) {
            "Health report generation failed: ${e.message}"
        }
    }
}