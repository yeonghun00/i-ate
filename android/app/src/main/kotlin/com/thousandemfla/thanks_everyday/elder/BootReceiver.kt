package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        
        Log.e("BootReceiver", "RECEIVED: ${intent.action}")
        
        // WRITE TO FILE IMMEDIATELY
        try {
            val file = java.io.File(context.filesDir, "boot_debug_log.txt")
            val time = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())
            file.appendText("[$time] ${intent.action} RECEIVED\n")
        } catch (e: Exception) {}
        
        // ONLY HANDLE BOOT_COMPLETED
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.e("BootReceiver", "📍 STARTING 2-MINUTE ALARMS...")
            try {
                val file = java.io.File(context.filesDir, "boot_debug_log.txt")
                val time = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())
                file.appendText("[$time] STARTING 2-MINUTE ALARMS...\n")
                
                // Use the simplified scheduleAlarms method
                AlarmUpdateReceiver.scheduleAlarms(context)
                
                Log.e("BootReceiver", "✅ 2-MINUTE ALARMS SCHEDULED SUCCESSFULLY")
                file.appendText("[$time] 2-MINUTE ALARMS SCHEDULED!\n")
                
            } catch (e: Exception) {
                Log.e("BootReceiver", "❌ ALARM SCHEDULING FAILED: ${e.message}")
                // Write alarm failure to file
                try {
                    val file = java.io.File(context.filesDir, "boot_debug_log.txt")
                    val time = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())
                    file.appendText("[$time] ALARM_ERROR: ${e.message}\n")
                } catch (fileError: Exception) {
                    // Ignore file write errors
                }
            }
            
            Log.e("BootReceiver", "📱 STARTING SCREEN MONITOR SERVICE...")
            try {
                val serviceIntent = Intent(context, ScreenMonitorService::class.java)
                if (android.os.Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                Log.e("BootReceiver", "✅ SCREEN MONITOR SERVICE STARTED")
                
                val file = java.io.File(context.filesDir, "boot_debug_log.txt")
                val time = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())
                file.appendText("[$time] SERVICE STARTED!\n")
                
            } catch (e: Exception) {
                Log.e("BootReceiver", "❌ SERVICE START FAILED: ${e.message}")
                // Write service failure to file
                try {
                    val file = java.io.File(context.filesDir, "boot_debug_log.txt")
                    val time = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())
                    file.appendText("[$time] SERVICE_ERROR: ${e.message}\n")
                } catch (fileError: Exception) {
                    // Ignore file write errors
                }
            }
            
            Log.e("BootReceiver", "🔥 BOOT INITIALIZATION COMPLETE")
        }
    }
}