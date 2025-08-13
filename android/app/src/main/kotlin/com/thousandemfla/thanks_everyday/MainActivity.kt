package com.thousandemfla.thanks_everyday

import android.Manifest
import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.thousandemfla.thanks_everyday.elder.AlarmUpdateReceiver
import com.thousandemfla.thanks_everyday.elder.ScreenStateReceiver
import com.thousandemfla.thanks_everyday.elder.ScreenMonitorService
import com.thousandemfla.thanks_everyday.elder.EnhancedUsageMonitor
import com.thousandemfla.thanks_everyday.elder.MiuiPermissionHelper
import com.thousandemfla.thanks_everyday.elder.AlternativeBootDetector

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.thousandemfla.thanks_everyday/screen_monitor"
    private val USAGE_DETECTOR_CHANNEL = "thanks_everyday/usage_detector"
    private val OVERLAY_CHANNEL = "overlay_service"
    private val MIUI_CHANNEL = "com.thousandemfla.thanks_everyday/miui"
    private val TAG = "MainActivity"
    private val USAGE_STATS_REQUEST_CODE = 100
    private val BATTERY_OPTIMIZATION_REQUEST_CODE = 101
    private val LOCATION_PERMISSION_REQUEST_CODE = 102
    
    private var screenStateReceiver: ScreenStateReceiver? = null
    private var enhancedUsageMonitor: EnhancedUsageMonitor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // CRITICAL FIX: Check for alternative boot detection on app launch
        checkAlternativeBootOnAppLaunch()
        
        // CRITICAL FIX: Ensure survival monitoring is restored on app startup
        // This handles cases where app was killed and user opens it again
        restoreMonitoringOnStartup()
    }
    
    override fun onResume() {
        super.onResume()
        
        // CRITICAL FIX: ScreenStateReceiver is now ONLY registered in AndroidManifest.xml
        // This ensures it works even when app is closed/killed
        // No dynamic registration needed anymore - all handled by system
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // Clean up EnhancedUsageMonitor to prevent memory leak
        try {
            enhancedUsageMonitor?.stopMonitoring()
            enhancedUsageMonitor = null
            Log.d(TAG, "✅ EnhancedUsageMonitor cleaned up")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error cleaning up EnhancedUsageMonitor: ${e.message}")
        }
        
        // ScreenStateReceiver is managed by system (AndroidManifest.xml)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Enhanced Usage Monitor
        val usageDetectorChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_DETECTOR_CHANNEL)
        enhancedUsageMonitor = EnhancedUsageMonitor(this, usageDetectorChannel)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenMonitoring" -> {
                    startGpsLikeSurvivalSignalMonitoring()
                    result.success(true)
                }
                "startLocationTracking" -> {
                    startLocationTracking()
                    result.success(true)
                }
                "stopScreenMonitoring" -> {
                    stopGpsLikeSurvivalSignalMonitoring()
                    result.success(true)
                }
                "checkPermissions" -> {
                    val hasPermissions = checkRequiredPermissions()
                    result.success(hasPermissions)
                }
                "checkLocationPermissions" -> {
                    val hasLocationPermissions = checkLocationPermissions()
                    result.success(hasLocationPermissions)
                }
                "requestLocationPermissions" -> {
                    requestLocationPermissions()
                    result.success(true)
                }
                "requestBackgroundLocationPermission" -> {
                    requestBackgroundLocationPermission()
                    result.success(true)
                }
                "checkUsageStatsPermission" -> {
                    val hasPermission = hasUsageStatsPermission()
                    result.success(hasPermission)
                }
                "checkBatteryOptimization" -> {
                    val isDisabled = isBatteryOptimizationDisabled()
                    result.success(isDisabled)
                }
                "requestPermissions" -> {
                    requestRequiredPermissions()
                    result.success(true)
                }
                "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission()
                    result.success(true)
                }
                "requestBatteryOptimizationDisable" -> {
                    requestDisableBatteryOptimization()
                    result.success(true)
                }
                "checkAutoStartPermission" -> {
                    val autoStartInfo = checkAutoStartPermission()
                    result.success(autoStartInfo)
                }
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(true)
                }
                "checkAdvancedBatteryOptimization" -> {
                    val batteryInfo = checkAdvancedBatteryOptimization()
                    result.success(batteryInfo)
                }
                "openMIUIBatterySettings" -> {
                    openMIUIBatterySettings()
                    result.success(true)
                }
                "checkExactAlarmPermission" -> {
                    val canScheduleExact = checkExactAlarmPermission()
                    result.success(canScheduleExact)
                }
                "requestExactAlarmPermission" -> {
                    requestExactAlarmPermission()
                    result.success(true)
                }
                "getBootDebugLog" -> {
                    val logContent = getBootDebugLog()
                    result.success(logContent)
                }
                "getScreenOnCount" -> {
                    val count = getScreenOnCount()
                    result.success(count)
                }
                "getLastScreenActivity" -> {
                    val timestamp = getLastScreenActivity()
                    result.success(timestamp)
                }
                "startLocationMonitoring" -> {
                    startLocationMonitoring()
                    result.success(true)
                }
                "stopLocationMonitoring" -> {
                    stopLocationMonitoring()
                    result.success(true)
                }
                "checkMiuiDevice" -> {
                    val isMiui = android.os.Build.MANUFACTURER.lowercase().contains("xiaomi")
                    result.success(isMiui)
                }
                "getMiuiGuidanceInfo" -> {
                    val guidanceInfo = MiuiPermissionHelper.getMiuiGuidanceInfo(this)
                    result.success(guidanceInfo)
                }
                "openMiuiAutoStartSettings" -> {
                    val success = MiuiPermissionHelper.openAutoStartSettings(this)
                    result.success(success)
                }
                "openMiuiBatterySettings" -> {
                    val success = MiuiPermissionHelper.openAutoStartSettings(this)
                    result.success(success)
                }
                "getMiuiBootStatus" -> {
                    val status = mapOf(
                        "isMiuiDevice" to MiuiPermissionHelper.isMiuiDevice(),
                        "hasAutoStartPermission" to MiuiPermissionHelper.checkAutoStartPermission(this)
                    )
                    result.success(status)
                }
                "getAlternativeBootStatus" -> {
                    val status = AlternativeBootDetector.getAlternativeDetectionStatus(this)
                    result.success(status)
                }
                "startAlternativeBootDetection" -> {
                    AlternativeBootDetector.startAlternativeDetection(this)
                    result.success(true)
                }
                "stopAlternativeBootDetection" -> {
                    AlternativeBootDetector.stopAlternativeDetection(this)
                    result.success(true)
                }
                "markMiuiSetupShown" -> {
                    MiuiPermissionHelper.markUserGuided(this)
                    result.success(true)
                }
                "manualResumeMonitoring" -> {
                    manualResumeMonitoring()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Enhanced Usage Detector Channel
        usageDetectorChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenMonitoring" -> {
                    enhancedUsageMonitor?.startMonitoring()
                    result.success(true)
                }
                "stopScreenMonitoring" -> {
                    enhancedUsageMonitor?.stopMonitoring()
                    result.success(true)
                }
                "getUsageStats" -> {
                    val stats = enhancedUsageMonitor?.getUsageStats() ?: emptyMap<String, Any>()
                    result.success(stats)
                }
                "isScreenCurrentlyOn" -> {
                    val isScreenOn = isScreenCurrentlyOn()
                    result.success(isScreenOn)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Setup overlay service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startInvisibleOverlay" -> {
                    val success = startInvisibleOverlay()
                    result.success(success)
                }
                "stopInvisibleOverlay" -> {
                    val success = stopInvisibleOverlay()
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // MIUI device detection channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MIUI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isMiuiDevice" -> {
                    val isMiui = MiuiPermissionHelper.isMiuiDevice()
                    result.success(isMiui)
                }
                "requestAutoStartPermission" -> {
                    val success = requestAutoStartPermission()
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // CRITICAL FIX: All background monitoring handled by AlarmUpdateReceiver + ScreenStateReceiver
        // Both registered in AndroidManifest.xml for maximum reliability
    }
    
    // Request MIUI autostart permission
    private fun requestAutoStartPermission(): Boolean {
        return try {
            if (MiuiPermissionHelper.isMiuiDevice()) {
                // Try to open MIUI autostart settings
                val intent = Intent().apply {
                    component = android.content.ComponentName(
                        "com.miui.securitycenter", 
                        "com.miui.permcenter.autostart.AutoStartManagementActivity"
                    )
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                
                // Fallback to security center if autostart activity not found
                val fallbackIntent = Intent().apply {
                    component = android.content.ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.securitycenter.Main"
                    )
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                
                try {
                    startActivity(intent)
                    true
                } catch (e: Exception) {
                    Log.w(TAG, "Primary autostart intent failed, trying fallback: ${e.message}")
                    try {
                        startActivity(fallbackIntent)
                        true
                    } catch (e2: Exception) {
                        Log.e(TAG, "Both autostart intents failed: ${e2.message}")
                        false
                    }
                }
            } else {
                Log.d(TAG, "Not a MIUI device, autostart permission not needed")
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting autostart permission: ${e.message}")
            false
        }
    }
    
    // CRITICAL FIX: Restore monitoring on app startup
    private fun restoreMonitoringOnStartup() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            Log.d(TAG, "🔄 Restoring monitoring on startup - Survival: $survivalEnabled, Location: $locationEnabled")
            
            if (survivalEnabled) {
                Log.d(TAG, "✅ Restoring survival monitoring alarms")
                AlarmUpdateReceiver.scheduleSurvivalAlarm(this)
                
                // CRITICAL FIX: Restart ScreenMonitorService for app persistence
                Log.d(TAG, "✅ Restarting ScreenMonitorService for app persistence")
                ScreenMonitorService.startService(this)
            }
            
            if (locationEnabled) {
                Log.d(TAG, "✅ Restoring GPS location tracking with alarm approach") 
                AlarmUpdateReceiver.enableLocationTracking(this)
            }
            
            if (!survivalEnabled && !locationEnabled) {
                Log.d(TAG, "ℹ️ No monitoring services enabled - nothing to restore")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error restoring monitoring on startup: ${e.message}")
        }
    }

    private fun startGpsLikeSurvivalSignalMonitoring() {
        Log.d(TAG, "Starting GPS-like survival signal monitoring")
        
        try {
            // Check permissions status (less restrictive than complex approach)
            val batteryOptimized = isBatteryOptimizationDisabled()
            
            Log.d(TAG, "GPS-like Survival Signal Status:")
            Log.d(TAG, "  - Battery optimization disabled: $batteryOptimized")
            
            // Use the GPS-like approach from AlarmUpdateReceiver
            AlarmUpdateReceiver.enableSurvivalMonitoring(this)
            
            // CRITICAL FIX: Start ScreenMonitorService for enhanced app persistence
            // This foreground service helps prevent app termination and provides backup unlock detection
            ScreenMonitorService.startService(this)
            
            // ScreenStateReceiver is now registered in AndroidManifest.xml for system-wide detection
            // No dynamic registration - this ensures immediate unlock detection works when app is closed
            
            Log.d(TAG, "GPS-like survival signal monitoring started successfully:")
            Log.d(TAG, "  - AlarmManager: Checks screen state every 2 minutes")
            Log.d(TAG, "  - PowerManager: Detects screen ON/OFF reliably")
            Log.d(TAG, "  - ScreenStateReceiver: Detects immediate unlock (USER_PRESENT) from AndroidManifest.xml")
            Log.d(TAG, "  - ScreenMonitorService: Foreground service provides backup detection & app persistence")
            Log.d(TAG, "  - Firebase: Updates 'lastPhoneActivity' field")
            Log.d(TAG, "  - Persistence: Works even when app is killed/phone reboots")
            
            if (!batteryOptimized) {
                Log.w(TAG, "⚠️ Battery optimization not disabled - may affect reliability!")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start GPS-like survival signal monitoring: ${e.message}")
        }
    }
    
    private fun startLocationTracking() {
        Log.d(TAG, "🌍 Starting GPS location tracking with RESTORED ALARM APPROACH")
        
        try {
            // Check location permissions
            val hasLocationPermissions = checkLocationPermissions()
            val batteryOptimized = isBatteryOptimizationDisabled()
            
            Log.d(TAG, "Location Tracking Permission Status:")
            Log.d(TAG, "  - Location permissions: $hasLocationPermissions")
            Log.d(TAG, "  - Battery optimization disabled: $batteryOptimized")
            
            // RESTORED: Use proven GPS alarm approach that survives app termination
            AlarmUpdateReceiver.enableLocationTracking(this)
            
            Log.d(TAG, "✅ GPS alarm tracking started successfully - survives app termination")
            Log.d(TAG, "✅ This alarm approach was working before the service changes!")
            
            if (!hasLocationPermissions) {
                Log.w(TAG, "⚠️ Location permissions missing - GPS tracking will not work!")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start GPS location tracking: ${e.message}")
        }
    }

    private fun stopGpsLikeSurvivalSignalMonitoring() {
        Log.d(TAG, "Stopping GPS-like survival signal monitoring")
        
        try {
            // Use the GPS-like approach from AlarmUpdateReceiver
            AlarmUpdateReceiver.disableSurvivalMonitoring(this)
            
            // CRITICAL FIX: Stop ScreenMonitorService when disabling survival monitoring
            ScreenMonitorService.stopService(this)
            
            // ScreenStateReceiver remains active (managed by AndroidManifest.xml)
            // It only updates Firebase when monitoring is enabled, so no action needed
            
            Log.d(TAG, "GPS-like survival signal monitoring stopped successfully:")
            Log.d(TAG, "  - AlarmManager: Survival signal checks disabled")
            Log.d(TAG, "  - ScreenMonitorService: Foreground service stopped")
            Log.d(TAG, "  - ScreenStateReceiver: Remains active but only updates when monitoring enabled")
            Log.d(TAG, "  - Location tracking may continue if enabled separately")
            Log.d(TAG, "  - Firebase: No more survival signal updates")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop GPS-like survival signal monitoring: ${e.message}")
        }
    }

    private fun checkRequiredPermissions(): Boolean {
        // For GPS-like survival signal: only need battery optimization disabled
        // For location tracking: need location permissions
        // Usage stats not required for GPS-like approach using PowerManager
        return isBatteryOptimizationDisabled() && checkLocationPermissions()
    }
    
    private fun checkLocationPermissions(): Boolean {
        val fineLocationGranted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        val coarseLocationGranted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        val backgroundLocationGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Not required for API < 29
        }
        
        Log.d(TAG, "Location permissions - Fine: $fineLocationGranted, Coarse: $coarseLocationGranted, Background: $backgroundLocationGranted")
        
        return fineLocationGranted && coarseLocationGranted && backgroundLocationGranted
    }
    
    private fun requestLocationPermissions() {
        // STEP 1: Request foreground location permissions first
        val foregroundPermissionsToRequest = mutableListOf<String>()
        
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            foregroundPermissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            foregroundPermissionsToRequest.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        
        if (foregroundPermissionsToRequest.isNotEmpty()) {
            Log.d(TAG, "🔄 STEP 1: Requesting foreground location permissions: $foregroundPermissionsToRequest")
            ActivityCompat.requestPermissions(
                this,
                foregroundPermissionsToRequest.toTypedArray(),
                LOCATION_PERMISSION_REQUEST_CODE
            )
        } else {
            // STEP 2: If foreground permissions are already granted, request background permission
            requestBackgroundLocationPermission()
        }
    }
    
    private fun requestBackgroundLocationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "🔄 STEP 2: Requesting background location permission (this triggers 'Always allow' option)")
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                    LOCATION_PERMISSION_REQUEST_CODE + 1 // Different request code for background permission
                )
            } else {
                Log.d(TAG, "✅ Background location permission already granted")
            }
        } else {
            Log.d(TAG, "ℹ️ Background location permission not required for API < 29")
        }
    }

    private fun requestRequiredPermissions() {
        if (!checkLocationPermissions()) {
            requestLocationPermissions()
        } else if (!isBatteryOptimizationDisabled()) {
            requestDisableBatteryOptimization()
        }
        // Note: Usage stats permission no longer required for GPS-like survival signal
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        when (requestCode) {
            LOCATION_PERMISSION_REQUEST_CODE -> {
                // Handle foreground location permissions
                var allGranted = true
                for (i in permissions.indices) {
                    val permission = permissions[i]
                    val granted = grantResults[i] == PackageManager.PERMISSION_GRANTED
                    Log.d(TAG, "Foreground permission $permission: ${if (granted) "GRANTED" else "DENIED"}")
                    if (!granted) allGranted = false
                }
                
                if (allGranted) {
                    Log.d(TAG, "✅ All foreground location permissions granted")
                    // STEP 2: Now request background location permission
                    requestBackgroundLocationPermission()
                } else {
                    Log.w(TAG, "❌ Some foreground location permissions were denied - cannot proceed to background permission")
                }
            }
            LOCATION_PERMISSION_REQUEST_CODE + 1 -> {
                // Handle background location permission
                for (i in permissions.indices) {
                    val permission = permissions[i]
                    val granted = grantResults[i] == PackageManager.PERMISSION_GRANTED
                    if (permission == Manifest.permission.ACCESS_BACKGROUND_LOCATION) {
                        if (granted) {
                            Log.d(TAG, "🎉 SUCCESS: Background location permission GRANTED - 'Always allow' was selected!")
                            Log.d(TAG, "✅ GPS will now work continuously in background even when app is killed")
                        } else {
                            Log.w(TAG, "⚠️ Background location permission DENIED - user selected 'While using app' or denied")
                            Log.w(TAG, "📱 GPS tracking will only work when app is in foreground or recently used")
                        }
                    }
                }
            }
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageStatsPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.data = Uri.parse("package:$packageName")
        startActivityForResult(intent, USAGE_STATS_REQUEST_CODE)
    }

    private fun isBatteryOptimizationDisabled(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            return powerManager.isIgnoringBatteryOptimizations(packageName)
        }
        return true
    }

    private fun requestDisableBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")
            startActivityForResult(intent, BATTERY_OPTIMIZATION_REQUEST_CODE)
        }
    }

    private fun getScreenOnCount(): Int {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getInt("flutter.screen_on_count", 0)
    }

    private fun getLastScreenActivity(): Long {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getLong("flutter.last_screen_on_timestamp", 0)
    }


    private fun startInvisibleOverlay(): Boolean {
        return try {
            // Check if overlay permission is granted
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(this)) {
                    Log.w(TAG, "Overlay permission not granted")
                    return false
                }
            }
            
            // The overlay permission itself helps with app persistence
            // We don't need to actually show anything visible
            // Just having the permission makes Android treat our app as higher priority
            Log.d(TAG, "Invisible overlay started (permission-based persistence)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start invisible overlay: ${e.message}")
            false
        }
    }
    
    private fun stopInvisibleOverlay(): Boolean {
        return try {
            // Since we're not actually showing anything, just return success
            Log.d(TAG, "Invisible overlay stopped")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop invisible overlay: ${e.message}")
            false
        }
    }

    private fun startLocationMonitoring() {
        Log.d(TAG, "Location monitoring integrated with AlarmUpdateReceiver")
        
        try {
            // Location monitoring is now handled by AlarmUpdateReceiver
            // Just ensure AlarmManager is scheduled
            AlarmUpdateReceiver.scheduleAlarms(this)
            Log.d(TAG, "Location monitoring started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start location monitoring: ${e.message}")
        }
    }

    private fun stopLocationMonitoring() {
        Log.d(TAG, "🛑 Stopping GPS location tracking")
        
        try {
            // RESTORED: Stop GPS alarm approach
            AlarmUpdateReceiver.disableLocationTracking(this)
            
            Log.d(TAG, "✅ GPS alarm tracking stopped successfully:")
            Log.d(TAG, "  - GPS alarms: Cancelled")
            Log.d(TAG, "  - Survival signal continues: If survival monitoring is still enabled")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to stop GPS location tracking: ${e.message}")
        }
    }
    
    // CRITICAL FIX: Dynamic registration methods removed
    // All receivers now registered in AndroidManifest.xml for better reliability
    
    private fun isScreenCurrentlyOn(): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
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
    
    // CRITICAL: Check OEM-specific auto-start permissions
    private fun checkAutoStartPermission(): HashMap<String, Any> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val model = Build.MODEL.lowercase()
        val brand = Build.BRAND.lowercase()
        
        Log.d(TAG, "🔍 Checking auto-start permission for device:")
        Log.d(TAG, "  - Manufacturer: $manufacturer")
        Log.d(TAG, "  - Brand: $brand")
        Log.d(TAG, "  - Model: $model")
        
        val oemInfo = when {
            manufacturer.contains("xiaomi") || brand.contains("xiaomi") -> {
                hashMapOf<String, Any>(
                    "oem" to "MIUI",
                    "requiresAutoStart" to true,
                    "settingsName" to "자동 시작",
                    "instructions" to "설정 → 앱 → 권한 → 자동시작 → 이 앱을 허용으로 변경하세요"
                )
            }
            manufacturer.contains("oppo") || brand.contains("oppo") -> {
                hashMapOf<String, Any>(
                    "oem" to "ColorOS",
                    "requiresAutoStart" to true,
                    "settingsName" to "자동 시작",
                    "instructions" to "설정 → 앱 관리 → 자동시작 관리 → 이 앱을 허용으로 변경하세요"
                )
            }
            manufacturer.contains("vivo") || brand.contains("vivo") -> {
                hashMapOf<String, Any>(
                    "oem" to "FunTouch OS",
                    "requiresAutoStart" to true,
                    "settingsName" to "자동 시작",
                    "instructions" to "설정 → 더보기 설정 → 권한 관리 → 자동시작 → 이 앱을 허용으로 변경하세요"
                )
            }
            manufacturer.contains("huawei") || brand.contains("huawei") -> {
                hashMapOf<String, Any>(
                    "oem" to "EMUI",
                    "requiresAutoStart" to true,
                    "settingsName" to "자동 시작",
                    "instructions" to "설정 → 앱 → 앱 시작 관리 → 이 앱을 수동으로 관리하고 모두 허용하세요"
                )
            }
            manufacturer.contains("honor") || brand.contains("honor") -> {
                hashMapOf<String, Any>(
                    "oem" to "Magic UI",
                    "requiresAutoStart" to true,
                    "settingsName" to "자동 시작",
                    "instructions" to "설정 → 앱 → 앱 시작 관리 → 이 앱을 수동으로 관리하고 모두 허용하세요"
                )
            }
            manufacturer.contains("oneplus") || brand.contains("oneplus") -> {
                hashMapOf<String, Any>(
                    "oem" to "OxygenOS",
                    "requiresAutoStart" to true,
                    "settingsName" to "자동 시작",
                    "instructions" to "설정 → 앱 → 특별한 앱 접근 → 자동시작 → 이 앱을 허용으로 변경하세요"
                )
            }
            else -> {
                hashMapOf<String, Any>(
                    "oem" to "Stock Android",
                    "requiresAutoStart" to false,
                    "settingsName" to "",
                    "instructions" to ""
                )
            }
        }
        
        val hasBootPermission = checkSelfPermission(android.Manifest.permission.RECEIVE_BOOT_COMPLETED) == 
                android.content.pm.PackageManager.PERMISSION_GRANTED
        
        Log.d(TAG, "🔍 Auto-start analysis:")
        Log.d(TAG, "  - OEM: ${oemInfo["oem"]}")
        Log.d(TAG, "  - Requires auto-start: ${oemInfo["requiresAutoStart"]}")
        Log.d(TAG, "  - BOOT permission: $hasBootPermission")
        
        return hashMapOf<String, Any>(
            "manufacturer" to manufacturer,
            "brand" to brand,
            "model" to model,
            "oem" to (oemInfo["oem"] ?: ""),
            "requiresAutoStart" to (oemInfo["requiresAutoStart"] ?: false),
            "settingsName" to (oemInfo["settingsName"] ?: ""),
            "instructions" to (oemInfo["instructions"] ?: ""),
            "hasBootPermission" to hasBootPermission
        )
    }
    
    private fun openAutoStartSettings() {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        
        try {
            val intent = when {
                manufacturer.contains("xiaomi") || brand.contains("xiaomi") -> {
                    // MIUI Auto-start settings
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.miui.securitycenter", 
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                    }
                }
                manufacturer.contains("oppo") || brand.contains("oppo") -> {
                    // ColorOS Auto-start settings
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.coloros.safecenter", 
                            "com.coloros.safecenter.permission.startup.FakeActivity"
                        )
                    }
                }
                manufacturer.contains("vivo") || brand.contains("vivo") -> {
                    // Vivo Auto-start settings
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.iqoo.secure", 
                            "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                        )
                    }
                }
                manufacturer.contains("huawei") || brand.contains("huawei") -> {
                    // EMUI Auto-start settings
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.huawei.systemmanager", 
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                    }
                }
                manufacturer.contains("honor") || brand.contains("honor") -> {
                    // Honor Auto-start settings
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.huawei.systemmanager", 
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                    }
                }
                manufacturer.contains("oneplus") || brand.contains("oneplus") -> {
                    // OnePlus Auto-start settings
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.oneplus.security", 
                            "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
                        )
                    }
                }
                else -> {
                    // Fallback to general app settings
                    Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.fromParts("package", packageName, null)
                    }
                }
            }
            
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            
            Log.d(TAG, "✅ Opened auto-start settings for $manufacturer")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to open auto-start settings: ${e.message}")
            
            // Fallback to general app settings
            try {
                val fallbackIntent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(fallbackIntent)
                Log.d(TAG, "✅ Opened fallback app settings")
            } catch (fallbackException: Exception) {
                Log.e(TAG, "❌ Fallback also failed: ${fallbackException.message}")
            }
        }
    }
    
    // CRITICAL: Check advanced battery optimization for OEM devices
    private fun checkAdvancedBatteryOptimization(): HashMap<String, Any> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        
        // Check standard battery optimization
        val standardBatteryOptimized = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager?
            powerManager?.let { !it.isIgnoringBatteryOptimizations(packageName) } ?: false
        } else {
            false
        }
        
        Log.d(TAG, "🔋 Battery optimization check:")
        Log.d(TAG, "  - Standard battery optimized: $standardBatteryOptimized")
        Log.d(TAG, "  - Manufacturer: $manufacturer")
        
        // OEM-specific battery optimization guidance
        val oemBatteryInfo = when {
            manufacturer.contains("xiaomi") || brand.contains("xiaomi") -> {
                hashMapOf<String, Any>(
                    "oem" to "MIUI",
                    "hasAdvancedBattery" to true,
                    "batterySettingsName" to "배터리 절약",
                    "instructions" to "설정 → 배터리 → 앱 배터리 절약 → 이 앱을 '제한 없음'으로 설정하고, 개발자 옵션에서 MIUI 최적화도 비활성화하세요",
                    "additionalSteps" to "개발자 옵션 → MIUI 최적화 끄기도 필요할 수 있습니다"
                )
            }
            manufacturer.contains("oppo") || brand.contains("oppo") -> {
                hashMapOf<String, Any>(
                    "oem" to "ColorOS",
                    "hasAdvancedBattery" to true,
                    "batterySettingsName" to "배터리 최적화",
                    "instructions" to "설정 → 배터리 → 앱 배터리 사용량 → 이 앱을 '제한하지 않음'으로 설정하세요",
                    "additionalSteps" to "추가로 '백그라운드 앱 관리'에서도 허용해야 합니다"
                )
            }
            manufacturer.contains("vivo") || brand.contains("vivo") -> {
                hashMapOf<String, Any>(
                    "oem" to "FunTouch OS",
                    "hasAdvancedBattery" to true,
                    "batterySettingsName" to "배터리 최적화",
                    "instructions" to "설정 → 배터리 → 백그라운드 앱 새로 고침 → 이 앱을 허용으로 설정하세요",
                    "additionalSteps" to ""
                )
            }
            manufacturer.contains("huawei") || brand.contains("huawei") -> {
                hashMapOf<String, Any>(
                    "oem" to "EMUI",
                    "hasAdvancedBattery" to true,
                    "batterySettingsName" to "배터리 최적화",
                    "instructions" to "설정 → 배터리 → 앱 실행 → 이 앱을 수동 관리로 설정하고 모든 옵션을 허용하세요",
                    "additionalSteps" to ""
                )
            }
            else -> {
                hashMapOf<String, Any>(
                    "oem" to "Stock Android",
                    "hasAdvancedBattery" to false,
                    "batterySettingsName" to "",
                    "instructions" to "",
                    "additionalSteps" to ""
                )
            }
        }
        
        return hashMapOf<String, Any>(
            "manufacturer" to manufacturer,
            "brand" to brand,
            "standardBatteryOptimized" to standardBatteryOptimized,
            "oem" to (oemBatteryInfo["oem"] ?: ""),
            "hasAdvancedBattery" to (oemBatteryInfo["hasAdvancedBattery"] ?: false),
            "batterySettingsName" to (oemBatteryInfo["batterySettingsName"] ?: ""),
            "instructions" to (oemBatteryInfo["instructions"] ?: ""),
            "additionalSteps" to (oemBatteryInfo["additionalSteps"] ?: "")
        )
    }
    
    private fun openMIUIBatterySettings() {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        
        try {
            val intent = when {
                manufacturer.contains("xiaomi") || brand.contains("xiaomi") -> {
                    // MIUI Battery settings
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.miui.powerkeeper", 
                            "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
                        )
                        putExtra("package_name", packageName)
                        putExtra("package_label", applicationInfo.labelRes)
                    }
                }
                manufacturer.contains("oppo") || brand.contains("oppo") -> {
                    // ColorOS Battery settings
                    Intent("android.settings.APPLICATION_DETAILS_SETTINGS").apply {
                        data = android.net.Uri.fromParts("package", packageName, null)
                    }
                }
                else -> {
                    // Standard battery optimization settings
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                    } else {
                        Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = android.net.Uri.fromParts("package", packageName, null)
                        }
                    }
                }
            }
            
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            
            Log.d(TAG, "✅ Opened battery settings for $manufacturer")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to open battery settings: ${e.message}")
            
            // Fallback to standard battery optimization
            try {
                val fallbackIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                } else {
                    Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.fromParts("package", packageName, null)
                    }
                }
                fallbackIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(fallbackIntent)
                Log.d(TAG, "✅ Opened fallback battery settings")
            } catch (fallbackException: Exception) {
                Log.e(TAG, "❌ Fallback battery settings also failed: ${fallbackException.message}")
            }
        }
    }
    
    // CRITICAL: Check exact alarm permission for Android 12+
    private fun checkExactAlarmPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true // Not required on older versions
        }
    }
    
    // CRITICAL: Request exact alarm permission for Android 12+
    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                try {
                    val intent = Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                        data = android.net.Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    Log.d(TAG, "✅ Opened exact alarm permission settings")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Failed to open exact alarm permission settings: ${e.message}")
                }
            } else {
                Log.d(TAG, "✅ Exact alarm permission already granted")
            }
        } else {
            Log.d(TAG, "ℹ️ Exact alarm permission not required on Android < 12")
        }
    }
    
    // Get boot debug log content for display in Flutter
    private fun getBootDebugLog(): String {
        return try {
            val bootLogFile = java.io.File(filesDir, "boot_debug_log.txt")
            if (bootLogFile.exists()) {
                bootLogFile.readText(Charsets.UTF_8)
            } else {
                "No boot debug log found. This means either:\n1. Device hasn't been rebooted since app installation\n2. BootReceiver is not triggering\n3. File creation failed\n\nTo test: Reboot your device and check this screen again."
            }
        } catch (e: Exception) {
            "Error reading boot debug log: ${e.message}"
        }
    }
    
    /**
     * Check for alternative boot detection on app launch
     */
    private fun checkAlternativeBootOnAppLaunch() {
        try {
            Log.d(TAG, "🔍 Checking for alternative boot detection on app launch...")
            
            // Use AlternativeBootDetector to check if device was rebooted
            val bootDetected = AlternativeBootDetector.checkForMissedBoot(this)
            
            if (bootDetected) {
                Log.d(TAG, "🎉 Alternative boot detected on app launch!")
            } else {
                Log.d(TAG, "ℹ️ No alternative boot detected - normal app launch")
            }
            
            // Start alternative detection systems for future boots
            AlternativeBootDetector.startAlternativeDetection(this)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in alternative boot check: ${e.message}")
        }
    }
    
    /**
     * Manual resume monitoring - allows user to manually restart all monitoring
     */
    private fun manualResumeMonitoring() {
        try {
            Log.d(TAG, "🔄 Manual resume monitoring requested by user...")
            
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            val locationEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            Log.d(TAG, "📱 Manual resume - Current settings:")
            Log.d(TAG, "  - Survival monitoring: $survivalEnabled")
            Log.d(TAG, "  - Location tracking: $locationEnabled")
            
            if (!survivalEnabled && !locationEnabled) {
                Log.w(TAG, "⚠️ No monitoring services enabled - nothing to resume")
                return
            }
            
            // Force restart all monitoring components
            if (survivalEnabled) {
                Log.d(TAG, "🚀 Manually restarting survival monitoring...")
                AlarmUpdateReceiver.enableSurvivalMonitoring(this)
                ScreenMonitorService.startService(this)
            }
            
            if (locationEnabled) {
                Log.d(TAG, "🌍 Manually restarting location tracking...")
                AlarmUpdateReceiver.enableLocationTracking(this)
            }
            
            // Restart alternative boot detection
            AlternativeBootDetector.startAlternativeDetection(this)
            
            // Check if this is a MIUI device and record manual activation
            if (MiuiPermissionHelper.isMiuiDevice()) {
                Log.d(TAG, "📱 MIUI device - recording manual monitoring activation")
                prefs.edit()
                    .putBoolean("flutter.manual_monitoring_activated", true)
                    .putLong("flutter.manual_activation_time", System.currentTimeMillis())
                    .apply()
            }
            
            Log.d(TAG, "✅ Manual resume monitoring completed successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in manual resume monitoring: ${e.message}")
        }
    }
    
    // Simple MIUI autostart opener
    private fun openMIUIAutostartSettings() {
        try {
            val intent = Intent()
            intent.component = android.content.ComponentName("com.miui.securitycenter", 
                "com.miui.permcenter.autostart.AutoStartManagementActivity")
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback to general app settings
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = android.net.Uri.parse("package:$packageName")
            startActivity(intent)
        }
    }
    
}