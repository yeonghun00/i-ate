import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';
import 'package:thanks_everyday/services/location_service.dart';
import 'package:thanks_everyday/services/food_tracking_service.dart';
import 'package:thanks_everyday/screens/boot_debug_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onDataDeleted;
  final VoidCallback onReset;
  
  const SettingsScreen({
    super.key,
    required this.onDataDeleted,
    required this.onReset,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final FirebaseService _firebaseService = FirebaseService();
  String? _familyCode;
  String? _elderlyName;
  // Recovery code removed - using name + connection code only
  bool _survivalSignalEnabled = false;
  int _alertHours = 12;
  String? _familyContact;
  bool _locationTrackingEnabled = false;
  int _foodAlertHours = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app resumes, check if permissions changed in system settings
    if (state == AppLifecycleState.resumed) {
      print('🔄 App resumed - checking if GPS permissions changed...');
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check actual location permission status
      bool hasBackgroundLocationPermission = await _checkBackgroundLocationPermission();
      bool savedLocationEnabled = prefs.getBool('flutter.location_tracking_enabled') ?? false;
      
      // If setting says enabled but permission is missing, disable it
      bool actualLocationEnabled = savedLocationEnabled && hasBackgroundLocationPermission;
      
      if (savedLocationEnabled && !hasBackgroundLocationPermission) {
        print('⚠️ GPS was enabled but background location permission is missing - disabling');
        await prefs.setBool('flutter.location_tracking_enabled', false);
        await LocationService.setLocationTrackingEnabled(false);
      }
      
      setState(() {
        _familyCode = _firebaseService.familyCode;
        _elderlyName = _firebaseService.elderlyName;
        // Recovery code loading removed
        _survivalSignalEnabled = prefs.getBool('flutter.survival_signal_enabled') ?? false;
        _alertHours = prefs.getInt('alert_hours') ?? 12;
        _familyContact = prefs.getString('family_contact');
        _locationTrackingEnabled = actualLocationEnabled;
        _foodAlertHours = prefs.getInt('food_alert_threshold') ?? 8;
      });
    } catch (e) {
      print('Failed to load settings: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }


  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '계정 삭제',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E3440),
            ),
          ),
          content: const Text(
            '정말로 계정을 삭제하시겠습니까?\n모든 데이터가 영구적으로 삭제되며 복구할 수 없습니다.',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '취소',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                await _deleteAllData();
                Navigator.of(context).pop();
                widget.onDataDeleted();
              },
              child: const Text(
                '삭제',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }



  Future<void> _deleteAllData() async {
    try {
      // Delete from Firebase if family code exists
      if (_familyCode != null) {
        await _firebaseService.deleteFamilyCode(_familyCode!);
      }
      
      // Clear all local data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      _showMessage('모든 데이터가 삭제되었습니다.');
      print('All data deleted successfully');
    } catch (e) {
      print('Error deleting data: $e');
      _showMessage('데이터 삭제 중 오류가 발생했습니다.');
    }
  }


  Future<void> _updateSettings() async {
    print('Updating settings - survivalSignal: $_survivalSignalEnabled, alertHours: $_alertHours');
    
    try {
      // Update local settings first
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flutter.survival_signal_enabled', _survivalSignalEnabled);
      await prefs.setInt('alert_hours', _alertHours);
      print('Local settings updated successfully');
      
      // Update screen monitoring service
      try {
        if (_survivalSignalEnabled) {
          await ScreenMonitorService.enableSurvivalSignal();
          print('Survival signal enabled');
        } else {
          await ScreenMonitorService.disableSurvivalSignal();
          print('Survival signal disabled');
        }
      } catch (e) {
        print('Error updating screen monitor service: $e');
        // Don't fail the entire update if screen monitoring fails
      }
      
      // Update Firebase settings
      if (_familyCode != null) {
        try {
          print('Updating Firebase settings for family code: $_familyCode');
          final success = await _firebaseService.updateFamilySettings(
            survivalSignalEnabled: _survivalSignalEnabled,
            familyContact: _familyContact ?? '',
            alertHours: _alertHours,
          );
          
          if (success) {
            print('Firebase settings updated successfully');
          } else {
            print('Firebase settings update failed');
          }
        } catch (e) {
          print('Error updating Firebase settings: $e');
          // Don't fail the entire update if Firebase fails
        }
      } else {
        print('No family code found, skipping Firebase update');
      }
      
      _showMessage('설정이 저장되었습니다.');
    } catch (e) {
      print('Error updating settings: $e');
      _showMessage('설정 저장 중 오류가 발생했습니다: ${e.toString()}');
    }
  }

  Future<void> _updateLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flutter.location_tracking_enabled', _locationTrackingEnabled);
      
      // Update location service
      await LocationService.setLocationTrackingEnabled(_locationTrackingEnabled);
      
      _showMessage('위치 추적 설정이 저장되었습니다.');
    } catch (e) {
      print('Error updating location settings: $e');
      _showMessage('위치 설정 저장 중 오류가 발생했습니다.');
    }
  }

  Future<void> _updateFoodSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('food_alert_threshold', _foodAlertHours);
      
      // Update food tracking service
      await FoodTrackingService.setFoodAlertThreshold(_foodAlertHours);
      
      _showMessage('식사 알림 설정이 저장되었습니다.');
    } catch (e) {
      print('Error updating food settings: $e');
      _showMessage('식사 설정 저장 중 오류가 발생했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '설정',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E3440),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF6B7280)),
      ),
      body: Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account Information Section
              _buildSection(
                title: '계정 정보',
                children: [
                  _buildInfoItem(
                    icon: Icons.person,
                    label: '사용자 이름',
                    value: _elderlyName ?? '설정되지 않음',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    icon: Icons.family_restroom,
                    label: '가족 코드',
                    value: _familyCode ?? '설정되지 않음',
                  ),
                  const SizedBox(height: 12),
                  // Recovery code display removed - using name + connection code only
                ],
              ),

              const SizedBox(height: 30),

              // App Settings Section
              _buildSection(
                title: '앱 설정',
                children: [
                  _buildToggleItem(
                    icon: Icons.health_and_safety,
                    title: '안전 확인 알림',
                    subtitle: '휴대폰 사용이 없으면 자녀에게 안전 확인 알림 발송',
                    value: _survivalSignalEnabled,
                    onChanged: (value) {
                      setState(() {
                        _survivalSignalEnabled = value;
                      });
                      // Add slight delay to prevent rapid toggle crashes
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _updateSettings();
                      });
                    },
                  ),
                  
                  // Alert hours setting (only show when survival signal is enabled)
                  if (_survivalSignalEnabled) ...[
                    const SizedBox(height: 16),
                    _buildAlertHoursSelector(),
                  ],
                  
                  const SizedBox(height: 16),
                  
                  _buildLocationToggleItem(),
                  
                  const SizedBox(height: 16),
                  
                  _buildToggleItem(
                    icon: Icons.restaurant_rounded,
                    title: '식사 알림',
                    subtitle: '식사하지 않으면 자녀에게 알림',
                    value: _foodAlertHours > 0,
                    onChanged: (value) {
                      setState(() {
                        _foodAlertHours = value ? 8 : 0;
                      });
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _updateFoodSettings();
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // Account Actions Section
              _buildSection(
                title: '계정 관리',
                children: [
                  _buildActionButton(
                    icon: Icons.delete_forever,
                    title: '계정 삭제',
                    subtitle: '모든 데이터 영구 삭제',
                    color: const Color(0xFFEF4444),
                    onTap: _showDeleteAccountDialog,
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // App Information
              Center(
                child: Column(
                  children: [
                    const Text(
                      '식사 기록 앱',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'v1.0.0',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '가족과 함께하는 식사 관리',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E3440),
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 24,
          color: const Color(0xFF10B981),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2E3440),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? subtitleColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 24,
          color: const Color(0xFF10B981),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: subtitleColor ?? const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: color.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAlertHoursSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 20,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              const Text(
                '알림 시간 설정',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Time options
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [3, 6, 12, 24].map((hours) {
              final isSelected = _alertHours == hours;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _alertHours = hours;
                  });
                  // Add slight delay to prevent rapid selection crashes
                  Future.delayed(const Duration(milliseconds: 300), () {
                    _updateSettings();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF10B981)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF10B981)
                          : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ] : [],
                  ),
                  child: Text(
                    '${hours}시간',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 12),
          
          Text(
            '${_alertHours}시간 이상 휴대폰을 사용하지 않으면 자녀에게 알림이 전송됩니다.',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // Build location toggle with dynamic subtitle showing permission status
  Widget _buildLocationToggleItem() {
    return FutureBuilder<bool>(
      future: _checkBackgroundLocationPermission(),
      builder: (context, snapshot) {
        bool hasPermission = snapshot.data ?? false;
        String subtitle;
        Color subtitleColor;
        
        if (_locationTrackingEnabled && hasPermission) {
          subtitle = '✅ 위치 정보를 자녀에게 공유 (2분마다)';
          subtitleColor = const Color(0xFF10B981);
        } else if (_locationTrackingEnabled && !hasPermission) {
          subtitle = '⚠️ "항상 허용" 권한이 필요합니다';
          subtitleColor = const Color(0xFFEF4444);
        } else {
          subtitle = '위치 정보를 자녀에게 공유';
          subtitleColor = const Color(0xFF6B7280);
        }
        
        return _buildToggleItem(
          icon: Icons.location_on_rounded,
          title: 'GPS 위치 추적',
          subtitle: subtitle,
          subtitleColor: subtitleColor,
          value: _locationTrackingEnabled,
          onChanged: (value) async {
            if (value) {
              // When enabling GPS, request background location permissions first
              bool permissionGranted = await _requestBackgroundLocationPermission();
              if (permissionGranted) {
                setState(() {
                  _locationTrackingEnabled = true;
                });
                Future.delayed(const Duration(milliseconds: 300), () {
                  _updateLocationSettings();
                });
              } else {
                // Permission denied, show explanation
                _showLocationPermissionDialog();
              }
            } else {
              // Disabling GPS - no permission needed
              setState(() {
                _locationTrackingEnabled = false;
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                _updateLocationSettings();
              });
            }
          },
        );
      },
    );
  }

  // Check if background location permission is currently granted
  Future<bool> _checkBackgroundLocationPermission() async {
    PermissionStatus status = await Permission.locationAlways.status;
    bool granted = status.isGranted;
    
    print('📍 Background location permission status: $status (granted: $granted)');
    return granted;
  }

  // Request background location permission with proper two-step flow
  Future<bool> _requestBackgroundLocationPermission() async {
    print('🔄 Starting two-step background location permission flow...');
    
    // Step 1: Request foreground location permissions first
    Map<Permission, PermissionStatus> foregroundStatuses = await [
      Permission.locationWhenInUse,
      Permission.location,
    ].request();
    
    bool foregroundGranted = foregroundStatuses[Permission.locationWhenInUse]?.isGranted == true ||
                            foregroundStatuses[Permission.location]?.isGranted == true;
    
    if (!foregroundGranted) {
      print('❌ Foreground location permission denied');
      return false;
    }
    
    print('✅ Step 1 completed: Foreground location permission granted');
    
    // Step 2: Now request background location permission (this shows "Always allow" option)
    await Future.delayed(const Duration(milliseconds: 500));
    PermissionStatus backgroundStatus = await Permission.locationAlways.request();
    
    bool backgroundGranted = backgroundStatus.isGranted;
    
    if (backgroundGranted) {
      print('🎉 SUCCESS: Background location permission GRANTED - "Always allow" was selected!');
      print('✅ GPS will now work continuously every 2 minutes even when app is killed');
    } else {
      print('⚠️ Background location permission DENIED - user selected "While using app" or denied');
    }
    
    return backgroundGranted;
  }

  // Show dialog explaining why background location permission is needed
  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('GPS 위치 권한 필요'),
          content: const Text(
            'GPS 위치 추적이 제대로 작동하려면 "항상 허용" 권한이 필요합니다.\n\n'
            '설정에서 위치 권한을 "항상 허용"으로 변경해주세요.\n\n'
            '앱이 백그라운드에서도 2분마다 위치를 자녀에게 전송할 수 있습니다.'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Open app settings
                openAppSettings();
              },
              child: const Text('설정 열기'),
            ),
          ],
        );
      },
    );
  }
}