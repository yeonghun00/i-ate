package com.thousandemfla.thanks_everyday.elder

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONObject
import org.json.JSONException
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class SafetyNetManager private constructor(private val context: Context) {
    
    companion object {
        private const val TAG = "SafetyNetManager"
        private const val BACKUP_PREFS = "SafetyNetBackup"
        private const val HEALTH_STATUS_PREFS = "HealthStatus"
        private const val MAX_BACKUPS = 5
        
        @Volatile
        private var INSTANCE: SafetyNetManager? = null
        
        fun getInstance(context: Context): SafetyNetManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: SafetyNetManager(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
    
    private val backupPrefs: SharedPreferences = context.getSharedPreferences(BACKUP_PREFS, Context.MODE_PRIVATE)
    private val healthPrefs: SharedPreferences = context.getSharedPreferences(HEALTH_STATUS_PREFS, Context.MODE_PRIVATE)
    
    data class SystemSnapshot(
        val timestamp: Long,
        val gpsServiceEnabled: Boolean,
        val screenMonitorEnabled: Boolean,
        val alarmsActive: Boolean,
        val permissionsGranted: Map<String, Boolean>,
        val firebaseConnected: Boolean,
        val lastGpsUpdate: Long,
        val lastScreenCheck: Long,
        val settings: Map<String, Any>
    )
    
    fun createSystemSnapshot(): SystemSnapshot {
        return try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val alarmDebugPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            
            val permissionsMap = mapOf(
                "ACCESS_FINE_LOCATION" to checkPermission("android.permission.ACCESS_FINE_LOCATION"),
                "ACCESS_BACKGROUND_LOCATION" to checkPermission("android.permission.ACCESS_BACKGROUND_LOCATION"),
                "WAKE_LOCK" to checkPermission("android.permission.WAKE_LOCK"),
                "RECEIVE_BOOT_COMPLETED" to checkPermission("android.permission.RECEIVE_BOOT_COMPLETED"),
                "FOREGROUND_SERVICE" to checkPermission("android.permission.FOREGROUND_SERVICE"),
                "SYSTEM_ALERT_WINDOW" to checkSystemAlertWindowPermission()
            )
            
            val settingsMap = mutableMapOf<String, Any>()
            flutterPrefs.all.forEach { (key, value) ->
                if (value != null) settingsMap[key] = value
            }
            alarmDebugPrefs.all.forEach { (key, value) ->
                if (value != null) settingsMap["debug_$key"] = value
            }
            
            SystemSnapshot(
                timestamp = System.currentTimeMillis(),
                gpsServiceEnabled = isGpsServiceRunning(),
                screenMonitorEnabled = isScreenMonitorRunning(),
                alarmsActive = areAlarmsActive(),
                permissionsGranted = permissionsMap,
                firebaseConnected = isFirebaseConnected(),
                lastGpsUpdate = getLastGpsUpdateTime(),
                lastScreenCheck = getLastScreenCheckTime(),
                settings = settingsMap
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error creating system snapshot", e)
            createEmergencySnapshot()
        }
    }
    
    fun saveSystemSnapshot(snapshot: SystemSnapshot, label: String = ""): Boolean {
        return try {
            val snapshotJson = JSONObject().apply {
                put("timestamp", snapshot.timestamp)
                put("gpsServiceEnabled", snapshot.gpsServiceEnabled)
                put("screenMonitorEnabled", snapshot.screenMonitorEnabled)
                put("alarmsActive", snapshot.alarmsActive)
                put("firebaseConnected", snapshot.firebaseConnected)
                put("lastGpsUpdate", snapshot.lastGpsUpdate)
                put("lastScreenCheck", snapshot.lastScreenCheck)
                put("label", label)
                
                val permissionsJson = JSONObject()
                snapshot.permissionsGranted.forEach { (key, value) ->
                    permissionsJson.put(key, value)
                }
                put("permissions", permissionsJson)
                
                val settingsJson = JSONObject()
                snapshot.settings.forEach { (key, value) ->
                    when (value) {
                        is String -> settingsJson.put(key, value)
                        is Boolean -> settingsJson.put(key, value)
                        is Int -> settingsJson.put(key, value)
                        is Long -> settingsJson.put(key, value)
                        is Float -> settingsJson.put(key, value)
                    }
                }
                put("settings", settingsJson)
            }
            
            val snapshotKey = "snapshot_${snapshot.timestamp}"
            backupPrefs.edit().putString(snapshotKey, snapshotJson.toString()).apply()
            
            cleanupOldBackups()
            Log.i(TAG, "System snapshot saved: $snapshotKey $label")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error saving system snapshot", e)
            false
        }
    }
    
    fun restoreSystemSnapshot(timestamp: Long): Boolean {
        return try {
            val snapshotKey = "snapshot_$timestamp"
            val snapshotString = backupPrefs.getString(snapshotKey, null) ?: return false
            val snapshotJson = JSONObject(snapshotString)
            
            val settingsJson = snapshotJson.getJSONObject("settings")
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val alarmDebugPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            
            val flutterEditor = flutterPrefs.edit()
            val debugEditor = alarmDebugPrefs.edit()
            
            settingsJson.keys().forEach { key ->
                val value = settingsJson.get(key)
                if (key.startsWith("debug_")) {
                    val debugKey = key.removePrefix("debug_")
                    when (value) {
                        is String -> debugEditor.putString(debugKey, value)
                        is Boolean -> debugEditor.putBoolean(debugKey, value)
                        is Int -> debugEditor.putInt(debugKey, value)
                        is Long -> debugEditor.putLong(debugKey, value)
                    }
                } else {
                    when (value) {
                        is String -> flutterEditor.putString(key, value)
                        is Boolean -> flutterEditor.putBoolean(key, value)
                        is Int -> flutterEditor.putInt(key, value)
                        is Long -> flutterEditor.putLong(key, value)
                    }
                }
            }
            
            flutterEditor.apply()
            debugEditor.apply()
            
            recordRestoreEvent(timestamp)
            Log.i(TAG, "System snapshot restored: $snapshotKey")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error restoring system snapshot", e)
            false
        }
    }
    
    fun getAvailableSnapshots(): List<Pair<Long, String>> {
        return try {
            backupPrefs.all.entries
                .filter { it.key.startsWith("snapshot_") }
                .mapNotNull { entry ->
                    try {
                        val json = JSONObject(entry.value.toString())
                        val timestamp = json.getLong("timestamp")
                        val label = json.optString("label", "")
                        Pair(timestamp, label)
                    } catch (e: Exception) {
                        null
                    }
                }
                .sortedByDescending { it.first }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting available snapshots", e)
            emptyList()
        }
    }
    
    fun createEmergencyBackup(): Boolean {
        val snapshot = createSystemSnapshot()
        return saveSystemSnapshot(snapshot, "EMERGENCY_BACKUP")
    }
    
    private fun createEmergencySnapshot(): SystemSnapshot {
        return SystemSnapshot(
            timestamp = System.currentTimeMillis(),
            gpsServiceEnabled = false,
            screenMonitorEnabled = false,
            alarmsActive = false,
            permissionsGranted = emptyMap(),
            firebaseConnected = false,
            lastGpsUpdate = 0L,
            lastScreenCheck = 0L,
            settings = emptyMap()
        )
    }
    
    private fun checkPermission(permission: String): Boolean {
        return try {
            context.checkSelfPermission(permission) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }
    
    private fun checkSystemAlertWindowPermission(): Boolean {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                android.provider.Settings.canDrawOverlays(context)
            } else {
                true
            }
        } catch (e: Exception) {
            false
        }
    }
    
    private fun isGpsServiceRunning(): Boolean {
        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            manager.getRunningServices(Integer.MAX_VALUE).any { 
                it.service.className.contains("GpsTracking") || it.service.className.contains("LocationService")
            }
        } catch (e: Exception) {
            false
        }
    }
    
    private fun isScreenMonitorRunning(): Boolean {
        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            manager.getRunningServices(Integer.MAX_VALUE).any { 
                it.service.className.contains("ScreenMonitor")
            }
        } catch (e: Exception) {
            false
        }
    }
    
    private fun areAlarmsActive(): Boolean {
        return try {
            val alarmPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            alarmPrefs.getBoolean("gps_alarm_active", false) || 
            alarmPrefs.getBoolean("survival_alarm_active", false)
        } catch (e: Exception) {
            false
        }
    }
    
    private fun isFirebaseConnected(): Boolean {
        return try {
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            flutterPrefs.getBoolean("firebase_connected", false)
        } catch (e: Exception) {
            false
        }
    }
    
    private fun getLastGpsUpdateTime(): Long {
        return try {
            val alarmPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            alarmPrefs.getLong("last_gps_update", 0L)
        } catch (e: Exception) {
            0L
        }
    }
    
    private fun getLastScreenCheckTime(): Long {
        return try {
            val alarmPrefs = context.getSharedPreferences("AlarmDebugPrefs", Context.MODE_PRIVATE)
            alarmPrefs.getLong("last_screen_check", 0L)
        } catch (e: Exception) {
            0L
        }
    }
    
    private fun cleanupOldBackups() {
        try {
            val snapshots = getAvailableSnapshots()
            if (snapshots.size > MAX_BACKUPS) {
                val toDelete = snapshots.drop(MAX_BACKUPS)
                val editor = backupPrefs.edit()
                toDelete.forEach { (timestamp, _) ->
                    editor.remove("snapshot_$timestamp")
                }
                editor.apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up old backups", e)
        }
    }
    
    private fun recordRestoreEvent(timestamp: Long) {
        try {
            healthPrefs.edit()
                .putLong("last_restore_timestamp", timestamp)
                .putLong("restore_time", System.currentTimeMillis())
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error recording restore event", e)
        }
    }
}