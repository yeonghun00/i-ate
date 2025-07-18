package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Boot receiver triggered: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                
                // Check if survival signal is enabled
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val isEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
                
                if (isEnabled) {
                    Log.d(TAG, "Starting screen monitor service after boot")
                    val serviceIntent = Intent(context, ScreenMonitorService::class.java)
                    
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start service: ${e.message}")
                    }
                } else {
                    Log.d(TAG, "Survival signal disabled, not starting service")
                }
            }
        }
    }
}