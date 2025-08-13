package com.thousandemfla.thanks_everyday.elder

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.util.Log
import java.io.File

object MiuiPermissionHelper {
    private const val TAG = "MiuiPermissionHelper"
    private const val MIUI_PREFS = "MiuiPermissionPrefs"
    
    // CRITICAL FIX: Enhanced permission validation for post-reboot state
    data class PostRebootPermissionStatus(
        val allPermissionsValid: Boolean,
        val locationPermissionsRevoked: Boolean,
        val backgroundLocationRevoked: Boolean,
        val batteryOptimizationEnabled: Boolean,
        val notificationPermissionRevoked: Boolean,
        val autoStartPermissionLost: Boolean,
        val overlayPermissionRevoked: Boolean,
        val exactAlarmPermissionRevoked: Boolean,
        val issuesFound: List<String>,
        val criticalIssuesFound: List<String>
    )
    
    data class MiuiGuidanceInfo(
        val isMiuiDevice: Boolean,
        val needsAutoStartPermission: Boolean,
        val hasAutoStartPermission: Boolean,
        val instructionsTitle: String,
        val instructionsSteps: List<String>,
        val settingsIntents: List<String>,
        val troubleshootingTips: List<String>
    )
    
    fun isMiuiDevice(): Boolean {
        return try {
            // SAFE Method: Check manufacturer/brand only (no system property access)
            val manufacturer = Build.MANUFACTURER.lowercase()
            val brand = Build.BRAND.lowercase()
            val isMiuiBrand = manufacturer.contains("xiaomi") || brand.contains("xiaomi") || 
                             manufacturer.contains("redmi") || brand.contains("redmi")
            
            Log.d(TAG, "MIUI device detection - Manufacturer: $manufacturer, Brand: $brand, Is MIUI: $isMiuiBrand")
            isMiuiBrand
        } catch (e: Exception) {
            Log.w(TAG, "Error detecting MIUI device: ${e.message}")
            // Fallback to basic manufacturer check
            val manufacturer = Build.MANUFACTURER.lowercase()
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi")
        }
    }
    
    
    fun checkAutoStartPermission(context: Context): Boolean {
        if (!isMiuiDevice()) {
            return true // Not MIUI, assume permission granted
        }
        
        return try {
            // Check if BootReceiver has successfully triggered before
            val bootLogFile = File(context.filesDir, "boot_debug_log.txt")
            val hasBootLog = bootLogFile.exists() && bootLogFile.length() > 0
            
            if (hasBootLog) {
                Log.d(TAG, "✅ Auto-start permission appears to be working (boot log exists)")
                recordAutoStartSuccess(context)
                return true
            }
            
            // Check SharedPreferences for recorded success
            val prefs = context.getSharedPreferences(MIUI_PREFS, Context.MODE_PRIVATE)
            val hasRecordedSuccess = prefs.getBoolean("auto_start_working", false)
            
            if (hasRecordedSuccess) {
                Log.d(TAG, "✅ Auto-start permission previously confirmed working")
                return true
            }
            
            // Check if user has been guided before
            val userGuidedBefore = prefs.getBoolean("user_guided_auto_start", false)
            val lastCheckTime = prefs.getLong("last_auto_start_check", 0)
            val currentTime = System.currentTimeMillis()
            
            if (!userGuidedBefore || (currentTime - lastCheckTime) > 24 * 60 * 60 * 1000) {
                Log.w(TAG, "⚠️ MIUI device without confirmed auto-start permission")
                prefs.edit().putLong("last_auto_start_check", currentTime).apply()
                return false
            }
            
            // Assume working if guided recently
            true
            
        } catch (e: Exception) {
            Log.e(TAG, "Error checking auto-start permission: ${e.message}")
            false
        }
    }
    
