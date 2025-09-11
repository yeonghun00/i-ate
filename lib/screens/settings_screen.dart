import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';
import 'package:thanks_everyday/services/location_service.dart';
import 'package:thanks_everyday/services/food_tracking_service.dart';
import 'package:thanks_everyday/services/permission_manager_service.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/widgets/permission_guide_widget.dart';
import 'package:thanks_everyday/models/sleep_time_settings.dart';

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

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _alertHoursController = TextEditingController();
  String? _familyCode;
  String? _elderlyName;
  // Recovery code removed - using name + connection code only
  bool _survivalSignalEnabled = false;
  int _alertHours = 12;
  bool _useCustomAlertHours = false;
  String? _familyContact;
  bool _locationTrackingEnabled = false;
  int _foodAlertHours = 8;
  PermissionStatusInfo? _permissionStatus;
  
  // Sleep time settings
  bool _sleepTimeExclusionEnabled = false;
  SleepTimeSettings _sleepTimeSettings = SleepTimeSettings.defaultSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertHoursController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app resumes, check if permissions changed in system settings
    if (state == AppLifecycleState.resumed) {
      AppLogger.debug('App resumed - checking if GPS permissions changed...', tag: 'SettingsScreen');
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check actual location permission status
      bool hasBackgroundLocationPermission =
          await _checkBackgroundLocationPermission();
      bool savedLocationEnabled =
          prefs.getBool('flutter.location_tracking_enabled') ?? false;

      // If setting says enabled but permission is missing, disable it
      bool actualLocationEnabled =
          savedLocationEnabled && hasBackgroundLocationPermission;

      if (savedLocationEnabled && !hasBackgroundLocationPermission) {
        AppLogger.warning('GPS was enabled but background location permission is missing - disabling', tag: 'SettingsScreen');
        await prefs.setBool('flutter.location_tracking_enabled', false);
        await LocationService.setLocationTrackingEnabled(false);
      }

      // Check all permissions status
      final permissionStatus = await PermissionManagerService.checkAllPermissions();

      // Get alert hours ONLY from Firebase (primary source)
      int alertHours = 12; // default fallback
      if (_firebaseService.familyCode != null) {
        try {
          final familyInfo = await _firebaseService.getFamilyInfo(_firebaseService.familyCode!);
          if (familyInfo != null) {
            // Check if settings exist in the family info
            if (familyInfo['settings'] != null) {
              final settings = familyInfo['settings'] as Map<String, dynamic>;
              alertHours = settings['alertHours'] ?? 12;
            } else if (familyInfo['alertHours'] != null) {
              // Backward compatibility - check direct field
              alertHours = familyInfo['alertHours'] as int;
            }
            AppLogger.info('Loaded alert hours from Firebase: $alertHours', tag: 'SettingsScreen');
          } else {
            AppLogger.warning('No family info found in Firebase, using default: 12', tag: 'SettingsScreen');
          }
        } catch (e) {
          AppLogger.error('Failed to fetch alert hours from Firebase: $e', tag: 'SettingsScreen');
          AppLogger.info('Using default alert hours: 12', tag: 'SettingsScreen');
        }
      } else {
        AppLogger.warning('No family code found, using default alert hours: 12', tag: 'SettingsScreen');
      }

      setState(() {
        _familyCode = _firebaseService.familyCode;
        _elderlyName = _firebaseService.elderlyName;
        // Recovery code loading removed
        _survivalSignalEnabled =
            prefs.getBool('flutter.survival_signal_enabled') ?? false;
        _alertHours = alertHours;
        
        // Check if it's a custom value (not in preset options)
        _useCustomAlertHours = ![3, 6, 12, 24].contains(_alertHours);
        if (_useCustomAlertHours) {
          _alertHoursController.text = _alertHours.toString();
        }
        
        AppLogger.info('Settings loaded - Alert hours: $_alertHours, Custom: $_useCustomAlertHours', tag: 'SettingsScreen');
        
        _familyContact = prefs.getString('family_contact');
        _locationTrackingEnabled = actualLocationEnabled;
        _foodAlertHours = prefs.getInt('food_alert_threshold') ?? 8;
        _permissionStatus = permissionStatus;
        
        // Load sleep time settings
        _sleepTimeExclusionEnabled = prefs.getBool('flutter.sleep_exclusion_enabled') ?? false;
        final sleepStartHour = prefs.getInt('flutter.sleep_start_hour') ?? 22;
        final sleepStartMinute = prefs.getInt('flutter.sleep_start_minute') ?? 0;
        final sleepEndHour = prefs.getInt('flutter.sleep_end_hour') ?? 6;
        final sleepEndMinute = prefs.getInt('flutter.sleep_end_minute') ?? 0;
        final activeDaysString = prefs.getString('flutter.sleep_active_days') ?? '1,2,3,4,5,6,7';
        final activeDays = activeDaysString.split(',').map((e) => int.parse(e.trim())).toList();
        
        _sleepTimeSettings = SleepTimeSettings(
          enabled: _sleepTimeExclusionEnabled,
          sleepStart: TimeOfDay(hour: sleepStartHour, minute: sleepStartMinute),
          sleepEnd: TimeOfDay(hour: sleepEndHour, minute: sleepEndMinute),
          activeDays: activeDays,
        );
      });
    } catch (e) {
      AppLogger.error('Failed to load settings: $e', tag: 'SettingsScreen');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
                style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
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
      AppLogger.info('All data deleted successfully', tag: 'SettingsScreen');
    } catch (e) {
      AppLogger.error('Error deleting data: $e', tag: 'SettingsScreen');
      _showMessage('데이터 삭제 중 오류가 발생했습니다.');
    }
  }

  Future<void> _updateSettings() async {
    AppLogger.info('Updating settings - survivalSignal: $_survivalSignalEnabled, alertHours: $_alertHours', tag: 'SettingsScreen');

    try {
      // Update local settings (excluding alert_hours which is stored in Firebase only)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'flutter.survival_signal_enabled',
        _survivalSignalEnabled,
      );
      
      // Save sleep time settings locally
      await prefs.setBool('flutter.sleep_exclusion_enabled', _sleepTimeExclusionEnabled);
      await prefs.setInt('flutter.sleep_start_hour', _sleepTimeSettings.sleepStart.hour);
      await prefs.setInt('flutter.sleep_start_minute', _sleepTimeSettings.sleepStart.minute);
      await prefs.setInt('flutter.sleep_end_hour', _sleepTimeSettings.sleepEnd.hour);
      await prefs.setInt('flutter.sleep_end_minute', _sleepTimeSettings.sleepEnd.minute);
      await prefs.setString('flutter.sleep_active_days', _sleepTimeSettings.activeDays.join(','));
      
      AppLogger.info('Local settings updated successfully (alert hours stored in Firebase only)', tag: 'SettingsScreen');

      // Update screen monitoring service
      try {
        if (_survivalSignalEnabled) {
          await ScreenMonitorService.enableSurvivalSignal();
          AppLogger.info('Survival signal enabled', tag: 'SettingsScreen');
        } else {
          await ScreenMonitorService.disableSurvivalSignal();
          AppLogger.info('Survival signal disabled', tag: 'SettingsScreen');
        }
      } catch (e) {
        AppLogger.error('Error updating screen monitor service: $e', tag: 'SettingsScreen');
        // Don't fail the entire update if screen monitoring fails
      }

      // Update Firebase settings
      if (_familyCode != null) {
        try {
          AppLogger.info('Updating Firebase settings for family code: $_familyCode', tag: 'SettingsScreen');
          final success = await _firebaseService.updateFamilySettings(
            survivalSignalEnabled: _survivalSignalEnabled,
            familyContact: _familyContact ?? '',
            alertHours: _alertHours,
            sleepTimeSettings: _sleepTimeExclusionEnabled ? _sleepTimeSettings.toMap() : null,
          );

          if (success) {
            AppLogger.info('Firebase settings updated successfully', tag: 'SettingsScreen');
          } else {
            AppLogger.warning('Firebase settings update failed', tag: 'SettingsScreen');
          }
        } catch (e) {
          AppLogger.error('Error updating Firebase settings: $e', tag: 'SettingsScreen');
          // Don't fail the entire update if Firebase fails
        }
      } else {
        AppLogger.warning('No family code found, skipping Firebase update', tag: 'SettingsScreen');
      }

      _showMessage('설정이 저장되었습니다.');
    } catch (e) {
      AppLogger.error('Error updating settings: $e', tag: 'SettingsScreen');
      _showMessage('설정 저장 중 오류가 발생했습니다: ${e.toString()}');
    }
  }

  Future<void> _updateLocationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'flutter.location_tracking_enabled',
        _locationTrackingEnabled,
      );

      // Update location service
      await LocationService.setLocationTrackingEnabled(
        _locationTrackingEnabled,
      );

      _showMessage('위치 추적 설정이 저장되었습니다.');
    } catch (e) {
      AppLogger.error('Error updating location settings: $e', tag: 'SettingsScreen');
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
      AppLogger.error('Error updating food settings: $e', tag: 'SettingsScreen');
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

                  // Sleep time exclusion setting (only show when survival signal is enabled)
                  if (_survivalSignalEnabled) ...[
                    const SizedBox(height: 16),
                    _buildSleepTimeToggle(),
                    if (_sleepTimeExclusionEnabled) ...[
                      const SizedBox(height: 12),
                      _buildSleepTimeSelector(),
                    ],
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

              // Permission Status Section
              if (_permissionStatus != null) _buildPermissionSection(),
              
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
                      style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '가족과 함께하는 식사 관리',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
        Icon(icon, size: 24, color: const Color(0xFF10B981)),
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
        Icon(icon, size: 24, color: const Color(0xFF10B981)),
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
            Icon(icon, size: 24, color: color),
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
            Icon(Icons.arrow_forward_ios, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepTimeToggle() {
    return _buildToggleItem(
      icon: Icons.bedtime,
      title: '수면 시간 제외',
      subtitle: '잠자는 시간은 모니터링하지 않음',
      value: _sleepTimeExclusionEnabled,
      onChanged: (value) {
        setState(() {
          _sleepTimeExclusionEnabled = value;
          _sleepTimeSettings = _sleepTimeSettings.copyWith(enabled: value);
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          _updateSettings();
        });
      },
    );
  }

  Widget _buildSleepTimeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 20, color: const Color(0xFF10B981)),
              const SizedBox(width: 8),
              const Text(
                '수면 시간 설정',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sleep start and end time
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '잠자는 시간',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _selectTime(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _sleepTimeSettings.sleepStart.format(context),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151),
                              ),
                            ),
                            const Icon(Icons.access_time, size: 20, color: Color(0xFF6B7280)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '일어나는 시간',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _selectTime(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _sleepTimeSettings.sleepEnd.format(context),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151),
                              ),
                            ),
                            const Icon(Icons.access_time, size: 20, color: Color(0xFF6B7280)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Active days
          const Text(
            '활성 요일',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ...[1, 2, 3, 4, 5, 6, 7].asMap().entries.map((entry) {
                final day = entry.value;
                final dayNames = ['월', '화', '수', '목', '금', '토', '일'];
                final isSelected = _sleepTimeSettings.activeDays.contains(day);
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _toggleActiveDay(day),
                    child: Container(
                      margin: EdgeInsets.only(right: entry.key < 6 ? 4 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF10B981) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFFD1D5DB),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          dayNames[day - 1],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),

          const SizedBox(height: 12),

          // Description
          Text(
            '설정된 수면 시간에는 안전 확인 알림이 일시 중지됩니다.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTime(bool isStart) async {
    final currentTime = isStart ? _sleepTimeSettings.sleepStart : _sleepTimeSettings.sleepEnd;
    
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF10B981),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedTime != null) {
      setState(() {
        if (isStart) {
          _sleepTimeSettings = _sleepTimeSettings.copyWith(sleepStart: selectedTime);
        } else {
          _sleepTimeSettings = _sleepTimeSettings.copyWith(sleepEnd: selectedTime);
        }
      });
      
      Future.delayed(const Duration(milliseconds: 300), () {
        _updateSettings();
      });
    }
  }

  void _toggleActiveDay(int day) {
    setState(() {
      final currentDays = List<int>.from(_sleepTimeSettings.activeDays);
      if (currentDays.contains(day)) {
        currentDays.remove(day);
      } else {
        currentDays.add(day);
      }
      currentDays.sort();
      _sleepTimeSettings = _sleepTimeSettings.copyWith(activeDays: currentDays);
    });
    
    Future.delayed(const Duration(milliseconds: 300), () {
      _updateSettings();
    });
  }

  Widget _buildAlertHoursSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 20, color: const Color(0xFF10B981)),
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
            children: [
              ...[3, 6, 12, 24].map((hours) {
                final isSelected = _alertHours == hours && !_useCustomAlertHours;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _alertHours = hours;
                      _useCustomAlertHours = false;
                      _alertHoursController.clear();
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
                      color: isSelected ? const Color(0xFF10B981) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF10B981)
                            : const Color(0xFFD1D5DB),
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF10B981,
                                ).withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Text(
                      '$hours시간',
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
              }),
              // Custom input option
              GestureDetector(
                onTap: () {
                  setState(() {
                    _useCustomAlertHours = true;
                    _alertHoursController.text = _alertHours.toString();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _useCustomAlertHours ? const Color(0xFF10B981) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _useCustomAlertHours
                          ? const Color(0xFF10B981)
                          : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                    boxShadow: _useCustomAlertHours
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    '직접 입력',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _useCustomAlertHours
                          ? Colors.white
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_useCustomAlertHours) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981),
                  width: 2,
                ),
              ),
              child: TextField(
                controller: _alertHoursController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  hintText: '시간 입력 (1-72)',
                  hintStyle: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 14.0,
                  ),
                  suffixText: '시간',
                  suffixStyle: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (value) {
                  final hours = int.tryParse(value);
                  if (hours != null && hours >= 1 && hours <= 72) {
                    setState(() {
                      _alertHours = hours;
                    });
                    // Add slight delay to prevent rapid updates
                    Future.delayed(const Duration(milliseconds: 500), () {
                      _updateSettings();
                    });
                  }
                },
              ),
            ),
          ],

          const SizedBox(height: 12),

          Text(
            '$_alertHours시간 이상 휴대폰을 사용하지 않으면 자녀에게 알림이 전송됩니다.',
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
          subtitle = '위치 정보를 자녀에게 공유 (10분마다)';
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
              bool permissionGranted =
                  await _requestBackgroundLocationPermission();
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

    AppLogger.debug('Background location permission status: $status (granted: $granted)', tag: 'SettingsScreen');
    return granted;
  }

  // Request background location permission with proper two-step flow
  Future<bool> _requestBackgroundLocationPermission() async {
    AppLogger.debug('Starting two-step background location permission flow...', tag: 'SettingsScreen');

    // Step 1: Request foreground location permissions first
    Map<Permission, PermissionStatus> foregroundStatuses = await [
      Permission.locationWhenInUse,
      Permission.location,
    ].request();

    bool foregroundGranted =
        foregroundStatuses[Permission.locationWhenInUse]?.isGranted == true ||
        foregroundStatuses[Permission.location]?.isGranted == true;

    if (!foregroundGranted) {
      AppLogger.warning('Foreground location permission denied', tag: 'SettingsScreen');
      return false;
    }

    AppLogger.debug('Step 1 completed: Foreground location permission granted', tag: 'SettingsScreen');

    // Step 2: Now request background location permission (this shows "Always allow" option)
    await Future.delayed(const Duration(milliseconds: 500));
    PermissionStatus backgroundStatus = await Permission.locationAlways
        .request();

    bool backgroundGranted = backgroundStatus.isGranted;

    if (backgroundGranted) {
      AppLogger.info('SUCCESS: Background location permission GRANTED - "Always allow" was selected!', tag: 'SettingsScreen');
      AppLogger.info('GPS will now work continuously every 2 minutes even when app is killed', tag: 'SettingsScreen');
    } else {
      AppLogger.warning('Background location permission DENIED - user selected "While using app" or denied', tag: 'SettingsScreen');
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
            '앱이 백그라운드에서도 2분마다 위치를 자녀에게 전송할 수 있습니다.',
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

  /// Build permission status section
  Widget _buildPermissionSection() {
    final status = _permissionStatus!;
    
    return _buildSection(
      title: '권한 상태',
      children: [
        // Overall status
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: status.allRequiredGranted
                ? const Color(0xFFDCFDF7)
                : const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: status.allRequiredGranted
                  ? const Color(0xFF10B981)
                  : const Color(0xFFFFE69C),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                status.allRequiredGranted
                    ? Icons.check_circle
                    : Icons.warning_amber_rounded,
                color: status.allRequiredGranted
                    ? const Color(0xFF10B981)
                    : const Color(0xFFB45309),
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.allRequiredGranted
                          ? '모든 권한 설정 완료'
                          : '권한 설정이 필요합니다',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: status.allRequiredGranted
                            ? const Color(0xFF047857)
                            : const Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status.allRequiredGranted
                          ? '안전 확인 알림이 정상 작동합니다'
                          : '${status.missing.length}개의 권한이 필요합니다',
                      style: TextStyle(
                        fontSize: 14,
                        color: status.allRequiredGranted
                            ? const Color(0xFF047857)
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Individual permission status
        ...status.permissions.map((permission) => _buildPermissionStatusItem(permission)),
        
        // Action button for missing permissions
        if (status.missing.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showPermissionGuide(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB45309),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                '권한 설정하기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
        
      ],
    );
  }

  Widget _buildPermissionStatusItem(PermissionInfo permission) {
    IconData icon;
    Color iconColor;
    
    switch (permission.type) {
      case PermissionType.location:
        icon = Icons.my_location_rounded;
        iconColor = const Color(0xFFFF7043);
        break;
      case PermissionType.batteryOptimization:
        icon = Icons.battery_std;
        iconColor = const Color(0xFF10B981);
        break;
      case PermissionType.usageStats:
        icon = Icons.security;
        iconColor = const Color(0xFF3B82F6);
        break;
      case PermissionType.overlay:
        icon = Icons.layers_rounded;
        iconColor = const Color(0xFF8B5CF6);
        break;
      case PermissionType.notifications:
        icon = Icons.notifications_active;
        iconColor = const Color(0xFFF59E0B);
        break;
      default:
        icon = Icons.settings;
        iconColor = const Color(0xFF6B7280);
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: permission.isGranted
              ? const Color(0xFFD1FAE5)
              : const Color(0xFFFED7D7),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permission.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  permission.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: permission.isGranted
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              permission.isGranted ? '허용됨' : '필요함',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (!permission.isGranted)
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: () => _requestSinglePermission(permission),
            ),
        ],
      ),
    );
  }


  void _showPermissionGuide() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxHeight: 600),
          child: SingleChildScrollView(
            child: PermissionGuideWidget(
              showDismissButton: true,
              compactMode: false,
              onAllPermissionsGranted: () {
                Navigator.of(context).pop();
                _loadSettings(); // Refresh settings
                _showMessage('모든 권한이 설정되었습니다!');
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestSinglePermission(PermissionInfo permission) async {
    final granted = await PermissionManagerService.requestPermission(permission.type);
    
    if (granted) {
      _showMessage('권한이 허용되었습니다');
    } else {
      _showMessage('권한 설정을 완료해주세요');
      // Open system settings as fallback
      await PermissionManagerService.openPermissionSettings(permission.type);
    }
    
    // Refresh settings
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadSettings();
  }
}
