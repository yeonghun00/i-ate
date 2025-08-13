package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.os.SystemClock
import android.telephony.TelephonyManager
import android.util.Log
import java.io.File

class NetworkBootDetectorReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "NetworkBootDetectorReceiver"
        private var lastNetworkCheckTime = 0L
        private var consecutiveNetworkTriggers = 0
        
        /**
         * Register dynamic network callback for enhanced boot detection
         * This bypasses some MIUI restrictions by using system-level callbacks
         */
        fun registerDynamicNetworkCallback(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    
                    val networkRequest = NetworkRequest.Builder()
                        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                        .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                        .build()
                    
                    val networkCallback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: android.net.Network) {
                            Log.e(TAG, "🌐 Dynamic network callback: Network available")
                            handleDynamicNetworkChange(context, "NETWORK_AVAILABLE")
                        }
                        
                        override fun onCapabilitiesChanged(network: android.net.Network, networkCapabilities: NetworkCapabilities) {
                            if (networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                                Log.e(TAG, "🌐 Dynamic network callback: Internet capability acquired")
                                handleDynamicNetworkChange(context, "INTERNET_AVAILABLE")
                            }
                        }
                        
                        override fun onLost(network: android.net.Network) {
                            Log.d(TAG, "🌐 Dynamic network callback: Network lost")
                        }
                    }
                    
                    connectivityManager.registerNetworkCallback(networkRequest, networkCallback)
                    Log.e(TAG, "✅ Dynamic network callback registered")
                    logToFile(context, "Dynamic network callback registered")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to register dynamic network callback: ${e.message}")
                logToFile(context, "Failed to register dynamic network callback: ${e.message}")
            }
        }
        
        private fun handleDynamicNetworkChange(context: Context, changeType: String) {
            try {
                Log.e(TAG, "🌐 Dynamic network change: $changeType")
                logToFile(context, "Dynamic network change: $changeType")
                
                val currentTime = System.currentTimeMillis()
                val currentUptime = SystemClock.uptimeMillis()
                
                // Avoid spam - only process if enough time has passed
                if (currentTime - lastNetworkCheckTime < 10000) { // Less than 10 seconds
                    consecutiveNetworkTriggers++
                    Log.d(TAG, "🌐 Consecutive network trigger #$consecutiveNetworkTriggers (within 10s)")
                } else {
                    consecutiveNetworkTriggers = 1
                }
                lastNetworkCheckTime = currentTime
                
                // Network available + low uptime + multiple triggers = likely boot
                if (currentUptime < 10 * 60 * 1000 && consecutiveNetworkTriggers >= 1) {
                    Log.e(TAG, "🔥 DYNAMIC NETWORK + LOW UPTIME = BOOT DETECTION!")
                    logToFile(context, "DYNAMIC NETWORK + LOW UPTIME = BOOT DETECTION!")
                    
                    // Trigger boot detection
                    if (AlternativeBootDetector.isAlternativeDetectionActive(context)) {
                        AlternativeBootDetector.handleNetworkBootDetection(context)
                    } else {
                        Log.e(TAG, "⚠️ Alternative detection not active - activating it now")
                        AlternativeBootDetector.startAlternativeDetection(context)
                        AlternativeBootDetector.handleNetworkBootDetection(context)
                    }
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in dynamic network change: ${e.message}")
                logToFile(context, "Error in dynamic network change: ${e.message}")
            }
        }
        
        private fun logToFile(context: Context, message: String) {
            try {
                val logFile = File(context.filesDir, "boot_debug_log.txt")
                val timestamp = System.currentTimeMillis()
                val readableTime = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(timestamp))
                logFile.appendText("[$readableTime] NET: $message\n", Charsets.UTF_8)
            } catch (e: Exception) {
                // Ignore file errors
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            Log.e(TAG, "🌐🌐🌐 NETWORK RECEIVER TRIGGERED: ${intent.action}")
            logToFile(context, "Network receiver triggered: ${intent.action}")

            when (intent.action) {
                ConnectivityManager.CONNECTIVITY_ACTION -> {
                    Log.e(TAG, "🌐 CONNECTIVITY_ACTION received")
                    handleEnhancedConnectivityChange(context, intent, "CONNECTIVITY_ACTION")
                }
                "android.net.wifi.STATE_CHANGE" -> {
                    Log.e(TAG, "📶 WIFI STATE_CHANGE received")
                    handleEnhancedConnectivityChange(context, intent, "WIFI_STATE_CHANGE")
                }
                "android.net.wifi.WIFI_STATE_CHANGED" -> {
                    Log.e(TAG, "📶 WIFI_STATE_CHANGED received")
                    handleEnhancedConnectivityChange(context, intent, "WIFI_STATE_CHANGED")
                }
                WifiManager.NETWORK_STATE_CHANGED_ACTION -> {
                    Log.e(TAG, "📶 WIFI NETWORK_STATE_CHANGED received")
                    handleEnhancedConnectivityChange(context, intent, "WIFI_NETWORK_STATE_CHANGED")
                }
                "android.net.conn.INET_CONDITION_ACTION" -> {
                    Log.e(TAG, "🌐 INET_CONDITION_ACTION received")
                    handleEnhancedConnectivityChange(context, intent, "INET_CONDITION_ACTION")
                }
                TelephonyManager.ACTION_PHONE_STATE_CHANGED -> {
                    Log.e(TAG, "📱 PHONE_STATE_CHANGED received")
                    handleEnhancedConnectivityChange(context, intent, "PHONE_STATE_CHANGED")
                }
                else -> {
                    Log.e(TAG, "🌐 Other network action: ${intent.action}")
                    handleEnhancedConnectivityChange(context, intent, "OTHER_ACTION")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in network boot detection: ${e.message}")
            logToFile(context, "Error in network boot detection: ${e.message}")
        }
    }

    private fun handleEnhancedConnectivityChange(context: Context, intent: Intent, actionType: String) {
        try {
            val currentTime = System.currentTimeMillis()
            val currentUptime = SystemClock.uptimeMillis()
            
            Log.e(TAG, "🔍 Enhanced connectivity analysis:")
            Log.e(TAG, "  - Action type: $actionType")
            Log.e(TAG, "  - System uptime: ${currentUptime}ms (${currentUptime / 1000}s)")
            Log.e(TAG, "  - Time since boot: ${currentTime}")
            
            logToFile(context, "Enhanced connectivity - type=$actionType, uptime=${currentUptime}ms")
            
            // Get detailed network state
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val networkInfo = connectivityManager.activeNetworkInfo
            val isConnected = networkInfo?.isConnected == true
            val networkType = networkInfo?.typeName ?: "NONE"
            
            Log.e(TAG, "  - Network connected: $isConnected")
            Log.e(TAG, "  - Network type: $networkType")
            logToFile(context, "Network state - connected=$isConnected, type=$networkType")
            
            // Enhanced boot detection logic
            var bootDetectionTriggered = false
            var detectionReason = ""
            
            // Condition 1: Very low uptime + network connectivity
            if (currentUptime < 5 * 60 * 1000 && isConnected) { // Less than 5 minutes
                bootDetectionTriggered = true
                detectionReason = "very_low_uptime_with_network"
                Log.e(TAG, "🔥 CONDITION 1: Very low uptime + network = BOOT DETECTED!")
            }
            // Condition 2: Low uptime + specific network actions
            else if (currentUptime < 10 * 60 * 1000 && (actionType == "CONNECTIVITY_ACTION" || actionType == "WIFI_NETWORK_STATE_CHANGED")) {
                bootDetectionTriggered = true
                detectionReason = "low_uptime_with_network_action"
                Log.e(TAG, "🔥 CONDITION 2: Low uptime + network action = BOOT DETECTED!")
            }
            // Condition 3: WiFi state change with very low uptime
            else if (currentUptime < 8 * 60 * 1000 && actionType.contains("WIFI")) {
                bootDetectionTriggered = true
                detectionReason = "wifi_change_low_uptime"
                Log.e(TAG, "🔥 CONDITION 3: WiFi change + low uptime = BOOT DETECTED!")
            }
            
            if (bootDetectionTriggered) {
                Log.e(TAG, "🚨🚨🚨 ENHANCED NETWORK BOOT DETECTION - Reason: $detectionReason")
                logToFile(context, "ENHANCED NETWORK BOOT DETECTION - Reason: $detectionReason")
                
                // Always trigger boot detection regardless of alternative detection state
                if (AlternativeBootDetector.isAlternativeDetectionActive(context)) {
                    Log.e(TAG, "🔄 Alternative detection active - triggering network boot detection")
                    AlternativeBootDetector.handleNetworkBootDetection(context)
                } else {
                    Log.e(TAG, "⚠️ Alternative detection not active - FORCE ACTIVATING for boot event")
                    logToFile(context, "Force activating alternative detection for boot event")
                    
                    // Force activate alternative detection and then trigger
                    AlternativeBootDetector.startAlternativeDetection(context)
                    AlternativeBootDetector.handleNetworkBootDetection(context)
                }
                
                // Also trigger immediate service restoration
                triggerImmediateServiceRestoration(context, detectionReason)
                
            } else {
                Log.d(TAG, "✅ Network change with normal uptime - no boot detected")
                
                // Still trigger normal alternative detection if active
                if (AlternativeBootDetector.isAlternativeDetectionActive(context)) {
                    Log.d(TAG, "🔄 Alternative detection active - normal network check")
                    AlternativeBootDetector.handleNetworkBootDetection(context)
                } else {
                    Log.d(TAG, "ℹ️ Alternative detection not active - ignoring normal network change")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in enhanced connectivity change: ${e.message}")
            logToFile(context, "Error in enhanced connectivity change: ${e.message}")
            e.printStackTrace()
        }
    }
    
    private fun triggerImmediateServiceRestoration(context: Context, detectionReason: String) {
        try {
            Log.e(TAG, "🚀 IMMEDIATE SERVICE RESTORATION via NetworkReceiver")
            logToFile(context, "IMMEDIATE SERVICE RESTORATION via NetworkReceiver - reason: $detectionReason")
            
            // Check which services should be restored
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val survivalSignalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            val locationTrackingEnabled = prefs.getBoolean("flutter.location_tracking_enabled", false)
            
            if (!survivalSignalEnabled && !locationTrackingEnabled) {
                Log.e(TAG, "❌ No services enabled - skipping network-triggered restoration")
                return
            }
            
            Log.e(TAG, "✅ Services enabled - proceeding with network-triggered restoration")
            logToFile(context, "Network restoration - survival=$survivalSignalEnabled, location=$locationTrackingEnabled")
            
            // Use AlarmUpdateReceiver for reliable restoration
            if (survivalSignalEnabled) {
                Log.e(TAG, "🚀 Network: Starting survival monitoring")
                AlarmUpdateReceiver.enableSurvivalMonitoring(context)
                Log.e(TAG, "✅ Network: Survival monitoring enabled")
            }
            
            if (locationTrackingEnabled) {
                Log.e(TAG, "🌍 Network: Starting location tracking")
                AlarmUpdateReceiver.enableLocationTracking(context)
                Log.e(TAG, "✅ Network: Location tracking enabled")
            }
            
            // Start ScreenMonitorService if survival signal is enabled
            if (survivalSignalEnabled) {
                try {
                    Log.e(TAG, "📱 Network: Starting ScreenMonitorService")
                    ScreenMonitorService.startService(context)
                    Log.e(TAG, "✅ Network: ScreenMonitorService started")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Network: ScreenMonitorService failed: ${e.message}")
                    logToFile(context, "Network: ScreenMonitorService failed: ${e.message}")
                }
            }
            
            Log.e(TAG, "🎉 NETWORK-TRIGGERED RESTORATION COMPLETE!")
            logToFile(context, "NETWORK-TRIGGERED RESTORATION COMPLETE!")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Network service restoration failed: ${e.message}")
            logToFile(context, "Network service restoration failed: ${e.message}")
        }
    }
    
    private fun logToFile(context: Context, message: String) {
        try {
            val logFile = File(context.filesDir, "boot_debug_log.txt")
            val timestamp = System.currentTimeMillis()
            val readableTime = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(timestamp))
            logFile.appendText("[$readableTime] NET: $message\n", Charsets.UTF_8)
        } catch (e: Exception) {
            // Ignore file errors
        }
    }
}