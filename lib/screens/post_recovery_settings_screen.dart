import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/screens/special_permission_guide_screen.dart';
import 'package:thanks_everyday/models/sleep_time_settings.dart';
import 'package:thanks_everyday/services/firebase_service.dart';

/// Screen shown after account recovery to let user re-enable monitoring settings
/// This addresses the issue that local settings are lost during reinstall
class PostRecoverySettingsScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const PostRecoverySettingsScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<PostRecoverySettingsScreen> createState() => _PostRecoverySettingsScreenState();
}

class _PostRecoverySettingsScreenState extends State<PostRecoverySettingsScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  bool _survivalSignalEnabled = true;  // Default to enabled
  bool _locationTrackingEnabled = true; // Default to enabled
  bool _sleepTimeExclusionEnabled = false;
  SleepTimeSettings _sleepTimeSettings = SleepTimeSettings.defaultSettings();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                // Success icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 64,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                const Text(
                  '계정 복구 완료!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Settings section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '모니터링 기능 설정',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Survival signal toggle
                      _buildSettingToggle(
                        icon: Icons.health_and_safety,
                        title: '안전 확인 알림',
                        subtitle: '휴대폰 사용이 없으면 자녀에게 알림',
                        value: _survivalSignalEnabled,
                        onChanged: (value) {
                          setState(() {
                            _survivalSignalEnabled = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      // Location tracking toggle
                      _buildSettingToggle(
                        icon: Icons.location_on_rounded,
                        title: 'GPS 위치 추적',
                        subtitle: '15분마다 위치를 자녀에게 공유',
                        value: _locationTrackingEnabled,
                        onChanged: (value) {
                          setState(() {
                            _locationTrackingEnabled = value;
                          });
                        },
                      ),

                      // Sleep time exclusion toggle (only show when survival signal is enabled)
                      if (_survivalSignalEnabled) ...[
                        const SizedBox(height: 16),
                        _buildSettingToggle(
                          icon: Icons.bedtime_rounded,
                          title: '수면 시간 제외',
                          subtitle: '잠자는 시간은 모니터링하지 않음',
                          value: _sleepTimeExclusionEnabled,
                          onChanged: (value) {
                            setState(() {
                              _sleepTimeExclusionEnabled = value;
                              if (value) {
                                _sleepTimeSettings = _sleepTimeSettings.copyWith(enabled: true);
                              }
                            });
                          },
                        ),

                        if (_sleepTimeExclusionEnabled) ...[
                          const SizedBox(height: 16),
                          _buildSleepTimeSelector(),
                        ],
                      ],

                      const SizedBox(height: 20),

                      // Info text
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: AppTheme.primaryGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '나중에 설정 화면에서 변경할 수 있습니다',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textMedium,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveSettingsAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            '계속하기',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Skip button
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _skipAndContinue,
                    child: Text(
                      '지금은 건너뛰기',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textMedium,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? AppTheme.primaryGreen.withValues(alpha: 0.3) : Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: value ? AppTheme.primaryGreen : Colors.grey,
              size: 24,
            ),
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
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMedium,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primaryGreen,
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettingsAndContinue() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // CRITICAL: Save settings to Firebase first (cloud storage)
      // This ensures child app can see the updated settings
      final sleepSettings = _sleepTimeExclusionEnabled ? _sleepTimeSettings.toMap() : null;

      AppLogger.info('Saving settings to Firebase...', tag: 'PostRecoverySettings');
      final settingsUpdated = await _firebaseService.updateFamilySettings(
        survivalSignalEnabled: _survivalSignalEnabled,
        familyContact: '',
        alertHours: null, // Keep existing alertHours from Firebase
        sleepTimeSettings: sleepSettings,
      );

      if (!settingsUpdated) {
        AppLogger.error('Failed to save settings to Firebase', tag: 'PostRecoverySettings');
        throw Exception('Firebase 설정 업데이트 실패');
      }

      // Save settings to local storage (SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flutter.survival_signal_enabled', _survivalSignalEnabled);
      await prefs.setBool('flutter.location_tracking_enabled', _locationTrackingEnabled);

      // Save sleep time exclusion settings locally
      await prefs.setBool('flutter.sleep_exclusion_enabled', _sleepTimeExclusionEnabled);
      if (_sleepTimeExclusionEnabled) {
        final sleepSettingsMap = _sleepTimeSettings.toMap();
        await prefs.setInt('flutter.sleep_start_hour', sleepSettingsMap['sleepStartHour']);
        await prefs.setInt('flutter.sleep_start_minute', sleepSettingsMap['sleepStartMinute']);
        await prefs.setInt('flutter.sleep_end_hour', sleepSettingsMap['sleepEndHour']);
        await prefs.setInt('flutter.sleep_end_minute', sleepSettingsMap['sleepEndMinute']);
        await prefs.setString('flutter.sleep_active_days', sleepSettingsMap['activeDays'].join(','));
      }

      AppLogger.info(
        'Post-recovery settings saved successfully: survival=$_survivalSignalEnabled, location=$_locationTrackingEnabled, sleep=$_sleepTimeExclusionEnabled',
        tag: 'PostRecoverySettings',
      );

      // Navigate to permission setup
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => SpecialPermissionGuideScreen(
              onPermissionsComplete: widget.onComplete,
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to save post-recovery settings: $e', tag: 'PostRecoverySettings');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('설정 저장 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _skipAndContinue() async {
    // Don't save any settings, just continue to permissions
    AppLogger.info('User skipped post-recovery settings', tag: 'PostRecoverySettings');

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SpecialPermissionGuideScreen(
            onPermissionsComplete: widget.onComplete,
          ),
        ),
      );
    }
  }

  Widget _buildSleepTimeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 20, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              const Text(
                '수면 시간 설정',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMedium,
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
                        color: AppTheme.textMedium,
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
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const Icon(Icons.access_time, size: 20, color: AppTheme.textLight),
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
                        color: AppTheme.textMedium,
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
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const Icon(Icons.access_time, size: 20, color: AppTheme.textLight),
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
              color: AppTheme.textMedium,
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
                        color: isSelected ? AppTheme.primaryGreen : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? AppTheme.primaryGreen : const Color(0xFFD1D5DB),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          dayNames[day - 1],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : AppTheme.textLight,
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '설정된 수면 시간에는 안전 확인 알림이 일시 중지됩니다.',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMedium,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
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
  }

  Future<void> _selectTime(bool isStartTime) async {
    final initialTime = isStartTime
        ? _sleepTimeSettings.sleepStart
        : _sleepTimeSettings.sleepEnd;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppTheme.primaryGreen,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _sleepTimeSettings = _sleepTimeSettings.copyWith(sleepStart: picked);
        } else {
          _sleepTimeSettings = _sleepTimeSettings.copyWith(sleepEnd: picked);
        }
      });
    }
  }
}