    fun recordAutoStartSuccess(context: Context) {
        try {
            val prefs = context.getSharedPreferences(MIUI_PREFS, Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean("auto_start_working", true)
                .putLong("last_success_time", System.currentTimeMillis())
                .apply()
            
            Log.d(TAG, "✅ Recorded auto-start permission success")
        } catch (e: Exception) {
            Log.e(TAG, "Error recording auto-start success: ${e.message}")
        }
    }
    
    fun markUserGuided(context: Context) {
        try {
            val prefs = context.getSharedPreferences(MIUI_PREFS, Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean("user_guided_auto_start", true)
                .putLong("user_guided_time", System.currentTimeMillis())
                .apply()
            
            Log.d(TAG, "✅ Marked user as guided for auto-start")
        } catch (e: Exception) {
            Log.e(TAG, "Error marking user guided: ${e.message}")
        }
    }
    
    fun getMiuiGuidanceInfo(context: Context): MiuiGuidanceInfo {
        val isMiui = isMiuiDevice()
        val hasPermission = checkAutoStartPermission(context)
        
        return MiuiGuidanceInfo(
            isMiuiDevice = isMiui,
            needsAutoStartPermission = isMiui && !hasPermission,
            hasAutoStartPermission = hasPermission,
            instructionsTitle = "MIUI 자동 시작 권한 설정",
            instructionsSteps = listOf(
                "1. '보안' 앱을 열거나 설정 → 앱 관리로 이동",
                "2. '권한' 또는 '앱 권한'을 선택",
                "3. '자동 시작' 또는 '자동 시작 관리'를 찾아 선택",
                "4. '식사하셨어요?' 앱을 찾아서 토글을 켜기(ON)",
                "5. 배터리 설정에서도 '제한 없음'으로 설정",
                "6. 기기를 재부팅하여 테스트"
            ),
            settingsIntents = getAutoStartSettingsIntents(context),
            troubleshootingTips = listOf(
                "• MIUI 버전에 따라 메뉴 이름이 다를 수 있습니다",
                "• '보안 센터' → '앱 관리' → '권한'에서도 찾을 수 있습니다",
                "• 앱을 최근 앱 목록에서 스와이프로 제거하지 마세요",
                "• 설정 후 반드시 재부팅이 필요합니다"
            )
        )
    }
    
    private fun getAutoStartSettingsIntents(context: Context): List<String> {
        val intents = mutableListOf<String>()
        
        // MIUI auto-start settings intents (multiple fallbacks)
        intents.addAll(listOf(
            "miui.intent.action.APP_PERM_EDITOR",
            "miui.intent.action.POWER_HIDE_MODE_APP_LIST", 
            "android.settings.APPLICATION_DETAILS_SETTINGS",
            "android.intent.action.MANAGE_APP_PERMISSIONS",
            "com.miui.securitycenter/.permission.PermissionUtils",
            "com.miui.powerkeeper/.ui.HiddenAppsConfigActivity",
            "com.xiaomi.market/.ui.AppPermissionActivity"
        ))
        
        return intents
    }
    
    fun openAutoStartSettings(context: Context): Boolean {
        val packageName = context.packageName
        val intents = getAutoStartSettingsIntents(context)
        
        for (intentAction in intents) {
            try {
                val intent = when {
                    intentAction.contains("APPLICATION_DETAILS_SETTINGS") -> {
                        Intent(intentAction).apply {
                            data = Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    }
                    intentAction.contains(".") -> {
                        // Component name intent
                        Intent().apply {
                            component = android.content.ComponentName.unflattenFromString(intentAction)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            putExtra("package_name", packageName)
                        }
                    }
                    else -> {
                        // Action intent
                        Intent(intentAction).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            putExtra("package_name", packageName)
                        }
                    }
                }
                
                context.startActivity(intent)
                Log.d(TAG, "✅ Successfully opened settings with intent: $intentAction")
                return true
                
            } catch (e: Exception) {
                Log.d(TAG, "Failed to open settings with intent $intentAction: ${e.message}")
            }
        }
        
        // Fallback to general app settings
        try {
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Log.d(TAG, "✅ Opened fallback app settings")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "❌ All settings intents failed: ${e.message}")
            return false
        }
    }
    
    // CRITICAL FIX: Comprehensive post-reboot permission validation for MIUI
    fun validatePostRebootPermissions(context: Context): PostRebootPermissionStatus {
        val issuesFound = mutableListOf<String>()
        val criticalIssuesFound = mutableListOf<String>()
        
        try {
            Log.d(TAG, "🔍 MIUI Post-Reboot Permission Validation Starting...")
            
            // 1. Location permissions check
            val fineLocationGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_FINE_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            
            val coarseLocationGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_COARSE_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            
            val backgroundLocationGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                androidx.core.content.ContextCompat.checkSelfPermission(
                    context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
            
            val locationPermissionsRevoked = !fineLocationGranted || !coarseLocationGranted
            val backgroundLocationRevoked = !backgroundLocationGranted
            
            if (locationPermissionsRevoked) {
                val issue = "Location permissions revoked after reboot (Fine: $fineLocationGranted, Coarse: $coarseLocationGranted)"
                criticalIssuesFound.add(issue)
                Log.e(TAG, "❌ CRITICAL: $issue")
            }
            
            if (backgroundLocationRevoked && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val issue = "Background location permission revoked after reboot"
                criticalIssuesFound.add(issue)
                Log.e(TAG, "❌ CRITICAL: $issue")
            }
            
            // 2. Battery optimization check
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
            val batteryOptimizationEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && powerManager != null) {
                !powerManager.isIgnoringBatteryOptimizations(context.packageName)
            } else {
                false
            }
            
            if (batteryOptimizationEnabled) {
                val issue = "Battery optimization re-enabled after reboot"
                criticalIssuesFound.add(issue)
                Log.e(TAG, "❌ CRITICAL: $issue")
            }
            
            // 3. Notification permission check (Android 13+)
            val notificationPermissionRevoked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                androidx.core.content.ContextCompat.checkSelfPermission(
                    context, android.Manifest.permission.POST_NOTIFICATIONS
                ) != android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                false
            }
            
            if (notificationPermissionRevoked) {
                val issue = "Notification permission revoked after reboot (Android 13+)"
                criticalIssuesFound.add(issue)
                Log.e(TAG, "❌ CRITICAL: $issue")
            }
            
            // 4. Overlay permission check
            val overlayPermissionRevoked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                !android.provider.Settings.canDrawOverlays(context)
            } else {
                false
            }
            
            if (overlayPermissionRevoked) {
                val issue = "Overlay permission revoked after reboot"
                issuesFound.add(issue)
                Log.w(TAG, "⚠️ $issue")
            }
            
            // 5. Exact alarm permission check (Android 12+)
            val exactAlarmPermissionRevoked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? android.app.AlarmManager
                alarmManager?.canScheduleExactAlarms() != true
            } else {
                false
            }
            
