import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';
import 'package:thanks_everyday/services/overlay_service.dart';
import 'package:thanks_everyday/services/location_service.dart';

/// Enum for different permission types
enum PermissionType {
  location,
  batteryOptimization,
  usageStats,
  overlay,
  notifications,
  autostart, // For MIUI/Xiaomi devices
}

/// Permission status with detailed information
class PermissionInfo {
  final PermissionType type;
  final bool isGranted;
  final bool isRequired;
  final String displayName;
  final String description;
  final String whyNeeded;
  final String actionText;
  
  const PermissionInfo({
    required this.type,
    required this.isGranted,
    required this.isRequired,
    required this.displayName,
    required this.description,
    required this.whyNeeded,
    required this.actionText,
  });
  
  PermissionInfo copyWith({
    bool? isGranted,
  }) {
    return PermissionInfo(
      type: type,
      isGranted: isGranted ?? this.isGranted,
      isRequired: isRequired,
      displayName: displayName,
      description: description,
      whyNeeded: whyNeeded,
      actionText: actionText,
    );
  }
}

/// Overall permission status
class PermissionStatusInfo {
  final List<PermissionInfo> permissions;
  final bool allRequiredGranted;
  final List<PermissionInfo> missing;
  final List<PermissionInfo> optional;
  
  PermissionStatusInfo({
    required this.permissions,
    required this.allRequiredGranted,
    required this.missing,
    required this.optional,
  });
}

/// Comprehensive permission management service for the app
/// Handles checking, requesting, and managing all required permissions
class PermissionManagerService {
  static const String _tag = 'PermissionManagerService';
  
  /// Check all permissions and return comprehensive status
  static Future<PermissionStatusInfo> checkAllPermissions() async {
    try {
      AppLogger.info('Checking all permissions status', tag: _tag);
      
      final permissions = <PermissionInfo>[];
      
      // Location permission (Always Allow)
      final locationPermission = await _checkLocationPermission();
      permissions.add(locationPermission);
      
      // Battery optimization
      final batteryPermission = await _checkBatteryOptimization();
      permissions.add(batteryPermission);
      
      // Usage stats permission
      final usageStatsPermission = await _checkUsageStatsPermission();
      permissions.add(usageStatsPermission);
      
      // Overlay permission
      final overlayPermission = await _checkOverlayPermission();
      permissions.add(overlayPermission);
      
      // Notification permission
      final notificationPermission = await _checkNotificationPermission();
      permissions.add(notificationPermission);
      
      // Calculate status
      final missing = permissions.where((p) => p.isRequired && !p.isGranted).toList();
      final optional = permissions.where((p) => !p.isRequired).toList();
      final allRequiredGranted = missing.isEmpty;
      
      AppLogger.info('Permission check complete - Required granted: $allRequiredGranted, Missing: ${missing.length}', tag: _tag);
      
      return PermissionStatusInfo(
        permissions: permissions,
        allRequiredGranted: allRequiredGranted,
        missing: missing,
        optional: optional,
      );
    } catch (e) {
      AppLogger.error('Error checking permissions: $e', tag: _tag);
      return PermissionStatusInfo(
        permissions: [],
        allRequiredGranted: false,
        missing: [],
        optional: [],
      );
    }
  }
  
  /// Check location permission (Always Allow)
  static Future<PermissionInfo> _checkLocationPermission() async {
    bool isGranted = false;
    
    try {
      final status = await Permission.locationAlways.status;
      isGranted = status.isGranted;
      
      // Also check if location service is enabled
      if (isGranted) {
        final hasBackgroundPermission = await LocationService.hasBackgroundLocationPermission();
        isGranted = hasBackgroundPermission;
      }
    } catch (e) {
      AppLogger.error('Error checking location permission: $e', tag: _tag);
    }
    
    return PermissionInfo(
      type: PermissionType.location,
      isGranted: isGranted,
      isRequired: true,
      displayName: 'GPS 위치 추적',
      description: '가족과 위치를 공유하여 안전을 확인',
      whyNeeded: '위치 정보를 자녀에게 공유하여 안전을 확인할 수 있습니다. "항상 허용" 옵션이 필요합니다.',
      actionText: '위치 권한 설정',
    );
  }
  
