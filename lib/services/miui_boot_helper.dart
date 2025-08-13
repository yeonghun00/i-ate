import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

/// MIUI Boot Helper - Flutter integration for MIUI boot detection and user guidance
/// 
/// This service handles the critical MIUI auto-start permission issue that prevents
/// elder safety monitoring from resuming after device reboot.
class MiuiBootHelper {
  static const String _tag = 'MiuiBootHelper';
  static const MethodChannel _channel = MethodChannel('elder_monitoring');
  
  /// Check if device is MIUI and needs special handling
  static Future<bool> isMiuiDevice() async {
    try {
      final result = await _channel.invokeMethod('isMiuiDevice');
      return result == true;
    } catch (e) {
      print('$_tag Error checking MIUI device: $e');
      // Fallback: check manufacturer
      return Platform.isAndroid && 
        (Platform.operatingSystemVersion.toLowerCase().contains('xiaomi') ||
         Platform.operatingSystemVersion.toLowerCase().contains('miui'));
    }
  }
  
  /// Check if boot receiver is working properly
  static Future<BootReceiverStatus> checkBootReceiverStatus() async {
    try {
      final result = await _channel.invokeMethod('checkBootReceiverStatus');
      return BootReceiverStatus.fromString(result ?? 'unknown');
    } catch (e) {
      print('$_tag Error checking boot receiver status: $e');
      return BootReceiverStatus.unknown;
    }
  }
  
  /// Check for missed boot and restore services if needed
  static Future<bool> checkForMissedBoot() async {
    try {
      final result = await _channel.invokeMethod('checkForMissedBoot');
      return result == true;
    } catch (e) {
      print('$_tag Error checking for missed boot: $e');
      return false;
    }
  }
  
  /// Open MIUI auto-start settings
  static Future<bool> openMiuiAutoStartSettings() async {
    try {
      final result = await _channel.invokeMethod('openMiuiAutoStartSettings');
      return result == true;
    } catch (e) {
      print('$_tag Error opening MIUI settings: $e');
      return false;
    }
  }
  
  /// Open battery optimization settings
  static Future<bool> openBatteryOptimizationSettings() async {
    try {
      final result = await _channel.invokeMethod('openBatteryOptimizationSettings');
      return result == true;
    } catch (e) {
      print('$_tag Error opening battery settings: $e');
      return false;
    }
  }
  
  /// Check if user needs to see MIUI guidance
  static Future<bool> shouldShowMiuiGuidance() async {
    if (!await isMiuiDevice()) return false;
    
    try {
      final result = await _channel.invokeMethod('shouldShowMiuiGuidance');
      return result == true;
    } catch (e) {
      print('$_tag Error checking guidance requirement: $e');
      
      // Fallback: check SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final guidanceShown = prefs.getBool('miui_guidance_shown') ?? false;
      final bootStatus = await checkBootReceiverStatus();
      
      return !guidanceShown || bootStatus != BootReceiverStatus.working;
    }
  }
  
  /// Mark MIUI guidance as shown
  static Future<void> markMiuiGuidanceShown() async {
    try {
      await _channel.invokeMethod('markMiuiGuidanceShown');
      
      // Also store in Flutter preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('miui_guidance_shown', true);
      await prefs.setInt('miui_guidance_shown_time', DateTime.now().millisecondsSinceEpoch);
      
    } catch (e) {
      print('$_tag Error marking guidance shown: $e');
    }
  }
  
