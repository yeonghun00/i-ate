package com.thousandemfla.thanks_everyday.elder

import android.content.Context
import android.util.Log

/**
 * Helper to check if current time is within configured sleep period
 * Used by multiple services to skip survival signal updates during sleep
 */
object SleepTimeHelper {
    private const val TAG = "SleepTimeHelper"
    
    /**
     * Check if current time falls within sleep period
     * Returns false if sleep exclusion is disabled
     */
    fun isCurrentlySleepTime(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            // Check if sleep exclusion is enabled
            val sleepEnabled = prefs.getBoolean("flutter.sleep_exclusion_enabled", false)
            Log.d(TAG, "📖 Reading from SharedPreferences: flutter.sleep_exclusion_enabled = $sleepEnabled")

            if (!sleepEnabled) {
                Log.d(TAG, "😴 Sleep exclusion is DISABLED - allowing survival signal updates")
                return false
            }

            Log.d(TAG, "✅ Sleep exclusion is ENABLED - checking if currently in sleep period")

            // Get sleep time settings (Flutter stores as Long, need to convert to Int)
            val sleepStartHour = prefs.getLong("flutter.sleep_start_hour", 22).toInt()
            val sleepStartMinute = prefs.getLong("flutter.sleep_start_minute", 0).toInt()
            val sleepEndHour = prefs.getLong("flutter.sleep_end_hour", 6).toInt()
            val sleepEndMinute = prefs.getLong("flutter.sleep_end_minute", 0).toInt()
            
            // Get active days (default to all days if not set)
            val activeDaysString = prefs.getString("flutter.sleep_active_days", "1,2,3,4,5,6,7")
            val activeDays = activeDaysString?.split(",")?.mapNotNull { it.trim().toIntOrNull() } ?: listOf(1,2,3,4,5,6,7)
            
            val now = java.util.Calendar.getInstance()
            val currentHour = now.get(java.util.Calendar.HOUR_OF_DAY)
            val currentMinute = now.get(java.util.Calendar.MINUTE)
            val currentWeekday = now.get(java.util.Calendar.DAY_OF_WEEK)
            
            // Convert to Monday=1, Sunday=7 format (Calendar uses Sunday=1)
            val mondayBasedWeekday = if (currentWeekday == java.util.Calendar.SUNDAY) 7 else currentWeekday - 1
            
            // Check if today is an active day
            if (!activeDays.contains(mondayBasedWeekday)) {
                Log.d(TAG, "Today ($mondayBasedWeekday) is not an active sleep day")
                return false
            }
            
            val currentTimeMinutes = currentHour * 60 + currentMinute
            val sleepStartMinutes = sleepStartHour * 60 + sleepStartMinute
            val sleepEndMinutes = sleepEndHour * 60 + sleepEndMinute
            
            val isSleepTime = if (sleepStartMinutes > sleepEndMinutes) {
                // Overnight period (e.g., 22:00 - 06:00)
                // Use < for end time so 06:00 exactly is considered awake
                currentTimeMinutes >= sleepStartMinutes || currentTimeMinutes < sleepEndMinutes
            } else {
                // Same-day period (e.g., 14:00 - 16:00)
                currentTimeMinutes >= sleepStartMinutes && currentTimeMinutes < sleepEndMinutes
            }

            val currentTimeStr = String.format("%02d:%02d", currentHour, currentMinute)
            val sleepPeriodStr = "${String.format("%02d:%02d", sleepStartHour, sleepStartMinute)}-${String.format("%02d:%02d", sleepEndHour, sleepEndMinute)}"

            if (isSleepTime) {
                Log.d(TAG, "😴 Currently IN sleep period: $currentTimeStr is within $sleepPeriodStr -> SKIPPING survival signal")
            } else {
                Log.d(TAG, "🌞 Currently OUTSIDE sleep period: $currentTimeStr is outside $sleepPeriodStr -> UPDATING survival signal")
            }

            return isSleepTime
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking sleep time: ${e.message}")
            return false
        }
    }
}
