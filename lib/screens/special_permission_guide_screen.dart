import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';
import 'package:thanks_everyday/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';

class SpecialPermissionGuideScreen extends StatefulWidget {
  final VoidCallback onPermissionsComplete;
  
  const SpecialPermissionGuideScreen({
    super.key,
    required this.onPermissionsComplete,
  });

  @override
  State<SpecialPermissionGuideScreen> createState() => _SpecialPermissionGuideScreenState();
}

class _SpecialPermissionGuideScreenState extends State<SpecialPermissionGuideScreen> with WidgetsBindingObserver {
  int _currentStep = 0;
  bool _isChecking = false;
  bool _backgroundLocationGranted = false;
  bool _overlayGranted = false;
  bool _hasUsagePermission = false;
  bool _hasBatteryPermission = false;
  bool _isMiuiDevice = false;
  bool _miuiAutostartPermissionAcknowledged = false;
  
  // Previous permission states to prevent unnecessary UI updates
  bool _previousBackgroundLocationGranted = false;
  bool _previousOverlayGranted = false;
  bool _previousHasUsagePermission = false;
  bool _previousHasBatteryPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectMiuiDevice();
    _checkPermissions();
  }
  
  void _detectMiuiDevice() async {
    // Detect if this is a MIUI device (Xiaomi/Redmi)
    if (Platform.isAndroid) {
      _isMiuiDevice = await _isXiaomiDevice();
      print('MIUI device detected: $_isMiuiDevice');
      setState(() {}); // Update UI after detection
    }
  }
  
  Future<bool> _isXiaomiDevice() async {
    try {
      const platform = MethodChannel('com.thousandemfla.thanks_everyday/miui');
      final bool isMiui = await platform.invokeMethod('isMiuiDevice');
      return isMiui;
    } catch (e) {
      print('Error detecting MIUI device: $e');
      return false; // Default to false if detection fails
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user comes back from settings, check permissions
    if (state == AppLifecycleState.resumed) {
      print('App resumed, checking permissions...');
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (!mounted) return;
    
    setState(() {
      _isChecking = true;
    });

    try {
      print('Checking permissions...');
      
      // Check all permissions
      final backgroundLocationStatus = await Permission.locationAlways.status;
      final overlayStatus = await Permission.systemAlertWindow.status;
      final hasUsagePermission = await ScreenMonitorService.checkUsageStatsPermission();
      final hasBatteryPermission = await ScreenMonitorService.checkBatteryOptimization();
      
      final backgroundLocationGranted = backgroundLocationStatus.isGranted;
      final overlayGranted = overlayStatus.isGranted;
      
      print('Background location permission: $backgroundLocationGranted');
      print('Overlay permission: $overlayGranted');
      print('Usage stats permission: $hasUsagePermission');
      print('Battery optimization disabled: $hasBatteryPermission');
      
      if (mounted) {
        // Only update state if permissions have actually changed
        final bool stateChanged = 
          _previousBackgroundLocationGranted != backgroundLocationGranted ||
          _previousOverlayGranted != overlayGranted ||
          _previousHasUsagePermission != hasUsagePermission ||
          _previousHasBatteryPermission != hasBatteryPermission;
        
        if (stateChanged || _isChecking) {
          setState(() {
            _backgroundLocationGranted = backgroundLocationGranted;
            _overlayGranted = overlayGranted;
            _hasUsagePermission = hasUsagePermission;
            _hasBatteryPermission = hasBatteryPermission;
            _isChecking = false;
            
            // Update previous state tracking
            _previousBackgroundLocationGranted = backgroundLocationGranted;
            _previousOverlayGranted = overlayGranted;
            _previousHasUsagePermission = hasUsagePermission;
            _previousHasBatteryPermission = hasBatteryPermission;
            
            // Update current step based on permissions
            final totalSteps = _isMiuiDevice ? 5 : 4; // background location, overlay, usage, battery + optional MIUI
            
            if (!backgroundLocationGranted) {
              _currentStep = 0; // Background location step
            } else if (!overlayGranted) {
              _currentStep = 1; // Overlay permission step
            } else if (!hasUsagePermission) {
              _currentStep = 2; // Usage stats step
            } else if (!hasBatteryPermission) {
              _currentStep = 3; // Battery optimization step
            } else if (_isMiuiDevice && !_miuiAutostartPermissionAcknowledged) {
              _currentStep = 4; // MIUI autostart step
            } else {
              _currentStep = totalSteps; // Completion step
            }
          });
        } else {
          // Just update the checking state without triggering UI rebuild
          _isChecking = false;
        }
        
        print('UI updated: currentStep=$_currentStep');
      }
    } catch (e) {
      print('Error checking permissions: $e');
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _requestPermissions() async {
    print('Requesting permissions for step: $_currentStep');
    
    try {
      if (_currentStep == 0) {
        // Request background location permission with proper flow
        await _requestBackgroundLocationPermission();
      } else if (_currentStep == 1) {
        // Request overlay permission
        final overlayResult = await Permission.systemAlertWindow.request();
        setState(() {
          _overlayGranted = overlayResult.isGranted;
        });
      } else if (_currentStep == 2) {
        // Request usage stats permission
        await ScreenMonitorService.requestUsageStatsPermission();
      } else if (_currentStep == 3) {
        // Request battery optimization disable
        await ScreenMonitorService.requestBatteryOptimizationDisable();
      }
      
      // Give user time to grant permissions and return
      await Future.delayed(const Duration(seconds: 1));
      
      // Check permissions again
      await _checkPermissions();
    } catch (e) {
      print('Error requesting permissions: $e');
    }
  }


  Future<void> _requestBackgroundLocationPermission() async {
    print('🔄 Starting two-step background location permission flow...');
    
    try {
      // Step 1: Request foreground location permissions first
      print('Step 1: Requesting foreground location permission...');
      final foregroundResults = await [
        Permission.locationWhenInUse,
        Permission.location,
      ].request();
      
      final foregroundGranted = foregroundResults[Permission.locationWhenInUse]?.isGranted == true ||
                                foregroundResults[Permission.location]?.isGranted == true;
      
      if (!foregroundGranted) {
        print('❌ Foreground location permission denied');
        _showMessage('위치 권한이 필요합니다. 설정에서 위치 권한을 허용해주세요.');
        return;
      }
      
      print('✅ Step 1 completed: Foreground location permission granted');
      
      // Step 2: Now request background location permission
      print('Step 2: Requesting background location permission...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      final backgroundResult = await Permission.locationAlways.request();
      
      setState(() {
        _backgroundLocationGranted = backgroundResult.isGranted;
      });
      
      if (_backgroundLocationGranted) {
        print('🎉 SUCCESS: Background location permission GRANTED - "Always allow" was selected!');
        _showMessage('✅ 위치 권한이 설정되었습니다! GPS 추적이 활성화됩니다.');
      } else {
        print('⚠️ Background location permission DENIED - user selected "While using app" or denied');
        _showMessage('⚠️ "항상 허용"을 선택해야 GPS 추적이 제대로 작동합니다.');
      }
      
    } catch (e) {
      print('Error in background location permission flow: $e');
      _showMessage('권한 요청 중 오류가 발생했습니다. 다시 시도해주세요.');
    }
  }

  // Manual refresh method for when user wants to check permissions
  Future<void> _refreshPermissions() async {
    print('Manual permission refresh requested');
    await _checkPermissions();
  }

  void _nextStep() {
    print('_nextStep called, currentStep: $_currentStep');
    
    if (_currentStep == 0) {
      // Check if background location permission is granted before advancing
      if (_backgroundLocationGranted) {
        setState(() {
          _currentStep = 1;
        });
        print('Advanced to step: $_currentStep');
      } else {
        print('Cannot advance - background location permission not granted');
      }
    } else if (_currentStep == 1) {
      // Check if overlay permission is granted before advancing
      if (_overlayGranted) {
        setState(() {
          _currentStep = 2;
        });
        print('Advanced to step: $_currentStep');
      } else {
        print('Cannot advance - overlay permission not granted');
      }
    } else if (_currentStep == 2) {
      // Check if usage permission is granted before advancing
      if (_hasUsagePermission) {
        setState(() {
          _currentStep = 3;
        });
        print('Advanced to step: $_currentStep');
      } else {
        print('Cannot advance - usage permission not granted');
      }
    } else if (_currentStep == 3) {
      // Check if battery permission is granted before advancing
      if (_hasBatteryPermission) {
        setState(() {
          _currentStep = _isMiuiDevice ? 4 : 5; // MIUI step or completion
        });
        print('Advanced to step: $_currentStep');
      } else {
        print('Cannot advance - battery permission not granted');
      }
    } else if (_currentStep == 4 && _isMiuiDevice) {
      // MIUI autostart permission step
      setState(() {
        _miuiAutostartPermissionAcknowledged = true;
        _currentStep = 5; // Completion step for MIUI devices
      });
      print('MIUI autostart permission acknowledged, advanced to step: $_currentStep');
    } else if (_currentStep >= 4) {
      // All done - navigate to main page
      _completeSetup();
    }
  }

  Future<void> _openAutoStartSettings() async {
    try {
      const platform = MethodChannel('com.thousandemfla.thanks_everyday/miui');
      final bool success = await platform.invokeMethod('requestAutoStartPermission');
      
      if (success) {
        _showMessage('설정 화면이 열렸습니다. 자동 시작 권한을 활성화해주세요.');
      } else {
        _showMessage('설정 화면을 열 수 없습니다. 수동으로 보안 앱에서 설정해주세요.');
      }
    } catch (e) {
      print('Error opening autostart settings: $e');
      _showMessage('설정 화면을 열 수 없습니다. 수동으로 보안 앱에서 설정해주세요.');
    }
  }

  void _completeSetup() async {
    print('_completeSetup called, navigating to main page');
    print('Current widget mounted: $mounted');
    print('Current permissions - usage: $_hasUsagePermission, battery: $_hasBatteryPermission');
    
    // Ensure we have all permissions before proceeding
    if (!_backgroundLocationGranted || !_overlayGranted || 
        !_hasUsagePermission || !_hasBatteryPermission || 
        (_isMiuiDevice && !_miuiAutostartPermissionAcknowledged)) {
      print('Not all permissions granted - cannot complete setup');
      if (_isMiuiDevice && !_miuiAutostartPermissionAcknowledged) {
        _showMessage('MIUI 자동 시작 권한 안내를 확인해주세요.');
      } else {
        _showMessage('모든 권한이 필요합니다. 권한을 확인해주세요.');
      }
      return;
    }
    
    // Store completion in SharedPreferences first
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      print('Setup completion stored in SharedPreferences');
    } catch (e) {
      print('Failed to store setup completion: $e');
    }
    
    // Try direct navigation to HomePage bypassing callback chain
    try {
      print('Attempting direct navigation to HomePage...');
      if (mounted) {
        // Navigate directly to HomePage and clear all previous routes
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
        print('Direct navigation to HomePage completed');
        return;
      }
    } catch (e) {
      print('Direct navigation failed: $e');
    }
    
    // Fallback to callback approach
    try {
      print('Calling onPermissionsComplete callback...');
      widget.onPermissionsComplete();
      print('onPermissionsComplete callback executed successfully');
    } catch (e) {
      print('Callback approach failed: $e');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.backgroundLight, AppTheme.backgroundSecondary],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 40),
                
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Text(
                    '앱 권한 설정',
                    style: TextStyle(
                      fontSize: 28.0,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Step indicator
                _buildStepIndicator(),

                const SizedBox(height: 40),

                // Step content
                _buildStepContent(),

                const SizedBox(height: 40),

                // Action buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final totalSteps = _isMiuiDevice ? 5 : 4; // All permission steps + optional MIUI
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: List.generate(totalSteps, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;
        
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted 
                ? const Color(0xFF10B981)
                : isCurrent 
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFFE5E7EB),
            border: Border.all(
              color: isCompleted || isCurrent
                  ? Colors.transparent
                  : const Color(0xFFD1D5DB),
              width: 2,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(
                    Icons.check,
                    size: 16,
                    color: Colors.white,
                  )
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? Colors.white : const Color(0xFF9CA3AF),
                    ),
                  ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildBackgroundLocationStep();
      case 1:
        return _buildOverlayStep();
      case 2:
        return _buildUsageStatsStep();
      case 3:
        return _buildBatteryStep();
      case 4:
        if (_isMiuiDevice) {
          return _buildMiuiStep(); // MIUI autostart permission step
        } else {
          return _buildCompletionStep(); // Completion step for non-MIUI
        }
      case 5:
        return _buildCompletionStep(); // Completion step for MIUI devices
      default:
        return _buildBackgroundLocationStep();
    }
  }


  Widget _buildBackgroundLocationStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.my_location_rounded,
            size: 80,
            color: Color(0xFFFF7043),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            '위치 접근 권한',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E3440),
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          Text(
            _backgroundLocationGranted 
                ? '✅ 위치 권한이 설정되었습니다!\n\n• 가족과 위치 공유 활성화\n• 안전 확인 기능 사용 가능\n• 다음 단계로 진행하세요'
                : '가족과 위치를 공유하여 안전을 확인하기 위해\n위치 접근 권한이 필요합니다.\n\n'
                  '• 가족이 당신의 위치를 확인 가능\n'
                  '• 안전한 위치 공유 서비스\n'
                  '• "항상 허용" 옵션을 선택해주세요',
            style: TextStyle(
              fontSize: 16,
              color: _backgroundLocationGranted ? const Color(0xFF10B981) : const Color(0xFF6B7280),
              height: 1.5,
              fontWeight: _backgroundLocationGranted ? FontWeight.w600 : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFDF7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.family_restroom,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    '위치 정보는 가족 공유 목적으로만 사용됩니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF047857),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.layers_rounded,
            size: 80,
            color: Color(0xFF8B5CF6),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            '다른 앱 위에 표시 권한',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E3440),
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          Text(
            _overlayGranted 
                ? '✅ 오버레이 권한이 설정되었습니다!\n\n• 백그라운드 모니터링 활성화\n• 안전 신호 감지 준비 완료\n• 다음 단계로 진행하세요'
                : '백그라운드에서 안전 모니터링을 위해\n다른 앱 위에 표시 권한이 필요합니다.\n\n'
                  '• 백그라운드 안전 모니터링\n'
                  '• 응급 상황 감지\n'
                  '• 시스템 알림 표시',
            style: TextStyle(
              fontSize: 16,
              color: _overlayGranted ? const Color(0xFF10B981) : const Color(0xFF6B7280),
              height: 1.5,
              fontWeight: _overlayGranted ? FontWeight.w600 : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8B5CF6)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.security,
                  color: Color(0xFF8B5CF6),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    '이 권한은 안전 모니터링에만 사용됩니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8B5CF6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageStatsStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.security,
            size: 80,
            color: Color(0xFF3B82F6),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            '안전 모니터링 권한',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E3440),
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          Text(
            _hasUsagePermission 
                ? '✅ 권한이 설정되었습니다!\n\n• 안전 확인 기능 활성화\n• 가족 알림 서비스 준비 완료\n• 다음 단계로 진행하세요'
                : '가족에게 안전을 알리기 위해\n휴대폰 사용 모니터링 권한이 필요합니다.\n\n'
                  '• 대략적인 휴대폰 사용 패턴 추적\n'
                  '• 장시간 미사용시 가족에게 알림\n'
                  '• 개인 데이터는 수집하지 않음',
            style: TextStyle(
              fontSize: 16,
              color: _hasUsagePermission ? const Color(0xFF10B981) : const Color(0xFF6B7280),
              height: 1.5,
              fontWeight: _hasUsagePermission ? FontWeight.w600 : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info,
                  color: Color(0xFFF59E0B),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    '이 권한은 안드로이드 설정에서 직접 허용해주세요.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.battery_std,
            size: 80,
            color: Color(0xFF10B981),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            '배터리 설정 조정',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E3440),
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          Text(
            _hasBatteryPermission
                ? '✅ 배터리 설정이 완료되었습니다!\n\n• 앱이 안정적으로 실행\n• 가족 알림 기능 정상 작동\n• 다음 단계로 진행하세요'
                : '앱이 안정적으로 작동하도록\n배터리 설정을 조정합니다.\n\n'
                  '• 앱이 백그라운드에서 실행\n'
                  '• 안정적인 가족 알림 서비스\n'
                  '• 배터리 사용량은 최소화됨',
            style: TextStyle(
              fontSize: 16,
              color: _hasBatteryPermission ? const Color(0xFF10B981) : const Color(0xFF6B7280),
              height: 1.5,
              fontWeight: _hasBatteryPermission ? FontWeight.w600 : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFDF7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.eco,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    '이 설정은 앱의 안정적인 작동에 필수입니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF047857),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle,
            size: 80,
            color: Color(0xFF10B981),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            '설정 완료!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF10B981),
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          const Text(
            '모든 권한이 설정되었습니다.\n이제 가족 안전 확인 서비스를 사용할 수 있습니다.\n\n'
            '• 가족과 위치 공유 시작\n'
            '• 정기적인 안전 확인 알림\n'
            '• 백그라운드에서 자동 실행',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFDF7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.family_restroom,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    '가족들이 당신의 안전을 확인할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF047857),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiuiStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.smartphone,
            size: 80,
            color: Color(0xFFFF7043),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            'MIUI 자동 시작 권한 설정',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFF7043),
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          const Text(
            'Xiaomi/MIUI 기기에서는 앱의 재부팅 후 동작을 위해\n자동 시작 권한이 필요합니다.',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '설정 방법:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF7043),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. 보안 앱 → 앱 관리 → 이 앱 찾기\n'
                  '2. "자동 시작" 허용으로 설정\n'
                  '3. "다른 앱에 의해 앱 시작 허용" 활성화\n'
                  '4. 배터리 절약 모드에서 이 앱 제외',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFFF7043),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: const Text(
                    '이 설정 없이는 재부팅 후 생존 신호 감지가 작동하지 않습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_isChecking) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
        ),
      );
    }

    switch (_currentStep) {
      case 0: // Background location permission
        return Column(
          children: [
            _buildStandardPermissionButton(
              hasPermission: _backgroundLocationGranted,
              requestText: '위치 권한 허용하기',
              nextText: '다음 단계로',
              color: const Color(0xFF3B82F6),
            ),
            
            const SizedBox(height: 16),
            
            // Refresh button
            GestureDetector(
              onTap: _refreshPermissions,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF3B82F6)),
                ),
                child: const Text(
                  '권한 상태 확인하기',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF3B82F6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
        
      case 1: // Overlay permission
        return _buildStandardPermissionButton(
          hasPermission: _overlayGranted,
          requestText: '오버레이 권한 허용하기',
          nextText: '다음 단계로',
          color: const Color(0xFF8B5CF6),
        );
        
      case 2: // Usage stats permission
        return Column(
          children: [
            _buildStandardPermissionButton(
              hasPermission: _hasUsagePermission,
              requestText: '사용 통계 권한 설정하기',
              nextText: '다음 단계로',
              color: const Color(0xFF3B82F6),
            ),
            
            const SizedBox(height: 16),
            
            // Refresh button
            GestureDetector(
              onTap: _refreshPermissions,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: const Text(
                  '권한 확인하기',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Skip button
            GestureDetector(
              onTap: _completeSetup,
              child: const Text(
                '나중에 설정하기',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF6B7280),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        );
        
      case 3: // Battery optimization
        return _buildStandardPermissionButton(
          hasPermission: _hasBatteryPermission,
          requestText: '배터리 최적화 해제',
          nextText: '다음 단계로',
          color: const Color(0xFF10B981),
        );
        
      case 4: // MIUI or Completion
        if (_isMiuiDevice) {
          // MIUI autostart permission buttons
          return Column(
            children: [
              // Open Settings button
              GestureDetector(
                onTap: _openAutoStartSettings,
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF7043), Color(0xFFD84315)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7043).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '설정 화면 열기',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Acknowledge button  
              GestureDetector(
                onTap: _nextStep,
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '설정 완료, 다음 단계로',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        } else {
          // Non-MIUI completion button
          return GestureDetector(
            onTap: () {
              print('앱 사용 시작하기 button clicked');
              _completeSetup();
            },
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '앱 사용 시작하기',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        }
        
      case 5: // MIUI completion
        return GestureDetector(
          onTap: () {
            print('MIUI 앱 사용 시작하기 button clicked');
            _completeSetup();
          },
          child: Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                '앱 사용 시작하기',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
        
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStandardPermissionButton({
    required bool hasPermission,
    required String requestText,
    required String nextText,
    required Color color,
  }) {
    return GestureDetector(
      onTap: hasPermission ? _nextStep : _requestPermissions,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.8)],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            hasPermission ? nextText : requestText,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}