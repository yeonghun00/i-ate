package com.thousandemfla.thanks_everyday.services

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log

/**
 * Service to read battery information
 */
object BatteryService {
    private const val TAG = "BatteryService"

    /**
     * Get current battery information
     * Returns a map with battery data
     */
    fun getBatteryInfo(context: Context): Map<String, Any> {
        try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

            // Get battery level (0-100)
            val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

            // Get charging status
            val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
                context.registerReceiver(null, filter)
            }

            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                           status == BatteryManager.BATTERY_STATUS_FULL

            // Get charging method (USB, AC, Wireless)
            val chargePlug = batteryStatus?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
            val chargingMethod = when (chargePlug) {
                BatteryManager.BATTERY_PLUGGED_USB -> "USB"
                BatteryManager.BATTERY_PLUGGED_AC -> "AC"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
                else -> "Not charging"
            }

            // Get battery health
            val health = batteryStatus?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) ?: -1
            val batteryHealth = when (health) {
                BatteryManager.BATTERY_HEALTH_GOOD -> "GOOD"
                BatteryManager.BATTERY_HEALTH_OVERHEAT -> "OVERHEAT"
                BatteryManager.BATTERY_HEALTH_DEAD -> "DEAD"
                BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "OVER_VOLTAGE"
                BatteryManager.BATTERY_HEALTH_COLD -> "COLD"
                else -> "UNKNOWN"
            }

            // Get battery temperature (in tenths of degrees Celsius)
            val temperature = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
            val temperatureCelsius = if (temperature > 0) temperature / 10.0 else null

            Log.d(TAG, "Battery: ${batteryLevel}%, Charging: $isCharging, Health: $batteryHealth")

            return mapOf(
                "batteryLevel" to batteryLevel,
                "isCharging" to isCharging,
                "chargingMethod" to chargingMethod,
                "batteryHealth" to batteryHealth,
                "batteryTemperature" to (temperatureCelsius ?: -1.0),
                "timestamp" to System.currentTimeMillis()
            )

        } catch (e: Exception) {
            Log.e(TAG, "Failed to get battery info: ${e.message}")
            return mapOf(
                "batteryLevel" to -1,
                "isCharging" to false,
                "batteryHealth" to "UNKNOWN",
                "error" to (e.message ?: "Unknown error")
            )
        }
    }

    /**
     * Get battery emoji based on percentage and charging status
     */
    fun getBatteryEmoji(batteryLevel: Int, isCharging: Boolean): String {
        return when {
            isCharging -> "🔌"
            batteryLevel >= 50 -> "🔋"
            batteryLevel >= 20 -> "🪫"
            else -> "🔴"
        }
    }
}