  /// Check battery optimization exemption
  static Future<PermissionInfo> _checkBatteryOptimization() async {
    bool isGranted = false;
    
    try {
      isGranted = await ScreenMonitorService.checkBatteryOptimization();
    } catch (e) {
      AppLogger.error('Error checking battery optimization: $e', tag: _tag);
    }
    
    return PermissionInfo(
      type: PermissionType.batteryOptimization,
      isGranted: isGranted,
      isRequired: true,
      displayName: '배터리 최적화 해제',
      description: '앱이 백그라운드에서 안정적으로 실행',
      whyNeeded: '배터리 최적화를 해제하면 앱이 백그라운드에서 지속적으로 모니터링할 수 있습니다.',
      actionText: '배터리 설정 변경',
    );
  }
  
  /// Check usage stats permission
  static Future<PermissionInfo> _checkUsageStatsPermission() async {
    bool isGranted = false;
    
    try {
      isGranted = await ScreenMonitorService.checkUsageStatsPermission();
    } catch (e) {
      AppLogger.error('Error checking usage stats permission: $e', tag: _tag);
    }
    
    return PermissionInfo(
      type: PermissionType.usageStats,
      isGranted: isGranted,
      isRequired: true,
      displayName: '사용 통계 접근',
      description: '휴대폰 사용 패턴을 모니터링',
      whyNeeded: '휴대폰 사용이 없을 때를 감지하여 자녀에게 안전 확인 알림을 보낼 수 있습니다.',
      actionText: '사용 통계 권한 설정',
    );
  }
  
  /// Check overlay permission
  static Future<PermissionInfo> _checkOverlayPermission() async {
    bool isGranted = false;
    
    try {
      isGranted = await OverlayService.hasOverlayPermission();
    } catch (e) {
      AppLogger.error('Error checking overlay permission: $e', tag: _tag);
    }
    
    return PermissionInfo(
      type: PermissionType.overlay,
      isGranted: isGranted,
      isRequired: true,
      displayName: '다른 앱 위에 표시',
      description: '백그라운드에서 생존 신호 표시',
      whyNeeded: '앱이 종료되어도 백그라운드에서 생존 신호를 표시하고 모니터링할 수 있습니다.',
      actionText: '오버레이 권한 허용',
    );
  }
  
  /// Check notification permission
  static Future<PermissionInfo> _checkNotificationPermission() async {
    bool isGranted = false;
    
    try {
      final status = await Permission.notification.status;
      isGranted = status.isGranted;
    } catch (e) {
      AppLogger.error('Error checking notification permission: $e', tag: _tag);
    }
    
    return PermissionInfo(
      type: PermissionType.notifications,
      isGranted: isGranted,
      isRequired: true,
      displayName: '알림 권한',
      description: '중요한 앱 알림을 받기 위해 필요',
      whyNeeded: '앱의 상태 변경이나 중요한 정보를 알림으로 받을 수 있습니다.',
      actionText: '알림 권한 허용',
    );
  }
  
  /// Request specific permission
  static Future<bool> requestPermission(PermissionType type) async {
    AppLogger.info('Requesting permission: $type', tag: _tag);
    
    try {
      switch (type) {
        case PermissionType.location:
          return await _requestLocationPermission();
          
        case PermissionType.batteryOptimization:
          await ScreenMonitorService.requestBatteryOptimizationDisable();
          return await ScreenMonitorService.checkBatteryOptimization();
          
        case PermissionType.usageStats:
          await ScreenMonitorService.requestUsageStatsPermission();
          // Give some time for user to grant permission
          await Future.delayed(const Duration(seconds: 1));
          return await ScreenMonitorService.checkUsageStatsPermission();
          
        case PermissionType.overlay:
          return await OverlayService.requestOverlayPermission();
          
        case PermissionType.notifications:
          final status = await Permission.notification.request();
          return status.isGranted;
          
        case PermissionType.autostart:
          // MIUI specific - handled separately
          return true;
      }
    } catch (e) {
      AppLogger.error('Error requesting permission $type: $e', tag: _tag);
      return false;
    }
  }
  
