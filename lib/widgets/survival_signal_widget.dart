import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/services/firebase_service.dart';

class SurvivalSignalWidget extends StatefulWidget {
  const SurvivalSignalWidget({super.key});

  @override
  State<SurvivalSignalWidget> createState() => _SurvivalSignalWidgetState();
}

class _SurvivalSignalWidgetState extends State<SurvivalSignalWidget> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _survivalSignalEnabled = false;
  int _alertThresholdHours = 12;
  int _hoursSinceActivity = 0;
  DateTime? _lastPhoneActivity;
  bool _isLoading = true;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _setupFirebaseListener();
    _startUpdateTimer();
  }
  
  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newSurvivalEnabled = prefs.getBool('flutter.survival_signal_enabled') ?? false;
      final newAlertHours = prefs.getInt('alert_hours') ?? 12;
      
      setState(() {
        _survivalSignalEnabled = newSurvivalEnabled;
        _alertThresholdHours = newAlertHours;
      });
      
      // Recalculate hours since activity with new threshold
      if (_lastPhoneActivity != null) {
        final now = DateTime.now();
        final hoursSince = now.difference(_lastPhoneActivity!).inHours;
        setState(() {
          _hoursSinceActivity = hoursSince;
        });
      }
    } catch (e) {
      print('Failed to load survival signal settings: $e');
    }
  }

  void _startUpdateTimer() {
    // Update the hours calculation every minute to keep colors current
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_lastPhoneActivity != null && mounted) {
        final now = DateTime.now();
        final hoursSince = now.difference(_lastPhoneActivity!).inHours;
        
        if (hoursSince != _hoursSinceActivity) {
          setState(() {
            _hoursSinceActivity = hoursSince;
          });
        }
      }
    });
  }

  void _setupFirebaseListener() {
    if (!_firebaseService.isSetup) return;

    try {
      FirebaseFirestore.instance
          .collection('families')
          .doc(_firebaseService.familyId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          final data = snapshot.data();
          final lastPhoneActivityTimestamp = data?['lastPhoneActivity'] as Timestamp?;
          
          if (lastPhoneActivityTimestamp != null) {
            final lastActivity = lastPhoneActivityTimestamp.toDate();
            final now = DateTime.now();
            final hoursSince = now.difference(lastActivity).inHours;
            
            setState(() {
              _lastPhoneActivity = lastActivity;
              _hoursSinceActivity = hoursSince;
              _isLoading = false;
            });
          } else {
            setState(() {
              _lastPhoneActivity = null;
              _hoursSinceActivity = 999; // Indicate no data
              _isLoading = false;
            });
          }
        }
      });
    } catch (e) {
      print('Failed to setup Firebase listener for survival signal: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show widget if survival signal is disabled
    if (!_survivalSignalEnabled) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.health_and_safety,
                size: 20,
                color: AppTheme.primaryGreen,
              ),
              const SizedBox(width: 8),
              const Text(
                '안전 신호',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                )
              else
                _buildStatusIndicator(),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Status details
          if (!_isLoading) ...[
            _buildStatusDetails(),
            const SizedBox(height: 8),
            _buildLastActivityInfo(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final color = _lastPhoneActivity != null 
        ? AppTheme.getSurvivalSignalColor(_hoursSinceActivity, _alertThresholdHours)
        : AppTheme.survivalAlert;
    
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDetails() {
    if (_lastPhoneActivity == null) {
      return const Row(
        children: [
          Icon(
            Icons.help_outline,
            size: 16,
            color: AppTheme.textLight,
          ),
          SizedBox(width: 6),
          Text(
            '활동 데이터 없음',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textLight,
            ),
          ),
        ],
      );
    }

    final statusColor = AppTheme.getSurvivalSignalColor(_hoursSinceActivity, _alertThresholdHours);
    final statusText = AppTheme.getSurvivalSignalStatus(_hoursSinceActivity, _alertThresholdHours);
    
    IconData statusIcon;
    if (_hoursSinceActivity >= _alertThresholdHours) {
      statusIcon = Icons.warning;
    } else if (_hoursSinceActivity >= (_alertThresholdHours - 1)) {
      statusIcon = Icons.info_outline;
    } else {
      statusIcon = Icons.check_circle_outline;
    }

    return Row(
      children: [
        Icon(
          statusIcon,
          size: 16,
          color: statusColor,
        ),
        const SizedBox(width: 6),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '($_hoursSinceActivity시간 전)',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textLight,
          ),
        ),
      ],
    );
  }

  Widget _buildLastActivityInfo() {
    if (_lastPhoneActivity == null) {
      return Text(
        '알림 기준: $_alertThresholdHours시간',
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.textLight,
        ),
      );
    }

    final timeString = _formatTime(_lastPhoneActivity!);
    final warningTime = _alertThresholdHours - 1;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '마지막 활동: $timeString',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textLight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '주의: $warningTime시간 • 알림: $_alertThresholdHours시간',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textLight,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }
}