  /// Check if app needs post-boot activation (Android 12+ foreground service restrictions)
  static Future<bool> needsPostBootActivation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('needs_post_boot_activation') ?? false;
    } catch (e) {
      print('$_tag Error checking post-boot activation: $e');
      return false;
    }
  }
  
  /// Clear post-boot activation flag
  static Future<void> clearPostBootActivationFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('needs_post_boot_activation');
    } catch (e) {
      print('$_tag Error clearing post-boot flag: $e');
    }
  }
  
  /// Show comprehensive MIUI setup dialog
  static Future<void> showMiuiSetupDialog(BuildContext context) async {
    if (!await isMiuiDevice()) return;
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return MiuiSetupDialog();
      },
    );
  }
  
  /// Show post-reboot activation dialog
  static Future<void> showPostBootActivationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return PostBootActivationDialog();
      },
    );
  }
  
  /// Initialize MIUI boot detection on app start
  static Future<void> initializeOnAppStart() async {
    try {
      print('$_tag Initializing MIUI boot detection...');
      
      // Check for missed boot
      final missedBoot = await checkForMissedBoot();
      if (missedBoot) {
        print('$_tag ⚠️ Missed boot detected - services restored automatically');
      }
      
      // Start alternative boot detection systems
      await _channel.invokeMethod('startAlternativeBootDetection');
      print('$_tag ✅ Alternative boot detection initialized');
      
    } catch (e) {
      print('$_tag Error initializing: $e');
    }
  }
}

/// Boot receiver status enumeration
enum BootReceiverStatus {
  working,
  neverWorked,
  blockedRecentBoot,
  unknown;
  
  static BootReceiverStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'working': return BootReceiverStatus.working;
      case 'never_worked': return BootReceiverStatus.neverWorked;
      case 'blocked_recent_boot': return BootReceiverStatus.blockedRecentBoot;
      default: return BootReceiverStatus.unknown;
    }
  }
}

/// MIUI Setup Dialog Widget
class MiuiSetupDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: Colors.orange, size: 28),
          SizedBox(width: 8),
          Text('🚨 MIUI 설정 필요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '샤오미 기기는 기본적으로 앱 재부팅 후 자동 시작을 차단합니다.',
              style: TextStyle(fontWeight: FontWeight.w500, color: Colors.red[700]),
            ),
            SizedBox(height: 16),
            Text('어르신 안전 모니터링이 재부팅 후에도 작동하려면:', style: TextStyle(fontWeight: FontWeight.w500)),
            SizedBox(height: 12),
            _buildStepItem('1. 보안 앱 → 앱 관리 → 자동 시작', '• "식사하셨어요?" 앱을 찾아 활성화'),
            SizedBox(height: 8),
            _buildStepItem('2. 배터리 설정 → 배터리 절약', '• "식사하셨어요?"를 "제한 없음"으로 설정'),
            SizedBox(height: 8),
            _buildStepItem('3. 최근 앱에서 절대 스와이프 금지', '• 앱을 끄면 모든 모니터링이 중단됩니다'),
            SizedBox(height: 8),
            _buildStepItem('4. 설정 변경 후', '• 기기를 한 번 재시작\n• 재시작 후 이 앱을 실행\n• 모니터링 작동 확인'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⚠️ 이 설정 없이는 GPS 추적과 생존 모니터링이 재부팅 후 작동하지 않습니다!',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('나중에'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await MiuiBootHelper.openMiuiAutoStartSettings();
            await MiuiBootHelper.markMiuiGuidanceShown();
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: Text('설정 열기', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
  
  Widget _buildStepItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[800])),
        Padding(
          padding: EdgeInsets.only(left: 12, top: 4),
          child: Text(description, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        ),
      ],
    );
  }
}

/// Post-Boot Activation Dialog Widget
class PostBootActivationDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.restart_alt, color: Colors.blue, size: 28),
          SizedBox(width: 8),
          Text('📱 재부팅 감지됨', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '기기가 재부팅되었습니다.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 12),
          Text('Android 12+ 보안 정책으로 인해 일부 모니터링 서비스는 사용자가 앱을 실행해야 완전히 활성화됩니다.'),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border.all(color: Colors.green[200]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '✅ 앱을 실행하시면 모든 안전 모니터링 서비스가 자동으로 복원됩니다.',
              style: TextStyle(fontWeight: FontWeight.w500, color: Colors.green[800]),
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await MiuiBootHelper.clearPostBootActivationFlag();
            
            // Trigger service restoration
            try {
              const MethodChannel('elder_monitoring').invokeMethod('restoreServicesAfterBoot');
            } catch (e) {
              print('Error restoring services: $e');
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: Text('서비스 활성화', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}