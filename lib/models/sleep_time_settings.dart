import 'package:flutter/material.dart';

class SleepTimeSettings {
  final bool enabled;
  final TimeOfDay sleepStart;
  final TimeOfDay sleepEnd;
  final List<int> activeDays; // 1=Monday, 7=Sunday

  const SleepTimeSettings({
    required this.enabled,
    required this.sleepStart,
    required this.sleepEnd,
    required this.activeDays,
  });

  // Default sleep time: 22:00 - 06:00, all days
  factory SleepTimeSettings.defaultSettings() {
    return SleepTimeSettings(
      enabled: false,
      sleepStart: const TimeOfDay(hour: 22, minute: 0),
      sleepEnd: const TimeOfDay(hour: 6, minute: 0),
      activeDays: [1, 2, 3, 4, 5, 6, 7], // All days
    );
  }

  // Create from Map (for Firebase/SharedPreferences)
  factory SleepTimeSettings.fromMap(Map<String, dynamic> map) {
    return SleepTimeSettings(
      enabled: map['enabled'] ?? false,
      sleepStart: TimeOfDay(
        hour: map['sleepStartHour'] ?? 22,
        minute: map['sleepStartMinute'] ?? 0,
      ),
      sleepEnd: TimeOfDay(
        hour: map['sleepEndHour'] ?? 6,
        minute: map['sleepEndMinute'] ?? 0,
      ),
      activeDays: List<int>.from(map['activeDays'] ?? [1, 2, 3, 4, 5, 6, 7]),
    );
  }

  // Convert to Map (for Firebase/SharedPreferences)
  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'sleepStartHour': sleepStart.hour,
      'sleepStartMinute': sleepStart.minute,
      'sleepEndHour': sleepEnd.hour,
      'sleepEndMinute': sleepEnd.minute,
      'activeDays': activeDays,
    };
  }

  // Create copy with modified properties
  SleepTimeSettings copyWith({
    bool? enabled,
    TimeOfDay? sleepStart,
    TimeOfDay? sleepEnd,
    List<int>? activeDays,
  }) {
    return SleepTimeSettings(
      enabled: enabled ?? this.enabled,
      sleepStart: sleepStart ?? this.sleepStart,
      sleepEnd: sleepEnd ?? this.sleepEnd,
      activeDays: activeDays ?? this.activeDays,
    );
  }

  @override
  String toString() {
    return 'SleepTimeSettings(enabled: $enabled, '
        'sleepStart: ${sleepStart.format24Hour()}, '
        'sleepEnd: ${sleepEnd.format24Hour()}, '
        'activeDays: $activeDays)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepTimeSettings &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          sleepStart == other.sleepStart &&
          sleepEnd == other.sleepEnd &&
          _listEquals(activeDays, other.activeDays);

  @override
  int get hashCode =>
      enabled.hashCode ^
      sleepStart.hashCode ^
      sleepEnd.hashCode ^
      activeDays.hashCode;

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

extension TimeOfDayExtensions on TimeOfDay {
  String format24Hour() {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  // Compare TimeOfDay objects
  bool isBefore(TimeOfDay other) {
    return hour < other.hour || (hour == other.hour && minute < other.minute);
  }

  bool isAfter(TimeOfDay other) {
    return hour > other.hour || (hour == other.hour && minute > other.minute);
  }

  // Convert to minutes since midnight for easier comparison
  int get totalMinutes => hour * 60 + minute;
}