import 'package:flutter/material.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/storage/local_storage_manager.dart';
import 'package:thanks_everyday/widgets/survival_signal/activity_data_listener.dart';
import 'package:thanks_everyday/widgets/survival_signal/activity_status_calculator.dart';
import 'package:thanks_everyday/widgets/survival_signal/activity_status_display.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class SurvivalSignalWidget extends StatefulWidget {
  const SurvivalSignalWidget({super.key});

  @override
  State<SurvivalSignalWidget> createState() => _SurvivalSignalWidgetState();
}

class _SurvivalSignalWidgetState extends State<SurvivalSignalWidget> {
  final FirebaseService _firebaseService = FirebaseService();
  final LocalStorageManager _storage = LocalStorageManager();
  late final ActivityDataListener _activityListener;
  bool _survivalSignalEnabled = false;
  int _alertThresholdHours = 12;

  @override
  void initState() {
    super.initState();
    _activityListener = ActivityDataListener(_firebaseService);
    _loadSettings();
  }
  
  @override
  void dispose() {
    _activityListener.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final survivalEnabled = await _storage.getString('flutter.survival_signal_enabled');
      final alertHours = await _storage.getString('alert_hours');
      
      setState(() {
        _survivalSignalEnabled = survivalEnabled == 'true';
        _alertThresholdHours = int.tryParse(alertHours ?? '12') ?? 12;
      });
    } catch (e) {
      AppLogger.error('Failed to load survival signal settings: $e', tag: 'SurvivalSignalWidget');
    }
  }

  @override
  Widget build(BuildContext context) {
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
          _buildHeader(),
          const SizedBox(height: 12),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
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
        StreamBuilder<ActivityData>(
          stream: _activityListener.activityStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isLoading) {
              return const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                ),
              );
            }
            
            return _buildStatusIndicator(snapshot.data!);
          },
        ),
      ],
    );
  }

  Widget _buildContent() {
    return StreamBuilder<ActivityData>(
      stream: _activityListener.activityStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isLoading) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final status = ActivityStatusCalculator.calculateStatus(
          lastActivity: data.lastActivity,
          alertThresholdHours: _alertThresholdHours,
        );

        return ActivityStatusDisplay(
          status: status,
          hoursSinceActivity: data.hoursSinceActivity,
          alertThresholdHours: _alertThresholdHours,
          lastActivity: data.lastActivity,
        );
      },
    );
  }

  Widget _buildStatusIndicator(ActivityData data) {
    final status = ActivityStatusCalculator.calculateStatus(
      lastActivity: data.lastActivity,
      alertThresholdHours: _alertThresholdHours,
    );

    Color color;
    switch (status) {
      case ActivityStatus.normal:
        color = AppTheme.primaryGreen;
        break;
      case ActivityStatus.warning:
        color = AppTheme.warningYellow;
        break;
      case ActivityStatus.alert:
        color = AppTheme.errorRed;
        break;
      case ActivityStatus.noData:
        color = AppTheme.textLight;
        break;
    }
    
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
}