  /// Request location permission with proper two-step flow
  static Future<bool> _requestLocationPermission() async {
    try {
      AppLogger.info('Starting two-step background location permission flow', tag: _tag);
      
      // Step 1: Request foreground location permissions first
      final foregroundResults = await [
        Permission.locationWhenInUse,
        Permission.location,
      ].request();
      
      final foregroundGranted = 
          foregroundResults[Permission.locationWhenInUse]?.isGranted == true ||
          foregroundResults[Permission.location]?.isGranted == true;
      
      if (!foregroundGranted) {
        AppLogger.warning('Foreground location permission denied', tag: _tag);
        return false;
      }
      
      // Step 2: Request background location permission
      await Future.delayed(const Duration(milliseconds: 500));
      final backgroundStatus = await Permission.locationAlways.request();
      
      final granted = backgroundStatus.isGranted;
      if (granted) {
        AppLogger.info('Background location permission granted successfully', tag: _tag);
      } else {
        AppLogger.warning('Background location permission denied', tag: _tag);
      }
      
      return granted;
    } catch (e) {
      AppLogger.error('Error in location permission flow: $e', tag: _tag);
      return false;
    }
  }
  
  /// Open system settings for specific permission
  static Future<void> openPermissionSettings(PermissionType type) async {
    AppLogger.info('Opening settings for permission: $type', tag: _tag);
    
    try {
      switch (type) {
        case PermissionType.location:
        case PermissionType.notifications:
        case PermissionType.overlay:
          await openAppSettings();
          break;
          
        case PermissionType.usageStats:
          await ScreenMonitorService.requestUsageStatsPermission();
          break;
          
        case PermissionType.batteryOptimization:
          await ScreenMonitorService.requestBatteryOptimizationDisable();
          break;
          
        case PermissionType.autostart:
          await ScreenMonitorService.openAutoStartSettings();
          break;
      }
    } catch (e) {
      AppLogger.error('Error opening permission settings: $e', tag: _tag);
    }
  }
  
  /// Get missing permissions that are required for safety alerts
  static Future<List<PermissionInfo>> getMissingRequiredPermissions() async {
    final status = await checkAllPermissions();
    return status.missing;
  }
  
  /// Check if safety alert feature can work properly
  static Future<bool> canEnableSafetyAlerts() async {
    final status = await checkAllPermissions();
    
    // For safety alerts, we need location, battery optimization, and usage stats
    final requiredForSafety = [
      PermissionType.location,
      PermissionType.batteryOptimization,
      PermissionType.usageStats,
    ];
    
    final missing = status.missing.where((p) => requiredForSafety.contains(p.type));
    return missing.isEmpty;
  }
  
  /// Store user preference for permission guide reminder
  static Future<void> setPermissionGuideShown(bool shown) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('permission_guide_shown', shown);
    } catch (e) {
      AppLogger.error('Error storing permission guide preference: $e', tag: _tag);
    }
  }
  
  /// Check if permission guide should be shown
  static Future<bool> shouldShowPermissionGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('permission_guide_shown') ?? false;
      
      if (shown) {
        return false;
      }
      
      // Check if we have missing permissions
      final status = await checkAllPermissions();
      return status.missing.isNotEmpty;
    } catch (e) {
      AppLogger.error('Error checking permission guide preference: $e', tag: _tag);
      return false;
    }
  }
}