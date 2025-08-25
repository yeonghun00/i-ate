import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/screens/guide_screen.dart';
// Settings screen import removed - not used in initial setup
// DataRecoveryScreen removed - using name + connection code only
import 'package:thanks_everyday/screens/account_recovery_screen.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'dart:async';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class InitialSetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const InitialSetupScreen({super.key, required this.onSetupComplete});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _alertHoursController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();

  bool _isLoading = false;
  String? _generatedCode;
  // Temporary display variables removed - not used in current implementation
  bool _survivalSignalEnabled = false;
  int _alertHours = 12; // Default 12 hours
  bool _useCustomAlertHours = false;
  bool _locationTrackingEnabled = false;
  bool _isWaitingForApproval = false;
  int _remainingSeconds = 120; // 2 minutes countdown
  StreamSubscription? _approvalSubscription;
  Timer? _pollingTimer;
  Timer? _timeoutTimer;
  Timer? _countdownTimer;

  Future<void> _setupFamily() async {
    if (_nameController.text.trim().isEmpty) {
      _showMessage('이름을 입력해주세요');
      return;
    }

    // Contact is optional, so we don't check if it's empty

    setState(() {
      _isLoading = true;
    });

    try {
      // Generate code and save to Firebase immediately
      final generatedCode = await _firebaseService.setupFamilyCode(
        _nameController.text.trim(),
      );

      if (generatedCode != null) {
        // Update Firebase settings with correct alert hours
        AppLogger.info('Saving alert hours to Firebase: $_alertHours', tag: 'InitialSetupScreen');
        final settingsUpdated = await _firebaseService.updateFamilySettings(
          survivalSignalEnabled: _survivalSignalEnabled,
          familyContact: '',
          alertHours: _alertHours,
        );
        
        if (!settingsUpdated) {
          AppLogger.error('Failed to save settings to Firebase', tag: 'InitialSetupScreen');
        }

        // Save only essential settings to SharedPreferences (Firebase is primary source for alert hours)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(
          'flutter.survival_signal_enabled',
          _survivalSignalEnabled,
        );
        await prefs.setBool(
          'flutter.location_tracking_enabled',
          _locationTrackingEnabled,
        );
        // Note: alert_hours is now stored in Firebase only

        // Family data is now stored directly in Firebase - no temporary storage needed

        setState(() {
          _generatedCode = generatedCode;
          _isWaitingForApproval = true;
        });

        // Start listening for approval from child app
        _startListeningForApproval();

        // Also start polling as backup
        _startPollingForApproval();

        // Start 2-minute timeout timer and countdown
        _startTimeoutTimer();
        _startCountdownTimer();
      } else {
        _showMessage('설정에 실패했습니다. 다시 시도해주세요.');
      }
    } catch (e) {
      _showMessage('오류가 발생했습니다: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startListeningForApproval() {
    if (_generatedCode == null) return;

    AppLogger.info('Starting to listen for approval for code: $_generatedCode', tag: 'InitialSetupScreen');

    // Listen to Firebase for approval changes with error handling
    _approvalSubscription = _firebaseService
        .listenForApproval(_generatedCode!)
        .listen(
          (approved) {
            AppLogger.info('Approval status changed: $approved', tag: 'InitialSetupScreen');

            if (mounted) {
              if (approved == true) {
                // Approved by child app - proceed immediately
                AppLogger.info('Approved! Proceeding to guide...', tag: 'InitialSetupScreen');

                // Cancel all timers immediately
                _approvalSubscription?.cancel();
                _pollingTimer?.cancel();
                _timeoutTimer?.cancel();
                _countdownTimer?.cancel();

                setState(() {
                  _isWaitingForApproval = false;
                  _isLoading = true;
                });

                _showMessage('자녀가 승인했습니다! 앱을 시작합니다.');

                // Navigate immediately without delay
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) =>
                          GuideScreen(onGuideComplete: widget.onSetupComplete),
                    ),
                  );
                }
              } else if (approved == false) {
                // Rejected by child app - reset
                AppLogger.info('Rejected! Resetting setup...', tag: 'InitialSetupScreen');

                setState(() {
                  _isWaitingForApproval = false;
                });

                _showMessage('자녀가 거부했습니다. 다시 설정해주세요.');
                _resetSetup();
              }
            }
          },
          onError: (error) {
            AppLogger.error('Error listening for approval: $error', tag: 'InitialSetupScreen');
            if (mounted) {
              _showMessage('연결 오류가 발생했습니다. 다시 시도해주세요.');
            }
          },
        );
  }

  // Manual refresh function
  Future<void> _refreshApprovalStatus() async {
    if (_generatedCode == null) return;

    try {
      final familyInfo = await _firebaseService.getFamilyInfo(_generatedCode!);
      if (familyInfo != null) {
        final approved = familyInfo['approved'] as bool?;
        AppLogger.debug('Manual refresh - approved: $approved', tag: 'InitialSetupScreen');

        if (mounted) {
          if (approved == true) {
            _approvalSubscription?.cancel();
            _pollingTimer?.cancel();
            _timeoutTimer?.cancel();
            _countdownTimer?.cancel();

            setState(() {
              _isWaitingForApproval = false;
              _isLoading = true;
            });

            _showMessage('자녀가 승인했습니다! 앱을 시작합니다.');

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    GuideScreen(onGuideComplete: widget.onSetupComplete),
              ),
            );
          } else if (approved == false) {
            setState(() {
              _isWaitingForApproval = false;
            });

            _showMessage('자녀가 거부했습니다. 다시 설정해주세요.');
            _resetSetup();
          }
        }
      }
    } catch (e) {
      AppLogger.error('Manual refresh error: $e', tag: 'InitialSetupScreen');
    }
  }

  void _startPollingForApproval() {
    if (_generatedCode == null) return;

    // Poll every 500ms for faster response
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      if (!_isWaitingForApproval || _generatedCode == null) {
        timer.cancel();
        return;
      }

      try {
        final familyInfo = await _firebaseService.getFamilyInfo(
          _generatedCode!,
        );
        if (familyInfo != null) {
          final approved = familyInfo['approved'] as bool?;
          AppLogger.debug('Polling check - approved: $approved', tag: 'InitialSetupScreen');

          if (approved != null && mounted) {
            if (approved == true) {
              timer.cancel();
              _approvalSubscription?.cancel();
              _timeoutTimer?.cancel();
              _countdownTimer?.cancel();

              setState(() {
                _isWaitingForApproval = false;
                _isLoading = true;
              });

              _showMessage('자녀가 승인했습니다! 앱을 시작합니다.');

              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) =>
                      GuideScreen(onGuideComplete: widget.onSetupComplete),
                ),
              );
            } else if (approved == false) {
              timer.cancel();
              _timeoutTimer?.cancel();
              _countdownTimer?.cancel();
              setState(() {
                _isWaitingForApproval = false;
              });

              _showMessage('자녀가 거부했습니다. 다시 설정해주세요.');
              _resetSetup();
            }
          }
        }
      } catch (e) {
        AppLogger.error('Polling error: $e', tag: 'InitialSetupScreen');
      }
    });
  }

  void _startTimeoutTimer() {
    // 2-minute timeout - if no approval, delete from Firebase and reset
    _timeoutTimer = Timer(const Duration(minutes: 2), () async {
      if (_isWaitingForApproval && _generatedCode != null) {
        AppLogger.warning('Timeout reached - no approval after 2 minutes', tag: 'InitialSetupScreen');

        // Cancel all listeners
        _approvalSubscription?.cancel();
        _pollingTimer?.cancel();
        _countdownTimer?.cancel();

        // Delete from Firebase
        try {
          await _firebaseService.deleteFamilyCode(_generatedCode!);
          AppLogger.info('Family code $_generatedCode deleted due to timeout', tag: 'InitialSetupScreen');
        } catch (e) {
          AppLogger.error('Failed to delete family code on timeout: $e', tag: 'InitialSetupScreen');
        }

        // Reset UI
        if (mounted) {
          setState(() {
            _isWaitingForApproval = false;
            _generatedCode = null;
            // Temporary variables removed
            _nameController.clear();
            _survivalSignalEnabled = false;
            _alertHours = 12;
            _locationTrackingEnabled = false;
          });

          _showMessage('연결 시간이 초과되었습니다. 다시 설정해주세요.');
        }
      }
    });
  }

  void _startCountdownTimer() {
    _remainingSeconds = 120; // Reset to 2 minutes
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
        });

        if (_remainingSeconds <= 0) {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _resetSetup() async {
    // Cancel all timers
    _approvalSubscription?.cancel();
    _pollingTimer?.cancel();
    _timeoutTimer?.cancel();
    _countdownTimer?.cancel();

    // Delete from Firebase
    if (_generatedCode != null) {
      try {
        await _firebaseService.deleteFamilyCode(_generatedCode!);
        AppLogger.info('Family code $_generatedCode deleted by user reset', tag: 'InitialSetupScreen');
      } catch (e) {
        AppLogger.error('Failed to delete family code: $e', tag: 'InitialSetupScreen');
      }
    }

    // Reset UI
    setState(() {
      _generatedCode = null;
      // Temporary variables removed
      _nameController.clear();
      _survivalSignalEnabled = false;
      _alertHours = 12;
      _locationTrackingEnabled = false;
      _isWaitingForApproval = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _navigateToAccountRecovery() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            AccountRecoveryScreen(onRecoveryComplete: widget.onSetupComplete),
      ),
    );
  }

  // Data recovery with 8-digit codes removed - using name + connection code only

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child:
              // Main content
              SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    if (_generatedCode != null) ...[
                      // Show generated code
                      const Text(
                        '가족 코드가 생성되었습니다!',
                        style: TextStyle(
                          fontSize: 28.0,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 30),

                      Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              '가족 코드',
                              style: TextStyle(
                                fontSize: 20.0,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 15),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Text(
                                _generatedCode!,
                                style: const TextStyle(
                                  fontSize: 64.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 25),

                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              _isWaitingForApproval
                                  ? '📱 자녀 앱에서 승인을 기다리고 있습니다'
                                  : '💡 이 코드를 자녀 앱에 입력해주세요',
                              style: const TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isWaitingForApproval
                                  ? '자녀가 코드를 입력하고 승인하면 앱이 시작됩니다.'
                                  : '자녀가 이 코드로 당신의 감사 이야기를 들을 수 있습니다.',
                              style: const TextStyle(
                                fontSize: 16.0,
                                color: AppTheme.textLight,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            // Countdown timer (only show when waiting for approval)
                            if (_isWaitingForApproval) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFEF4444,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFEF4444,
                                    ).withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer,
                                      size: 16,
                                      color: AppTheme.errorRed,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${(_remainingSeconds / 60).floor()}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.errorRed,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            if (_isWaitingForApproval) ...[
                              const SizedBox(height: 12),
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryGreen,
                                ),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: _refreshApprovalStatus,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppTheme.primaryGreen,
                                      width: 1,
                                    ),
                                  ),
                                  child: const Text(
                                    '새로고침',
                                    style: TextStyle(
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // Show continue button only when not waiting for approval
                      if (!_isWaitingForApproval) ...[
                        // Continue button (hidden for now as we wait for approval)
                        Container(
                          width: double.infinity,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(35),
                            color: AppTheme.borderLight,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              '자녀 앱 승인 대기 중',
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDisabled,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Try again button
                      GestureDetector(
                        onTap: _resetSetup,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Text(
                            '다시 설정하기',
                            style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textLight,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
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
                        child: Column(
                          children: [
                            const Text(
                              '식사하셨어요?',
                              style: TextStyle(
                                fontSize: 32.0,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '부모님이 건강하게 잘 계시는지 확인하는 앱',
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textMedium,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.primaryGreen.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                '⚙️ 딱 한 번만 설정하면 됩니다',
                                style: TextStyle(
                                  fontSize: 14.0,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Name input
                      _buildInputField(
                        controller: _nameController,
                        label: '👤 사용자 이름',
                        hint: '김할머니',
                        icon: Icons.person,
                      ),

                      const SizedBox(height: 30),

                      // Settings section
                      Container(
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
                            const Text(
                              '기능 설정',
                              style: TextStyle(
                                fontSize: 20.0,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary,
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Meal tracking info
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundCard,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.restaurant_rounded,
                                    color: AppTheme.primaryGreen,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      '식사하셨어요? 앱으로 하루 3번의 식사를 기록할 수 있습니다. ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.textMedium,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 15),

                            // Location tracking toggle
                            _buildToggleOption(
                              title: 'GPS 위치 추적',
                              subtitle: '위치 정보를 자녀에게 공유',
                              value: _locationTrackingEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _locationTrackingEnabled = value;
                                });
                              },
                            ),

                            const SizedBox(height: 15),

                            // Survival signal toggle
                            _buildToggleOption(
                              title: '안전 알림 서비스',
                              subtitle: '휴대폰 사용 여부를 자녀에게 알림',
                              value: _survivalSignalEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _survivalSignalEnabled = value;
                                });
                              },
                            ),

                            if (_survivalSignalEnabled) ...[
                              const SizedBox(height: 15),

                              // Alert time selector
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.backgroundCard,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '알림 시간 설정',
                                      style: TextStyle(
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textMedium,
                                      ),
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
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? const Color(0xFF10B981)
                                                    : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFFD1D5DB),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                '$hours시간',
                                                style: TextStyle(
                                                  fontSize: 14.0,
                                                  fontWeight: FontWeight.w500,
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
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _useCustomAlertHours
                                                  ? const Color(0xFF10B981)
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: _useCustomAlertHours
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFFD1D5DB),
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              '직접 입력',
                                              style: TextStyle(
                                                fontSize: 14.0,
                                                fontWeight: FontWeight.w500,
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
                                            }
                                          },
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 12),

                                    Text(
                                      '$_alertHours시간 이상 휴대폰을 사용하지 않으면 자녀에게 알림이 전송됩니다.',
                                      style: const TextStyle(
                                        fontSize: 14.0,
                                        color: AppTheme.textLight,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Setup button
                      GestureDetector(
                        onTap: _isLoading ? null : _setupFamily,
                        child: Container(
                          width: double.infinity,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(35),
                            gradient: AppTheme.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryGreen.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  )
                                : const Text(
                                    '설정 완료',
                                    style: TextStyle(
                                      fontSize: 22.0,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Account recovery option
                      TextButton(
                        onPressed: _navigateToAccountRecovery,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryGreen.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_search_rounded,
                                color: AppTheme.primaryGreen,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '이미 계정이 있어요',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 16.0,
              ),
              prefixIcon: Icon(icon, color: AppTheme.primaryGreen),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleOption({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14.0,
                  color: Color(0xFF6B7280),
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
    );
  }

  @override
  void dispose() {
    _approvalSubscription?.cancel();
    _pollingTimer?.cancel();
    _timeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _nameController.dispose();
    _alertHoursController.dispose();
    super.dispose();
  }
}
