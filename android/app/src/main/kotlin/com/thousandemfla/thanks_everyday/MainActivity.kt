package com.thousandemfla.thanks_everyday.elder

import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.thousandemfla.thanks_everyday.elder.SurvivalMonitorWorker

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.thousandemfla.thanks_everyday.elder/screen_monitor"
    private val OVERLAY_CHANNEL = "overlay_service"
    private val TAG = "MainActivity"
    private val USAGE_STATS_REQUEST_CODE = 100
    private val BATTERY_OPTIMIZATION_REQUEST_CODE = 101
    
    private var inactivityReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenMonitoring" -> {
                    startScreenMonitoring()
                    result.success(true)
                }
                "stopScreenMonitoring" -> {
                    stopScreenMonitoring()
                    result.success(true)
                }
                "checkPermissions" -> {
                    val hasPermissions = checkRequiredPermissions()
                    result.success(hasPermissions)
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
        
        setupInactivityReceiver()
    }

    private fun startScreenMonitoring() {
        Log.d(TAG, "Starting screen monitoring service")
        
        try {
            // Start background service for screen event monitoring
            val serviceIntent = Intent(this, ScreenMonitorService::class.java)
            startService(serviceIntent)
            
            // Also schedule WorkManager for periodic inactivity checks
            SurvivalMonitorWorker.scheduleWork(this)
            
            Log.d(TAG, "Screen monitoring started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start screen monitoring: ${e.message}")
        }
    }

    private fun stopScreenMonitoring() {
        Log.d(TAG, "Stopping screen monitoring service")
        
        try {
            // Stop background service
            val serviceIntent = Intent(this, ScreenMonitorService::class.java)
            stopService(serviceIntent)
            
            // Cancel WorkManager tasks
            SurvivalMonitorWorker.cancelWork(this)
            
            Log.d(TAG, "Screen monitoring stopped successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop screen monitoring: ${e.message}")
        }
    }

    private fun checkRequiredPermissions(): Boolean {
        return hasUsageStatsPermission() && isBatteryOptimizationDisabled()
    }

    private fun requestRequiredPermissions() {
        if (!hasUsageStatsPermission()) {
            requestUsageStatsPermission()
        } else if (!isBatteryOptimizationDisabled()) {
            requestDisableBatteryOptimization()
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

    private fun setupInactivityReceiver() {
        inactivityReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.thousandemfla.thanks_everyday.elder.INACTIVITY_ALERT") {
                    Log.d(TAG, "Received inactivity alert")
                    // Send to Flutter app
                    val channel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    channel.invokeMethod("onInactivityAlert", null)
                }
            }
        }
        
        val filter = IntentFilter("com.thousandemfla.thanks_everyday.elder.INACTIVITY_ALERT")
        
        // For Android 14+ (API 34+), specify RECEIVER_NOT_EXPORTED since this is an internal broadcast
        if (Build.VERSION.SDK_INT >= 34) {
            registerReceiver(inactivityReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(inactivityReceiver, filter)
        }
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

    override fun onDestroy() {
        super.onDestroy()
        inactivityReceiver?.let {
            unregisterReceiver(it)
        }
    }
}