import 'package:flutter/material.dart';
import 'package:thanks_everyday/models/sleep_time_settings.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class SleepTimeCalculator {
  static const String tag = 'SleepTimeCalculator';

  /// Check if the current time falls within sleep period
  static bool isCurrentlySleepTime(SleepTimeSettings settings) {
    if (!settings.enabled) {
      AppLogger.debug('Sleep exclusion disabled', tag: tag);
      return false;
    }

    final now = DateTime.now();
    final currentTime = TimeOfDay.fromDateTime(now);
    final currentWeekday = now.weekday; // 1=Monday, 7=Sunday

    // Check if today is an active day
    if (!settings.activeDays.contains(currentWeekday)) {
      AppLogger.debug('Today ($currentWeekday) is not an active sleep day', tag: tag);
      return false;
    }

    final isSleepTime = _isTimeInSleepPeriod(currentTime, settings.sleepStart, settings.sleepEnd);
    
    AppLogger.debug(
      'Sleep time check: ${currentTime.format24Hour()} is ${isSleepTime ? "SLEEP" : "AWAKE"} '
      '(${settings.sleepStart.format24Hour()}-${settings.sleepEnd.format24Hour()})',
      tag: tag,
    );

    return isSleepTime;
  }

  /// Calculate how much "awake time" has passed between two DateTime points,
  /// excluding sleep periods
  static Duration calculateAwakeTimeBetween(
    DateTime startTime,
    DateTime endTime,
    SleepTimeSettings settings,
  ) {
    if (!settings.enabled) {
      return endTime.difference(startTime);
    }

    AppLogger.debug(
      'Calculating awake time from ${startTime.toIso8601String()} to ${endTime.toIso8601String()}',
      tag: tag,
    );

    Duration totalAwakeTime = Duration.zero;
    DateTime currentDay = DateTime(startTime.year, startTime.month, startTime.day);
    final endDay = DateTime(endTime.year, endTime.month, endTime.day);

    while (currentDay.isBefore(endDay) || currentDay.isAtSameMomentAs(endDay)) {
      final dayStart = currentDay.isBefore(DateTime(startTime.year, startTime.month, startTime.day))
          ? currentDay
          : startTime;
      
      final dayEnd = currentDay.isAtSameMomentAs(endDay)
          ? endTime
          : currentDay.add(const Duration(days: 1));

      final awakeTimeInDay = _calculateAwakeTimeInDay(dayStart, dayEnd, settings, currentDay.weekday);
      totalAwakeTime += awakeTimeInDay;

      AppLogger.debug(
        'Day ${currentDay.day}: awake time = ${awakeTimeInDay.inMinutes} minutes',
        tag: tag,
      );

      currentDay = currentDay.add(const Duration(days: 1));
    }

    AppLogger.debug(
      'Total awake time: ${totalAwakeTime.inHours}h ${totalAwakeTime.inMinutes % 60}m',
      tag: tag,
    );

    return totalAwakeTime;
  }

  /// Calculate awake time within a single day
  static Duration _calculateAwakeTimeInDay(
    DateTime dayStart,
    DateTime dayEnd,
    SleepTimeSettings settings,
    int weekday,
  ) {
    if (!settings.activeDays.contains(weekday)) {
      // No sleep exclusion on this day, entire period counts as awake
      return dayEnd.difference(dayStart);
    }

    final startOfDay = DateTime(dayStart.year, dayStart.month, dayStart.day);
    final endOfDay = DateTime(dayStart.year, dayStart.month, dayStart.day, 23, 59, 59);

    // Convert sleep times to DateTime for this day
    final sleepStartDateTime = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      settings.sleepStart.hour,
      settings.sleepStart.minute,
    );

    final sleepEndDateTime = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day + (settings.sleepEnd.totalMinutes < settings.sleepStart.totalMinutes ? 1 : 0),
      settings.sleepEnd.hour,
      settings.sleepEnd.minute,
    );

    // Find the intersection of our time period with the awake periods
    Duration awakeTime = Duration.zero;

    if (sleepStartDateTime.isAfter(sleepEndDateTime)) {
      // Overnight sleep (e.g., 22:00 - 06:00)
      // Awake periods: start of day to sleep start, sleep end to end of day
      
      // Period 1: dayStart to sleepStart (if applicable)
      if (dayStart.isBefore(sleepStartDateTime) && dayEnd.isAfter(startOfDay)) {
        final periodEnd = dayEnd.isBefore(sleepStartDateTime) ? dayEnd : sleepStartDateTime;
        awakeTime += periodEnd.difference(dayStart);
      }

      // Period 2: sleepEnd to dayEnd (if applicable)
      if (dayStart.isBefore(sleepEndDateTime) && dayEnd.isAfter(sleepEndDateTime)) {
        final periodStart = dayStart.isAfter(sleepEndDateTime) ? dayStart : sleepEndDateTime;
        awakeTime += dayEnd.difference(periodStart);
      }
    } else {
      // Same-day sleep (e.g., 14:00 - 16:00 nap)
      // Sleep period is within the same day
      
      if (dayEnd.isBefore(sleepStartDateTime) || dayStart.isAfter(sleepEndDateTime)) {
        // No overlap with sleep period
        awakeTime = dayEnd.difference(dayStart);
      } else {
        // There is overlap with sleep period
        if (dayStart.isBefore(sleepStartDateTime)) {
          awakeTime += sleepStartDateTime.difference(dayStart);
        }
        if (dayEnd.isAfter(sleepEndDateTime)) {
          awakeTime += dayEnd.difference(sleepEndDateTime);
        }
      }
    }

    return awakeTime;
  }

  /// Check if a given time falls within sleep period (handles overnight periods)
  static bool _isTimeInSleepPeriod(TimeOfDay currentTime, TimeOfDay sleepStart, TimeOfDay sleepEnd) {
    if (sleepStart.totalMinutes > sleepEnd.totalMinutes) {
      // Overnight period (e.g., 22:00 - 06:00)
      return currentTime.totalMinutes >= sleepStart.totalMinutes ||
             currentTime.totalMinutes <= sleepEnd.totalMinutes;
    } else {
      // Same-day period (e.g., 14:00 - 16:00)
      return currentTime.totalMinutes >= sleepStart.totalMinutes &&
             currentTime.totalMinutes <= sleepEnd.totalMinutes;
    }
  }

  /// Get time remaining until sleep period ends (useful for UI)
  static Duration? getTimeUntilSleepEnds(SleepTimeSettings settings) {
    if (!isCurrentlySleepTime(settings)) {
      return null;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    DateTime sleepEndDateTime;
    
    if (settings.sleepStart.totalMinutes > settings.sleepEnd.totalMinutes) {
      // Overnight sleep - sleep end is tomorrow
      sleepEndDateTime = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        settings.sleepEnd.hour,
        settings.sleepEnd.minute,
      );
    } else {
      // Same-day sleep - sleep end is today
      sleepEndDateTime = DateTime(
        today.year,
        today.month,
        today.day,
        settings.sleepEnd.hour,
        settings.sleepEnd.minute,
      );
    }

    final remainingTime = sleepEndDateTime.difference(now);
    return remainingTime.isNegative ? Duration.zero : remainingTime;
  }

  /// Get user-friendly description of sleep schedule
  static String getSleepScheduleDescription(SleepTimeSettings settings) {
    if (!settings.enabled) {
      return '수면 시간 제외 비활성화됨';
    }

    final startTime = settings.sleepStart.format24Hour();
    final endTime = settings.sleepEnd.format24Hour();
    
    final dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final activeDayNames = settings.activeDays.map((day) => dayNames[day - 1]).toList();
    
    if (settings.activeDays.length == 7) {
      return '매일 $startTime - $endTime';
    } else {
      return '${activeDayNames.join(', ')} $startTime - $endTime';
    }
  }

  /// Check if survival alert should be triggered considering sleep time
  static bool shouldTriggerSurvivalAlert(
    DateTime lastActivity,
    int alertHours,
    SleepTimeSettings sleepSettings,
  ) {
    final now = DateTime.now();
    
    if (!sleepSettings.enabled) {
      // No sleep exclusion - use simple time check
      final timeSinceActivity = now.difference(lastActivity);
      final shouldAlert = timeSinceActivity.inHours >= alertHours;
      
      AppLogger.debug(
        'Simple survival check: ${timeSinceActivity.inHours}h since activity, '
        'threshold: ${alertHours}h, alert: $shouldAlert',
        tag: tag,
      );
      
      return shouldAlert;
    }

    // Calculate awake time since last activity
    final awakeTimeSinceActivity = calculateAwakeTimeBetween(lastActivity, now, sleepSettings);
    final shouldAlert = awakeTimeSinceActivity.inHours >= alertHours;
    
    AppLogger.debug(
      'Sleep-aware survival check: ${awakeTimeSinceActivity.inHours}h awake time since activity, '
      'threshold: ${alertHours}h, alert: $shouldAlert',
      tag: tag,
    );
    
    return shouldAlert;
  }
}