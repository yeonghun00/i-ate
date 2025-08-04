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
import com.thousandemfla.thanks_everyday.elder.EnhancedUsageMonitor

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.thousandemfla.thanks_everyday/screen_monitor"
    private val USAGE_DETECTOR_CHANNEL = "thanks_everyday/usage_detector"
    private val OVERLAY_CHANNEL = "overlay_service"
    private val TAG = "MainActivity"
    private val USAGE_STATS_REQUEST_CODE = 100
    private val BATTERY_OPTIMIZATION_REQUEST_CODE = 101
    private val LOCATION_PERMISSION_REQUEST_CODE = 102
    
    private var screenStateReceiver: ScreenStateReceiver? = null
    private var enhancedUsageMonitor: EnhancedUsageMonitor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // ScreenStateReceiver is now registered in AndroidManifest.xml for system-wide detection
    }
    
    override fun onResume() {
        super.onResume()
        
        // Ensure receiver is registered when app comes to foreground
        if (screenStateReceiver == null) {
            registerScreenStateReceiver()
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
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
        
        // Simplified: WorkManager handles all background updates
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
            
            // ScreenStateReceiver is now registered in AndroidManifest.xml for system-wide detection
            
            Log.d(TAG, "GPS-like survival signal monitoring started successfully:")
            Log.d(TAG, "  - AlarmManager: Checks screen state every 2 minutes")
            Log.d(TAG, "  - PowerManager: Detects screen ON/OFF reliably")
            Log.d(TAG, "  - ScreenStateReceiver: Detects immediate unlock (USER_PRESENT)")
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
        Log.d(TAG, "Starting GPS location tracking")
        
        try {
            // Check location permissions
            val hasLocationPermissions = checkLocationPermissions()
            val batteryOptimized = isBatteryOptimizationDisabled()
            
            Log.d(TAG, "Location Tracking Permission Status:")
            Log.d(TAG, "  - Location permissions: $hasLocationPermissions")
            Log.d(TAG, "  - Battery optimization disabled: $batteryOptimized")
            
            // Enable location tracking using new independent method
            AlarmUpdateReceiver.enableLocationTracking(this)
            
            Log.d(TAG, "GPS location tracking started successfully - updates every 2 minutes")
            
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
            
            // Unregister ScreenStateReceiver when monitoring stops
            unregisterScreenStateReceiver()
            
            Log.d(TAG, "GPS-like survival signal monitoring stopped successfully:")
            Log.d(TAG, "  - AlarmManager: Survival signal checks disabled")
            Log.d(TAG, "  - ScreenStateReceiver: Unregistered")
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
        val permissionsToRequest = mutableListOf<String>()
        
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        
        if (permissionsToRequest.isNotEmpty()) {
            Log.d(TAG, "Requesting location permissions: $permissionsToRequest")
            ActivityCompat.requestPermissions(
                this,
                permissionsToRequest.toTypedArray(),
                LOCATION_PERMISSION_REQUEST_CODE
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // If basic location permissions are granted, request background location
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "Requesting background location permission")
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                    LOCATION_PERMISSION_REQUEST_CODE
                )
            }
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
                var allGranted = true
                for (i in permissions.indices) {
                    val permission = permissions[i]
                    val granted = grantResults[i] == PackageManager.PERMISSION_GRANTED
                    Log.d(TAG, "Permission $permission: ${if (granted) "GRANTED" else "DENIED"}")
                    if (!granted) allGranted = false
                }
                
                if (allGranted) {
                    Log.d(TAG, "✅ All requested location permissions granted")
                    // If basic permissions are granted and we're API 29+, request background permission
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && 
                        !permissions.contains(Manifest.permission.ACCESS_BACKGROUND_LOCATION)) {
                        requestLocationPermissions() // This will request background permission
                    }
                } else {
                    Log.w(TAG, "❌ Some location permissions were denied")
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
        Log.d(TAG, "Stopping GPS location tracking")
        
        try {
            // Disable GPS tracking using independent method (survival signal continues if enabled)
            AlarmUpdateReceiver.disableLocationTracking(this)
            
            Log.d(TAG, "GPS location tracking stopped successfully:")
            Log.d(TAG, "  - AlarmManager: Only GPS alarm cancelled")
            Log.d(TAG, "  - Survival signal continues: If survival monitoring is still enabled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop GPS location tracking: ${e.message}")
        }
    }
    
    
    private fun registerScreenStateReceiver() {
        try {
            if (screenStateReceiver == null) {
                screenStateReceiver = ScreenStateReceiver()
                val intentFilter = IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_USER_PRESENT)
                    priority = 1000
                }
                registerReceiver(screenStateReceiver, intentFilter)
                Log.d(TAG, "✅ Screen state receiver registered dynamically for ACTION_SCREEN_ON and ACTION_USER_PRESENT")
            } else {
                Log.d(TAG, "📱 Screen state receiver already registered")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to register screen state receiver: ${e.message}")
        }
    }
    
    private fun unregisterScreenStateReceiver() {
        try {
            screenStateReceiver?.let {
                unregisterReceiver(it)
                screenStateReceiver = null
                Log.d(TAG, "❌ Screen state receiver unregistered")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to unregister screen state receiver: ${e.message}")
        }
    }
    
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
    
}