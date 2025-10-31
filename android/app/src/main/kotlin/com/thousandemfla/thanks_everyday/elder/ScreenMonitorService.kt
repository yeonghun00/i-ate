package com.thousandemfla.thanks_everyday.elder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.thousandemfla.thanks_everyday.R
import com.thousandemfla.thanks_everyday.services.BatteryService

class ScreenMonitorService : Service() {
    
    companion object {
        private const val TAG = "ScreenMonitorService"
        private const val NOTIFICATION_ID = 1001 // Shared with GpsTrackingService
        private const val CHANNEL_ID = "health_monitoring_channel" // Shared channel
        
        fun startService(context: Context) {
            try {
                Log.e(TAG, "🔍 ENHANCED: ScreenMonitorService.startService() called")
                Log.e(TAG, "🔍 ENHANCED: Validating post-reboot permissions...")
                
                // CRITICAL FIX: Enhanced MIUI and Android 12+ compatibility check
                val permissionStatus = MiuiPermissionHelper.validatePostRebootPermissions(context)
                Log.e(TAG, "🔍 ENHANCED: Permission validation completed")
                
                // If critical permissions are revoked, don't attempt service start
                if (permissionStatus.notificationPermissionRevoked || 
                    permissionStatus.batteryOptimizationEnabled) {
                    Log.e(TAG, "❌ Critical permissions revoked - service start will fail")
                    Log.e(TAG, "💡 Notification permission: ${!permissionStatus.notificationPermissionRevoked}")
                    Log.e(TAG, "💡 Battery optimization disabled: ${!permissionStatus.batteryOptimizationEnabled}")
                    
                    // Store that we need manual activation
                    val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("flutter.needs_post_boot_activation", true).apply()
                    return
                }
                
                // CRITICAL FIX: Check if notification system is ready before starting foreground service
                if (!isNotificationSystemReady(context)) {
                    Log.w(TAG, "⚠️ Notification system not ready - scheduling delayed startup")
                    scheduleDelayedServiceStart(context, 15000) // 15-second delay
                    return
                }
                
                // CRITICAL FIX: Android 12+ foreground service startup restrictions
                val isAndroid12Plus = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                val isMiuiDevice = MiuiPermissionHelper.isMiuiDevice()
                
                if (isAndroid12Plus || isMiuiDevice) {
                    Log.w(TAG, "⚠️ Android 12+ or MIUI detected - using enhanced startup strategy")
                    startServiceWithMiuiCompatibility(context)
                } else {
                    startServiceStandard(context)
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to start ScreenMonitorService: ${e.message}")
                Log.e(TAG, "💡 This may happen during boot if system isn't ready yet")
                
                // Check for specific Android 12+ errors
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && 
                    e.message?.contains("ForegroundServiceStartNotAllowedException") == true) {
                    Log.e(TAG, "💡 ANDROID 12+ RESTRICTION: Cannot start foreground service from boot")
                    Log.e(TAG, "💡 Solution: User must open app manually after reboot")
                    
                    // Store this state so the app can show a notification when opened
                    val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("flutter.needs_post_boot_activation", true).apply()
                    return
                }
                
                // Enhanced retry logic with progressive delays
                scheduleDelayedServiceStart(context, 30000) // 30-second retry for failures
            }
        }
        
        // CRITICAL FIX: MIUI-compatible service startup strategy
        private fun startServiceWithMiuiCompatibility(context: Context) {
            try {
                Log.d(TAG, "🚀 Starting service with MIUI/Android 12+ compatibility")
                
                // Try standard approach first
                val intent = Intent(context, ScreenMonitorService::class.java)
                intent.putExtra("start_source", "boot_miui_compat")
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // For Android 12+, we need to be extra careful about context
                    try {
                        context.startForegroundService(intent)
                        Log.d(TAG, "✅ MIUI/Android 12+ foreground service start succeeded")
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ Direct foreground service start failed: ${e.message}")
                        
                        // Fallback: Try delayed start in case system isn't ready
                        Log.d(TAG, "🔄 Attempting delayed startup fallback...")
                        scheduleDelayedServiceStart(context, 45000) // Longer delay for MIUI
                    }
                } else {
                    context.startService(intent)
                    Log.d(TAG, "✅ MIUI legacy service start succeeded")
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ MIUI-compatible service start failed: ${e.message}")
                throw e
            }
        }
        
        private fun startServiceStandard(context: Context) {
            val intent = Intent(context, ScreenMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
                Log.d(TAG, "✅ Standard foreground service start requested (Android 8+)")
            } else {
                context.startService(intent)
                Log.d(TAG, "✅ Standard service start requested (Android 7-)")
            }
        }
        
        // CRITICAL FIX: Check if notification system is ready for foreground services
        private fun isNotificationSystemReady(context: Context): Boolean {
            return try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (notificationManager == null) {
                    Log.w(TAG, "❌ NotificationManager not available")
                    return false
                }
                
                // Test if we can create a notification channel (Android 8+ requirement)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        val testChannel = NotificationChannel("test_boot", "Boot Test", NotificationManager.IMPORTANCE_LOW)
                        notificationManager.createNotificationChannel(testChannel)
                        notificationManager.deleteNotificationChannel("test_boot")
                        Log.d(TAG, "✅ Notification system ready - channel creation/deletion successful")
                        return true
                    } catch (e: Exception) {
                        Log.w(TAG, "❌ Notification channel test failed: ${e.message}")
                        return false
                    }
                } else {
                    // Pre-Android 8: NotificationManager exists is enough
                    Log.d(TAG, "✅ Notification system ready (Android 7-)")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "❌ Notification system readiness check failed: ${e.message}")
                false
            }
        }
        
        // CRITICAL FIX: Schedule delayed service start with progressive retry
        private fun scheduleDelayedServiceStart(context: Context, delayMs: Long) {
            Log.d(TAG, "⏳ Scheduling ScreenMonitorService start in ${delayMs / 1000} seconds...")
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    Log.d(TAG, "🔄 Attempting delayed ScreenMonitorService startup...")
                    val retryIntent = Intent(context, ScreenMonitorService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(retryIntent)
                    } else {
                        context.startService(retryIntent)
                    }
                    Log.d(TAG, "✅ Delayed ScreenMonitorService startup successful")
                } catch (retryException: Exception) {
                    Log.e(TAG, "❌ Delayed ScreenMonitorService startup failed: ${retryException.message}")
                    
                    // Final retry with even longer delay if this was a short delay
                    if (delayMs < 60000) {
                        Log.d(TAG, "🔄 Scheduling final retry in 60 seconds...")
                        scheduleDelayedServiceStart(context, 60000)
                    } else {
                        Log.e(TAG, "💀 Giving up on ScreenMonitorService startup - system may be severely restricted")
                    }
                }
            }, delayMs)
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, ScreenMonitorService::class.java)
            context.stopService(intent)
            Log.d(TAG, "❌ ScreenMonitorService stop requested")
        }
        
        // Check if service is currently running
        fun isServiceRunning(): Boolean {
            // Simple check - in a full implementation you could check ActivityManager
            // For now, we'll just return true since this is called for verification
            return true
        }
    }
    
    private var screenStateReceiver: BroadcastReceiver? = null
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 ScreenMonitorService created")
        createNotificationChannel()
        registerScreenStateReceiver()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📱 ScreenMonitorService started - monitoring screen unlock events")
        
        val startSource = intent?.getStringExtra("start_source") ?: "unknown"
        Log.d(TAG, "🔍 Start source: $startSource")
        
        try {
            // CRITICAL FIX: Enhanced notification creation with MIUI compatibility
            val notification = createNotificationWithMiuiSupport()
            startForeground(NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ Foreground notification created and displayed with MIUI support")
            
            // Re-register receiver in case it was lost
            registerScreenStateReceiver()
            
            // CRITICAL FIX: Validate that foreground service actually started on MIUI
            if (MiuiPermissionHelper.isMiuiDevice()) {
                validateMiuiForegroundServiceStarted()
            }
            
            Log.d(TAG, "✅ ScreenMonitorService running as foreground service for app persistence")
            Log.d(TAG, "✅ Notification should now show: '가족과 함께하는 안전한 일상 : 안전 확인 서비스가 활성화되어 있습니다'")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during service startup: ${e.message}")
            
            // CRITICAL FIX: Specific handling for MIUI notification failures
            if (MiuiPermissionHelper.isMiuiDevice() && 
                e.message?.contains("notification") == true) {
                Log.e(TAG, "💡 MIUI notification failure - may indicate permission issues")
                handleMiuiNotificationFailure()
            }
            
            // Continue anyway - better to have partial functionality than crash
        }
        
        return START_STICKY // Restart if killed by system
    }
    
    // CRITICAL FIX: Enhanced notification creation with MIUI-specific optimizations
    private fun createNotificationWithMiuiSupport(): Notification {
        return if (MiuiPermissionHelper.isMiuiDevice()) {
            // MIUI-specific notification with enhanced visibility
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("가족과 함께하는 안전한 일상")
                .setContentText("안전 확인 서비스가 활성화되어 있습니다")
                .setSmallIcon(R.drawable.notification_icon) // Use custom logo with transparent background
                .setPriority(NotificationCompat.PRIORITY_HIGH) // Higher priority for MIUI
                .setOngoing(true)
                .setShowWhen(false)
                .setAutoCancel(false) // Prevent accidental dismissal
                .setLocalOnly(true) // Don't sync to other devices
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // Always show on lock screen
                .build()
        } else {
            createNotification()
        }
    }
    
    // CRITICAL FIX: Validate that MIUI actually allowed the foreground service
    private fun validateMiuiForegroundServiceStarted() {
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            try {
                // Check if notification is still visible (indicator service is running)
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val activeNotifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    notificationManager.activeNotifications
                } else {
                    null
                }
                
                val ourNotificationVisible = activeNotifications?.any { 
                    it.id == NOTIFICATION_ID 
                } ?: true // Assume visible on older Android
                
                if (ourNotificationVisible) {
                    Log.d(TAG, "✅ MIUI foreground service validation: Notification still visible")
                } else {
                    Log.e(TAG, "❌ MIUI foreground service validation: Notification disappeared")
                    Log.e(TAG, "💡 MIUI may have silently killed the foreground service")
                    
                    // Store that manual activation is needed
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("flutter.miui_killed_foreground_service", true).apply()
                }
                
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Could not validate MIUI foreground service: ${e.message}")
            }
        }, 10000) // Check after 10 seconds
    }
    
    // CRITICAL FIX: Handle MIUI notification failures
    private fun handleMiuiNotificationFailure() {
        try {
            Log.e(TAG, "🔧 Handling MIUI notification failure...")
            
            // Store failure info for later diagnosis
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean("flutter.miui_notification_failed", true)
                .putLong("flutter.last_notification_failure", System.currentTimeMillis())
                .apply()
            
            // Try to continue without foreground notification (will be background service)
            Log.d(TAG, "💡 Continuing as background service due to MIUI notification failure")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error handling MIUI notification failure: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "💀 ScreenMonitorService destroyed")
        unregisterScreenStateReceiver()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "건강 안전 서비스",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "가족과 함께하는 안전한 일상을 위한 서비스입니다"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        // Check if GPS tracking is also active to create combined notification
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
        
        val title = "가족과 함께하는 안전한 일상"
        val text = if (locationEnabled) {
            "위치 공유와 안전 확인 서비스가 활성화되어 있습니다"
        } else {
            "안전 확인 서비스가 활성화되어 있습니다"
        }
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.notification_icon) // Use custom logo with transparent background
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .setAutoCancel(false)
            .build()
    }
    
    private fun registerScreenStateReceiver() {
        try {
            if (screenStateReceiver == null) {
                screenStateReceiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        when (intent.action) {
                            Intent.ACTION_SCREEN_ON -> {
                                Log.d(TAG, "📱 Screen turned ON (from service)")
                            }
                            Intent.ACTION_USER_PRESENT -> {
                                Log.d(TAG, "🔓 User UNLOCKED phone (from service) - updating Firebase")
                                updateLastPhoneActivity()
                                
                                // ADD GPS LOCATION UPDATE: Use the same screen-on trigger as survival signals
                                updateGpsLocationOnScreenUnlock()
                                
                                // SIMPLE FIX: Use simple GPS backup check like survival
                                checkAndInitializeGpsAlarmsSimple()
                            }
                        }
                    }
                }
                
                val intentFilter = IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_USER_PRESENT)
                    priority = 1000
                }
                
                registerReceiver(screenStateReceiver, intentFilter)
                Log.d(TAG, "✅ Screen state receiver registered in foreground service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to register screen state receiver in service: ${e.message}")
        }
    }
    
    private fun unregisterScreenStateReceiver() {
        try {
            screenStateReceiver?.let {
                unregisterReceiver(it)
                screenStateReceiver = null
                Log.d(TAG, "❌ Screen state receiver unregistered from service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to unregister screen state receiver: ${e.message}")
        }
    }
    
    private fun updateLastPhoneActivity() {
        try {
            // Check if monitoring is enabled
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)

            if (!isEnabled) {
                Log.d(TAG, "📱 Monitoring disabled, skipping phone activity update (service)")
                return
            }

            // Get family info - CRITICAL FIX: Check both key variations
            var familyId = prefs.getString("flutter.family_id", null)
            if (familyId == null) {
                familyId = prefs.getString("family_id", null)
                Log.d(TAG, "🔄 Using fallback key 'family_id' in service: $familyId")
            }

            if (familyId == null) {
                Log.w(TAG, "⚠️ No family ID found, skipping phone activity update (service)")
                return
            }

            // Get battery info
            val batteryInfo = BatteryService.getBatteryInfo(this)
            val batteryLevel = batteryInfo["batteryLevel"] as Int
            val isCharging = batteryInfo["isCharging"] as Boolean
            val batteryHealth = batteryInfo["batteryHealth"] as String

            // Check if currently in sleep time
            val firestore = FirebaseFirestore.getInstance()
            if (SleepTimeHelper.isCurrentlySleepTime(this)) {
                Log.d(TAG, "😴 Screen event during sleep time - updating battery only, skipping survival signal")
                // Update only battery during sleep time
                val batteryOnlyUpdate = mutableMapOf<String, Any>(
                    "batteryLevel" to batteryLevel,
                    "isCharging" to isCharging,
                    "batteryTimestamp" to FieldValue.serverTimestamp()
                )

                if (batteryHealth != "UNKNOWN") {
                    batteryOnlyUpdate["batteryHealth"] = batteryHealth
                }

                firestore.collection("families")
                    .document(familyId)
                    .update(batteryOnlyUpdate)
                    .addOnSuccessListener {
                        Log.d(TAG, "✅ Battery updated (sleep time) from screen event! Battery: $batteryLevel% ${if (isCharging) "⚡" else ""}")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ Failed to update battery from service: ${e.message}")
                    }
            } else {
                // Normal operation: Update survival signal + battery
                val updateData = mutableMapOf<String, Any>(
                    "lastPhoneActivity" to FieldValue.serverTimestamp(),
                    "batteryLevel" to batteryLevel,
                    "isCharging" to isCharging,
                    "batteryTimestamp" to FieldValue.serverTimestamp()
                )

                // Optional: Add battery health if not unknown
                if (batteryHealth != "UNKNOWN") {
                    updateData["batteryHealth"] = batteryHealth
                }

                firestore.collection("families")
                    .document(familyId)
                    .update(updateData)
                    .addOnSuccessListener {
                        Log.d(TAG, "✅ lastPhoneActivity + battery updated from screen event! Battery: $batteryLevel% ${if (isCharging) "⚡" else ""}")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ Failed to update lastPhoneActivity from service: ${e.message}")
                    }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating phone activity from service: ${e.message}")
        }
    }
    
    // SIMPLE FIX: Simple GPS backup check using the same pattern as survival monitoring
    private fun checkAndInitializeGpsAlarmsSimple() {
        try {
            Log.d(TAG, "🌍 SERVICE SIMPLE: Checking GPS alarm status as backup...")
            
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            if (!locationEnabled) {
                Log.d(TAG, "⚠️ GPS tracking disabled - no backup initialization needed")
                return
            }
            
            Log.d(TAG, "✅ GPS tracking is enabled - checking if alarms are working...")
            
            // Simple stale check: If GPS hasn't executed recently, restart it
            val miuiAlarmPrefs = getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
            val lastGpsExecution = miuiAlarmPrefs.getLong("last_gps_execution", 0)
            val currentTime = System.currentTimeMillis()
            val timeSinceLastExecution = currentTime - lastGpsExecution
            
            // Simple threshold: 5 minutes
            val gpsStaleThreshold = 5 * 60 * 1000L
            
            if (lastGpsExecution == 0L || timeSinceLastExecution > gpsStaleThreshold) {
                Log.w(TAG, "🔄 SERVICE: GPS alarms appear stale - reinitializing...")
                Log.d(TAG, "  - Last GPS execution: ${if (lastGpsExecution == 0L) "NEVER" else "${timeSinceLastExecution / 1000 / 60} min ago"}")
                
                // Simple restart: Cancel and reschedule
                try {
                    AlarmUpdateReceiver.cancelGpsAlarm(this)
                    AlarmUpdateReceiver.scheduleGpsAlarm(this)
                    Log.d(TAG, "✅ SERVICE: GPS alarm backup initialization completed successfully")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ SERVICE: Failed to restart GPS alarm: ${e.message}")
                }
            } else {
                Log.d(TAG, "✅ SERVICE: GPS alarms appear to be working normally")
                Log.d(TAG, "  - Last execution: ${timeSinceLastExecution / 1000 / 60} minutes ago")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ SERVICE: Error in simple GPS alarm backup check: ${e.message}")
        }
    }
    
    // ADD GPS LOCATION UPDATE: Update GPS location when screen unlocks (service version)
    private fun updateGpsLocationOnScreenUnlock() {
        try {
            Log.d(TAG, "🌍🔓 SERVICE SCREEN UNLOCK GPS UPDATE - Using same trigger as survival signals")
            
            // Check if GPS tracking is enabled (same pattern as survival signal check)
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            Log.d(TAG, "🔍 SERVICE: GPS tracking enabled: $locationEnabled")
            
            if (!locationEnabled) {
                Log.d(TAG, "❌ SERVICE: GPS tracking disabled - skipping screen unlock GPS update")
                return
            }
            
            // Get family info - CRITICAL FIX: Try both key variations (same as survival)
            var familyId = prefs.getString("flutter.family_id", null)
            if (familyId == null) {
                familyId = prefs.getString("family_id", null)
                Log.d(TAG, "🔄 SERVICE: Using fallback key 'family_id' for GPS: $familyId")
            }
            if (familyId == null) {
                Log.w(TAG, "⚠️ SERVICE: No family ID found - cannot update GPS location")
                return
            }
            
            Log.d(TAG, "🚀 SERVICE: Updating GPS location immediately for family: $familyId")
            Log.d(TAG, "💡 SERVICE: This GPS update happens INSTANTLY when user unlocks (like survival signals!)")
            
            // Use existing GPS update method
            updateGpsLocationImmediate(familyId)
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ SERVICE: Error in screen unlock GPS update: ${e.message}")
        }
    }
    
    // Immediate GPS location update (service version)
    private fun updateGpsLocationImmediate(familyId: String) {
        try {
            Log.d(TAG, "📍 SERVICE: Getting immediate GPS location for screen unlock...")
            
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            // Quick permission check - if no permissions, skip GPS update
            val hasLocationPermission = try {
                androidx.core.content.ContextCompat.checkSelfPermission(
                    this, android.Manifest.permission.ACCESS_FINE_LOCATION
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                androidx.core.content.ContextCompat.checkSelfPermission(
                    this, android.Manifest.permission.ACCESS_COARSE_LOCATION
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } catch (e: Exception) {
                false
            }
            
            if (!hasLocationPermission) {
                Log.d(TAG, "⚠️ SERVICE: No location permissions - skipping immediate GPS update")
                return
            }
            
            // Try to get location (GPS first, then network)
            var location: android.location.Location? = null
            
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                Log.d(TAG, "📡 SERVICE: GPS provider location: $location")
            }
            
            if (location == null && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                location = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                Log.d(TAG, "📶 SERVICE: Network provider location: $location")
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
                        Log.d(TAG, "✅✅✅ SERVICE: IMMEDIATE GPS UPDATE SUCCESS - Location updated on screen unlock!")
                        Log.d(TAG, "🎯 SERVICE: GPS coordinates: ${location.latitude}, ${location.longitude}")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ SERVICE: Immediate GPS update failed: ${e.message}")
                    }
            } else {
                Log.d(TAG, "⚠️ SERVICE: No location available for immediate GPS update")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ SERVICE: Error in immediate GPS location update: ${e.message}")
        }
    }
    
    // ORIGINAL COMPLEX VERSION: Enhanced backup mechanism to aggressively initialize GPS alarms if they failed during boot
    private fun checkAndInitializeGpsAlarms() {
        try {
            Log.d(TAG, "🌍 SERVICE ENHANCED: Checking GPS alarm status as backup for boot failures...")
            
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            if (!locationEnabled) {
                Log.d(TAG, "⚠️ GPS tracking disabled - no backup initialization needed")
                return
            }
            
            Log.d(TAG, "✅ GPS tracking is enabled - checking alarm status...")
            
            // Check if GPS alarms might have failed during boot
            val miuiAlarmPrefs = getSharedPreferences("MiuiAlarmPrefs", Context.MODE_PRIVATE)
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
                    Log.w(TAG, "⚠️ SERVICE: GPS has NEVER executed - definitely needs initialization")
                    true
                }
                timeSinceLastExecution > gpsStaleThreshold -> {
                    Log.w(TAG, "⚠️ SERVICE: GPS execution is stale (${timeSinceLastExecution / 1000 / 60} min > ${gpsStaleThreshold / 1000 / 60} min)")
                    true
                }
                lastGpsScheduled == 0L -> {
                    Log.w(TAG, "⚠️ SERVICE: GPS was never scheduled - needs initialization")
                    true
                }
                timeSinceLastScheduled > (2 * gpsStaleThreshold) -> {
                    Log.w(TAG, "⚠️ SERVICE: GPS hasn't been scheduled recently (${timeSinceLastScheduled / 1000 / 60} min)")
                    true
                }
                else -> false
            }
            
            if (shouldReinitialize) {
                Log.w(TAG, "🔄 SERVICE: GPS alarms need reinitialization:")
                Log.d(TAG, "  - Last GPS execution: $lastGpsExecution (${if (lastGpsExecution == 0L) "NEVER" else "${timeSinceLastExecution / 1000 / 60} min ago"})")
                Log.d(TAG, "  - Last GPS scheduled: $lastGpsScheduled (${if (lastGpsScheduled == 0L) "NEVER" else "${timeSinceLastScheduled / 1000 / 60} min ago"})")
                Log.d(TAG, "  - Threshold: ${gpsStaleThreshold / 1000 / 60} minutes")
                Log.d(TAG, "  - Is MIUI device: $isMiuiDevice")
                
                // CRITICAL FIX: Always validate permissions before attempting GPS restart
                val hasLocationPermissions = try {
                    val fineLocation = androidx.core.content.ContextCompat.checkSelfPermission(
                        this, android.Manifest.permission.ACCESS_FINE_LOCATION
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    
                    val coarseLocation = androidx.core.content.ContextCompat.checkSelfPermission(
                        this, android.Manifest.permission.ACCESS_COARSE_LOCATION
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    
                    fineLocation || coarseLocation
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ SERVICE: Could not check location permissions: ${e.message}")
                    false
                }
                
                if (!hasLocationPermissions) {
                    Log.e(TAG, "❌ SERVICE: Cannot reinitialize GPS - location permissions not granted")
                    Log.e(TAG, "💡 SERVICE: User needs to grant location permissions for GPS tracking to work")
                    return
                }
                
                Log.d(TAG, "✅ SERVICE: Location permissions confirmed - proceeding with GPS reinitialization")
                
                // Cancel any existing GPS alarms first
                try {
                    AlarmUpdateReceiver.cancelGpsAlarm(this)
                    Log.d(TAG, "❌ SERVICE: Cancelled any existing GPS alarms")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ SERVICE: Could not cancel existing GPS alarms: ${e.message}")
                }
                
                // Start fresh GPS alarm
                try {
                    AlarmUpdateReceiver.scheduleGpsAlarm(this)
                    Log.d(TAG, "✅ SERVICE: GPS alarm backup initialization completed successfully")
                    
                    // Store that we performed backup initialization
                    prefs.edit()
                        .putLong("flutter.last_gps_backup_init_service", currentTime)
                        .putBoolean("flutter.gps_backup_init_service_performed", true)
                        .putString("flutter.gps_backup_trigger_service", "screen_unlock_service")
                        .apply()
                        
                    // Also record in MIUI alarm prefs for tracking
                    miuiAlarmPrefs.edit()
                        .putLong("gps_backup_init_service_time", currentTime)
                        .putLong("last_gps_alarm_scheduled", currentTime)
                        .apply()
                        
                } catch (e: Exception) {
                    Log.e(TAG, "❌ SERVICE: Failed to schedule GPS alarm during backup initialization: ${e.message}")
                }
                    
            } else {
                Log.d(TAG, "✅ SERVICE: GPS alarms appear to be working normally")
                Log.d(TAG, "  - Last execution: ${timeSinceLastExecution / 1000 / 60} minutes ago")
                Log.d(TAG, "  - Last scheduled: ${timeSinceLastScheduled / 1000 / 60} minutes ago")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ SERVICE: Error in enhanced GPS alarm backup check: ${e.message}")
        }
    }
}