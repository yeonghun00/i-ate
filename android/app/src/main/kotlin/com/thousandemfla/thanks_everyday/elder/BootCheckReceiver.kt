package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootCheckReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootCheckReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            Log.d(TAG, "⏰ Periodic boot check alarm triggered")

            // Only run if alternative detection is active
            if (AlternativeBootDetector.isAlternativeDetectionActive(context)) {
                Log.d(TAG, "🔄 Checking for missed boot events...")
                
                val bootDetected = AlternativeBootDetector.checkForMissedBoot(context)
                if (bootDetected) {
                    Log.e(TAG, "🚨 Boot check detected missed boot event!")
                } else {
                    Log.d(TAG, "✅ No missed boot events detected")
                }
                
                // Reschedule next check
                scheduleNextCheck(context)
                
            } else {
                Log.d(TAG, "ℹ️ Alternative detection not active - stopping periodic checks")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in periodic boot check: ${e.message}")
        }
    }

    private fun scheduleNextCheck(context: Context) {
        try {
            // The AlternativeBootDetector will reschedule automatically
            // This is just for logging
            Log.d(TAG, "📅 Scheduling next boot check in 30 minutes")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error scheduling next boot check: ${e.message}")
        }
    }
}