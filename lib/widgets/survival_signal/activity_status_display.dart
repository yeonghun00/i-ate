import 'package:flutter/material.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/widgets/survival_signal/activity_status_calculator.dart';

class ActivityStatusDisplay extends StatelessWidget {
  final ActivityStatus status;
  final int hoursSinceActivity;
  final int alertThresholdHours;
  final DateTime? lastActivity;

  const ActivityStatusDisplay({
    super.key,
    required this.status,
    required this.hoursSinceActivity,
    required this.alertThresholdHours,
    required this.lastActivity,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusRow(),
        const SizedBox(height: 8),
        _buildActivityInfo(),
      ],
    );
  }

  Widget _buildStatusRow() {
    if (status == ActivityStatus.noData) {
      return const Row(
        children: [
          Icon(Icons.help_outline, size: 16, color: AppTheme.textLight),
          SizedBox(width: 6),
          Text(
            '활동 데이터 없음',
            style: TextStyle(fontSize: 14, color: AppTheme.textLight),
          ),
        ],
      );
    }

    final statusColor = _getStatusColor();
    final statusText = ActivityStatusCalculator.getStatusText(
      status,
      hoursSinceActivity,
      alertThresholdHours,
    );

    return Row(
      children: [
        Icon(_getStatusIcon(), size: 16, color: statusColor),
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
          '($hoursSinceActivity시간 전)',
          style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
        ),
      ],
    );
  }

  Widget _buildActivityInfo() {
    if (status == ActivityStatus.noData) {
      return Text(
        '알림 기준: $alertThresholdHours시간',
        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
      );
    }

    final timeString = ActivityStatusCalculator.formatTimeAgo(lastActivity);
    final warningTime = alertThresholdHours - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '마지막 활동: $timeString',
          style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
        ),
        const SizedBox(height: 2),
        Text(
          '주의: $warningTime시간 • 알림: $alertThresholdHours시간',
          style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
        ),
      ],
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case ActivityStatus.normal:
        return AppTheme.primaryGreen;
      case ActivityStatus.warning:
        return AppTheme.survivalWarning;
      case ActivityStatus.alert:
        return AppTheme.errorRed;
      case ActivityStatus.noData:
        return AppTheme.textLight;
    }
  }

  IconData _getStatusIcon() {
    switch (status) {
      case ActivityStatus.normal:
        return Icons.check_circle_outline;
      case ActivityStatus.warning:
        return Icons.info_outline;
      case ActivityStatus.alert:
        return Icons.warning;
      case ActivityStatus.noData:
        return Icons.help_outline;
    }
  }
}