            if (exactAlarmPermissionRevoked) {
                val issue = "Exact alarm permission revoked after reboot (Android 12+)"
                criticalIssuesFound.add(issue)
                Log.e(TAG, "❌ CRITICAL: $issue")
            }
            
            // 6. Auto-start permission check
            val autoStartPermissionLost = isMiuiDevice() && !checkAutoStartPermission(context)
            
            if (autoStartPermissionLost) {
                val issue = "MIUI auto-start permission appears lost after reboot"
                criticalIssuesFound.add(issue)
                Log.e(TAG, "❌ CRITICAL: $issue")
            }
            
            val allPermissionsValid = criticalIssuesFound.isEmpty() && issuesFound.isEmpty()
            
            Log.d(TAG, "🔍 MIUI Permission Validation Results:")
            Log.d(TAG, "  - All permissions valid: $allPermissionsValid")
            Log.d(TAG, "  - Critical issues: ${criticalIssuesFound.size}")
            Log.d(TAG, "  - Minor issues: ${issuesFound.size}")
            
            return PostRebootPermissionStatus(
                allPermissionsValid = allPermissionsValid,
                locationPermissionsRevoked = locationPermissionsRevoked,
                backgroundLocationRevoked = backgroundLocationRevoked,
                batteryOptimizationEnabled = batteryOptimizationEnabled,
                notificationPermissionRevoked = notificationPermissionRevoked,
                autoStartPermissionLost = autoStartPermissionLost,
                overlayPermissionRevoked = overlayPermissionRevoked,
                exactAlarmPermissionRevoked = exactAlarmPermissionRevoked,
                issuesFound = issuesFound,
                criticalIssuesFound = criticalIssuesFound
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during post-reboot permission validation: ${e.message}")
            criticalIssuesFound.add("Permission validation failed: ${e.message}")
            
            return PostRebootPermissionStatus(
                allPermissionsValid = false,
                locationPermissionsRevoked = true,
                backgroundLocationRevoked = true,
                batteryOptimizationEnabled = true,
                notificationPermissionRevoked = true,
                autoStartPermissionLost = true,
                overlayPermissionRevoked = true,
                exactAlarmPermissionRevoked = true,
                issuesFound = listOf("Permission check failed"),
                criticalIssuesFound = criticalIssuesFound
            )
        }
    }
    
    // CRITICAL FIX: Store permission state before reboot for comparison
    fun storePermissionStateBeforeReboot(context: Context) {
        try {
            val prefs = context.getSharedPreferences(MIUI_PREFS, Context.MODE_PRIVATE)
            
            val fineLocationGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_FINE_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            
            val backgroundLocationGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                androidx.core.content.ContextCompat.checkSelfPermission(
                    context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
            
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
            val batteryOptimizationDisabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && powerManager != null) {
                powerManager.isIgnoringBatteryOptimizations(context.packageName)
            } else {
                true
            }
            
            prefs.edit()
                .putBoolean("pre_reboot_fine_location", fineLocationGranted)
                .putBoolean("pre_reboot_background_location", backgroundLocationGranted)
                .putBoolean("pre_reboot_battery_optimization_disabled", batteryOptimizationDisabled)
                .putLong("permission_state_stored_time", System.currentTimeMillis())
                .apply()
            
            Log.d(TAG, "✅ Permission state stored before reboot")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to store permission state: ${e.message}")
        }
    }
    
    fun logMiuiStatus(context: Context) {
        Log.d(TAG, "=== MIUI STATUS DEBUG ===")
        Log.d(TAG, "Device: ${Build.MANUFACTURER} ${Build.MODEL}")
        Log.d(TAG, "Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        Log.d(TAG, "MIUI detected: ${isMiuiDevice()}")
        Log.d(TAG, "Auto-start permission: ${checkAutoStartPermission(context)}")
        
        val bootLogFile = File(context.filesDir, "boot_debug_log.txt")
        Log.d(TAG, "Boot log exists: ${bootLogFile.exists()}")
        Log.d(TAG, "Boot log size: ${if (bootLogFile.exists()) bootLogFile.length() else 0} bytes")
        
        val prefs = context.getSharedPreferences(MIUI_PREFS, Context.MODE_PRIVATE)
        Log.d(TAG, "Recorded success: ${prefs.getBoolean("auto_start_working", false)}")
        Log.d(TAG, "User guided: ${prefs.getBoolean("user_guided_auto_start", false)}")
        
        // Add post-reboot permission validation
        val permissionStatus = validatePostRebootPermissions(context)
        Log.d(TAG, "Post-reboot permissions valid: ${permissionStatus.allPermissionsValid}")
        Log.d(TAG, "Critical permission issues: ${permissionStatus.criticalIssuesFound.size}")
        
        Log.d(TAG, "========================")
    }
}