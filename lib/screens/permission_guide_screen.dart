import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/screens/background_location_guide_screen.dart';

class PermissionGuideScreen extends StatefulWidget {
  final VoidCallback onPermissionsGranted;
  
  const PermissionGuideScreen({super.key, required this.onPermissionsGranted});

  @override
  State<PermissionGuideScreen> createState() => _PermissionGuideScreenState();
}

class _PermissionGuideScreenState extends State<PermissionGuideScreen> {
  bool _locationGranted = false;
  bool _backgroundLocationGranted = false;
  bool _batteryOptimizationGranted = false;
  bool _overlayGranted = false;
  bool _isChecking = false;
  bool _showingBackgroundGuide = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final locationStatus = await Permission.locationWhenInUse.status;
    final backgroundLocationStatus = await Permission.locationAlways.status;
    final batteryOptimizationStatus = await Permission.ignoreBatteryOptimizations.status;
    final overlayStatus = await Permission.systemAlertWindow.status;

    setState(() {
      _locationGranted = locationStatus.isGranted;
      _backgroundLocationGranted = backgroundLocationStatus.isGranted;
      _batteryOptimizationGranted = batteryOptimizationStatus.isGranted;
      _overlayGranted = overlayStatus.isGranted;
    });

    if (_locationGranted && _backgroundLocationGranted && _batteryOptimizationGranted && _overlayGranted) {
      widget.onPermissionsGranted();
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isChecking = true;
    });

    try {
      // Step 1: Request foreground location permissions first
      final foregroundResults = await [
        Permission.locationWhenInUse,
        Permission.ignoreBatteryOptimizations,
        Permission.systemAlertWindow,
      ].request();

      setState(() {
        _locationGranted = foregroundResults[Permission.locationWhenInUse]?.isGranted ?? false;
        _batteryOptimizationGranted = foregroundResults[Permission.ignoreBatteryOptimizations]?.isGranted ?? false;
        _overlayGranted = foregroundResults[Permission.systemAlertWindow]?.isGranted ?? false;
      });

      // Step 2: Only request background location if foreground location is granted
      if (_locationGranted) {
        print('✅ Foreground location granted, showing background location guide...');
        
        // Show background location guide before requesting permission
        await _showBackgroundLocationGuide();
        
      } else {
        print('❌ Foreground location not granted, cannot request background location');
      }

      if (_locationGranted && _backgroundLocationGranted && _batteryOptimizationGranted && _overlayGranted) {
        widget.onPermissionsGranted();
      }
    } catch (e) {
      print('Permission request failed: $e');
    } finally {
      setState(() {
        _isChecking = false;
      });
    }
  }

  Future<void> _showBackgroundLocationGuide() async {
    setState(() {
      _showingBackgroundGuide = true;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BackgroundLocationGuideScreen(
          onContinue: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );

    setState(() {
      _showingBackgroundGuide = false;
    });

    // Now request background location permission
    await _requestBackgroundLocationPermission();
  }

  Future<void> _requestBackgroundLocationPermission() async {
    print('🔄 Requesting background location permission...');
    
    // Add a small delay to ensure the system is ready
    await Future.delayed(const Duration(milliseconds: 500));
    
    final backgroundResult = await Permission.locationAlways.request();
    setState(() {
      _backgroundLocationGranted = backgroundResult.isGranted;
    });
    
    if (_backgroundLocationGranted) {
      print('✅ Background location granted - "Always allow" option was selected');
    } else {
      print('❌ Background location denied - user selected "While using app" or denied');
    }

    // Check if all permissions are now granted
    if (_locationGranted && _backgroundLocationGranted && _batteryOptimizationGranted && _overlayGranted) {
      widget.onPermissionsGranted();
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
              colors: [
                AppTheme.backgroundLight,
                AppTheme.backgroundSecondary,
              ],
            ),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                // App icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryGreen,
                        AppTheme.darkGreen,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.security,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Title
                const Text(
                  '앱 사용 권한 설정',
                  style: TextStyle(
                    fontSize: 28.0,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  '식사하셨어요? 앱이 제대로 작동하려면\n아래 권한이 필요합니다',
                  style: TextStyle(
                    fontSize: 18.0,
                    color: AppTheme.textLight,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),
                
                // Permission items
                _buildPermissionItem(
                  icon: Icons.location_on_rounded,
                  title: 'GPS 위치 접근 (앱 사용 중)',
                  description: '앱을 사용하는 동안 위치 추적을 위해 필요합니다',
                  granted: _locationGranted,
                ),
                
                const SizedBox(height: 16),
                
                _buildPermissionItem(
                  icon: Icons.my_location_rounded,
                  title: 'GPS 백그라운드 추적',
                  description: '앱이 꺼져도 지속적인 위치 추적을 위해 필요합니다',
                  granted: _backgroundLocationGranted,
                  isImportant: true,
                ),
                
                const SizedBox(height: 16),
                
                _buildPermissionItem(
                  icon: Icons.battery_charging_full_rounded,
                  title: '배터리 최적화 제외',
                  description: '지속적인 모니터링을 위해 필요한 설정입니다',
                  granted: _batteryOptimizationGranted,
                ),
                
                const SizedBox(height: 16),
                
                _buildPermissionItem(
                  icon: Icons.layers_rounded,
                  title: '다른 앱 위에 표시',
                  description: '백그라운드에서 안전 모니터링을 위해 필요합니다',
                  granted: _overlayGranted,
                ),
                
                const SizedBox(height: 50),
                
                // Permission button
                GestureDetector(
                  onTap: _isChecking ? null : _requestPermissions,
                  child: Container(
                    width: double.infinity,
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(35),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryGreen,
                          AppTheme.darkGreen,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isChecking
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            )
                          : const Text(
                              '권한 허용하기',
                              style: TextStyle(
                                fontSize: 20.0,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  '권한을 허용하지 않으면 일부 기능이 제한될 수 있습니다',
                  style: TextStyle(
                    fontSize: 14.0,
                    color: AppTheme.textDisabled,
                  ),
                  textAlign: TextAlign.center,
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required bool granted,
    bool isImportant = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isImportant ? Border.all(
          color: granted ? AppTheme.primaryGreen : Colors.orange,
          width: 2,
        ) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: granted ? AppTheme.primaryGreen : AppTheme.textDisabled,
            ),
            child: Icon(
              icon,
              size: 24,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMedium,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14.0,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ),
          
          Icon(
            granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? AppTheme.primaryGreen : AppTheme.textDisabled,
            size: 24,
          ),
        ],
      ),
    );
  }
}