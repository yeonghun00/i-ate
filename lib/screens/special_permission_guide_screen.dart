import 'package:flutter/material.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';
import 'package:thanks_everyday/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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
  bool _hasUsagePermission = false;
  bool _hasBatteryPermission = false;
  Timer? _permissionCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _startPermissionPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionCheckTimer?.cancel();
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
      final hasUsagePermission = await ScreenMonitorService.checkUsageStatsPermission();
      final hasBatteryPermission = await ScreenMonitorService.checkBatteryOptimization();
      
      print('Usage stats permission: $hasUsagePermission');
      print('Battery optimization disabled: $hasBatteryPermission');
      
      if (mounted) {
        setState(() {
          _hasUsagePermission = hasUsagePermission;
          _hasBatteryPermission = hasBatteryPermission;
          _isChecking = false;
          
          // Update current step based on permissions
          if (hasUsagePermission && hasBatteryPermission) {
            print('All permissions granted, jumping to step 2');
            _currentStep = 2; // Complete
          } else if (hasUsagePermission && !hasBatteryPermission) {
            print('Usage permission granted, moving to step 1 (battery optimization)');
            _currentStep = 1; // Battery optimization step
          } else {
            print('Usage permission not granted, staying at step 0');
            _currentStep = 0; // Usage stats step
          }
        });
        
        print('UI updated: hasUsagePermission=$_hasUsagePermission, hasBatteryPermission=$_hasBatteryPermission, currentStep=$_currentStep');
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
        // Request usage stats permission
        await ScreenMonitorService.requestUsageStatsPermission();
      } else if (_currentStep == 1) {
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

  void _startPermissionPolling() {
    // Check permissions every 1 second for real-time updates
    _permissionCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _currentStep < 2) {
        _checkPermissions();
      } else {
        timer.cancel();
      }
    });
  }

  void _nextStep() {
    print('_nextStep called, currentStep: $_currentStep');
    
    if (_currentStep == 0) {
      // Check if usage permission is granted before advancing
      if (_hasUsagePermission) {
        setState(() {
          _currentStep = 1;
        });
        print('Advanced to step: $_currentStep');
      } else {
        print('Cannot advance - usage permission not granted');
      }
    } else if (_currentStep == 1) {
      // Check if battery permission is granted before advancing
      if (_hasBatteryPermission) {
        setState(() {
          _currentStep = 2;
        });
        print('Advanced to step: $_currentStep');
      } else {
        print('Cannot advance - battery permission not granted');
      }
    } else if (_currentStep == 2) {
      // All done - navigate to main page
      _completeSetup();
    }
  }

  void _completeSetup() async {
    print('_completeSetup called, navigating to main page');
    print('Current widget mounted: $mounted');
    print('Current permissions - usage: $_hasUsagePermission, battery: $_hasBatteryPermission');
    
    // Cancel timer to prevent interference
    _permissionCheckTimer?.cancel();
    
    // Ensure we have all permissions before proceeding
    if (!_hasUsagePermission || !_hasBatteryPermission) {
      print('Not all permissions granted - cannot complete setup');
      _showMessage('모든 권한이 필요합니다. 권한을 확인해주세요.');
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
              colors: [Color(0xFFF8F9FA), Color(0xFFE9ECEF)],
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
                    '생존 신호 감지 설정',
                    style: TextStyle(
                      fontSize: 28.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E3440),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;
        
        return Row(
          children: [
            Container(
              width: 40,
              height: 40,
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
                        size: 20,
                        color: Colors.white,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isCurrent ? Colors.white : const Color(0xFF9CA3AF),
                        ),
                      ),
              ),
            ),
            if (index < 2)
              Container(
                width: 40,
                height: 2,
                color: isCompleted 
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE5E7EB),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      default:
        return _buildStep1();
    }
  }

  Widget _buildStep1() {
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
            '휴대폰 사용 모니터링 권한',
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
                ? '✅ 권한이 설정되었습니다!\n\n• 화면 사용 모니터링 활성화\n• 생존 신호 감지 준비 완료\n• 다음 단계로 진행하세요'
                : '생존 신호 감지를 위해 휴대폰 화면 사용을 모니터링합니다.\n\n'
                  '• 화면이 켜질 때마다 기록\n'
                  '• 12시간 이상 미사용시 가족에게 알림\n'
                  '• 개인정보는 수집하지 않음',
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
                    '이 권한은 Android 설정에서 직접 허용해야 합니다.',
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

  Widget _buildStep2() {
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
            '배터리 최적화 해제',
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
                ? '✅ 배터리 최적화가 해제되었습니다!\n\n• 앱이 백그라운드에서 계속 실행\n• 정확한 생존 신호 감지\n• 다음 단계로 진행하세요'
                : '지속적인 모니터링을 위해 배터리 최적화를 해제합니다.\n\n'
                  '• 앱이 백그라운드에서 계속 실행\n'
                  '• 정확한 생존 신호 감지\n'
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
                    '이 설정은 생존 신호 감지에 필수입니다.',
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

  Widget _buildStep3() {
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
            '모든 권한이 설정되었습니다.\n이제 생존 신호 감지가 활성화됩니다.\n\n'
            '• 휴대폰 사용 모니터링 시작\n'
            '• 설정된 시간 미사용시 가족 알림\n'
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

  Widget _buildActionButtons() {
    if (_isChecking) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
        ),
      );
    }

    switch (_currentStep) {
      case 0:
        return Column(
          children: [
            // Request permissions button
            GestureDetector(
              onTap: _hasUsagePermission ? _nextStep : _requestPermissions,
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _hasUsagePermission ? '다음 단계로' : '권한 설정하기',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Refresh button
            GestureDetector(
              onTap: _checkPermissions,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
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
        
      case 1:
        return GestureDetector(
          onTap: _hasBatteryPermission ? _nextStep : _requestPermissions,
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _hasBatteryPermission ? '다음 단계' : '배터리 최적화 해제',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
        
      case 2:
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
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
}