import 'package:thanks_everyday/theme/app_theme.dart';

class ActivityStatusCalculator {
  static ActivityStatus calculateStatus({
    DateTime? lastActivity,
    required int alertThresholdHours,
  }) {
    if (lastActivity == null) {
      return ActivityStatus.noData;
    }

    final hoursSince = DateTime.now().difference(lastActivity).inHours;
    
    if (hoursSince >= alertThresholdHours) {
      return ActivityStatus.alert;
    } else if (hoursSince >= (alertThresholdHours - 1)) {
      return ActivityStatus.warning;
    } else {
      return ActivityStatus.normal;
    }
  }

  static String getStatusText(ActivityStatus status, int hoursSince, int threshold) {
    switch (status) {
      case ActivityStatus.normal:
        return '정상 활동 중';
      case ActivityStatus.warning:
        return '주의 필요';
      case ActivityStatus.alert:
        return '알림 필요';
      case ActivityStatus.noData:
        return '활동 데이터 없음';
    }
  }

  static String formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return '없음';
    
    final difference = DateTime.now().difference(dateTime);
    
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

enum ActivityStatus {
  normal,
  warning, 
  alert,
  noData
}