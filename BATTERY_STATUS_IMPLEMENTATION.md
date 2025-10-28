# Battery Status Sharing - Parent to Child App

## Overview

Allow child app to monitor the elderly parent's phone battery level in real-time. This helps family members know if the phone might die soon, preventing false survival alerts.

---

## Table of Contents

1. [Why Battery Status Matters](#why-battery-status-matters)
2. [System Architecture](#system-architecture)
3. [Firebase Data Structure](#firebase-data-structure)
4. [Parent App Implementation](#parent-app-implementation)
5. [Child App Implementation](#child-app-implementation)
6. [Testing](#testing)
7. [Cost Impact](#cost-impact)

---

## Why Battery Status Matters

### Problem Scenarios

**Scenario 1: Low Battery Warning**
```
Parent phone battery: 15%
No survival signal for 10 hours
Child app doesn't know why - Could be:
  - Phone about to die? (Low battery)
  - Elderly person in trouble? (Real emergency)
```

**Scenario 2: Battery Died**
```
Parent phone battery: 0% (died at 14:00)
Last signal: 14:00
Current time: 02:00 (12 hours later)

Without battery info:
  → Child app sends survival alert
  → Family panics
  → Just low battery, not emergency

With battery info:
  → Child app shows: "Phone died (0% battery at 14:00)"
  → Family knows it's battery issue
  → Can still check but less panic
```

### Benefits

✅ **Reduce false alarms** - Distinguish battery death from real emergency
✅ **Proactive monitoring** - Family can remind parent to charge phone
✅ **Better context** - Child app shows full picture of parent's status
✅ **Low cost** - Only 1 extra field in existing updates

---

## System Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────┐
│               Parent App (Elderly Phone)            │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. Read Battery Level                              │
│     └─> Android: BatteryManager                    │
│     └─> Returns: 85% (example)                     │
│                                                     │
│  2. Read Charging Status                            │
│     └─> Is plugged in? true/false                  │
│                                                     │
│  3. Update Firebase (every 15 minutes)              │
│     └─> families/{familyId}                         │
│         ├─> lastPhoneActivity: Timestamp           │
│         ├─> batteryLevel: 85                       │
│         ├─> isCharging: false                      │
│         └─> batteryTimestamp: Timestamp            │
│                                                     │
└─────────────────────────────────────────────────────┘
                        │
                        │ Firestore writes
                        ▼
┌─────────────────────────────────────────────────────┐
│                  Firebase Firestore                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  families/{familyId}/                               │
│  {                                                  │
│    elderlyName: "이영훈",                           │
│    lastPhoneActivity: <timestamp>,                 │
│    batteryLevel: 85,              ← NEW            │
│    isCharging: false,             ← NEW            │
│    batteryTimestamp: <timestamp>, ← NEW            │
│    location: { ... }                                │
│  }                                                  │
│                                                     │
└─────────────────────────────────────────────────────┘
                        │
                        │ Real-time listener
                        ▼
┌─────────────────────────────────────────────────────┐
│              Child App (Family Phone)               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. Listen to Firebase changes                      │
│     └─> families/{familyId}                         │
│                                                     │
│  2. Display Battery Status                          │
│     ┌─────────────────────────────────┐            │
│     │  🔋 Parent Phone Status         │            │
│     │                                 │            │
│     │  Battery: 85% 🟢                │            │
│     │  Status: Not charging           │            │
│     │  Updated: 2 minutes ago         │            │
│     └─────────────────────────────────┘            │
│                                                     │
│  3. Show Warnings                                   │
│     ├─> Low battery (< 20%): ⚠️ Yellow             │
│     ├─> Critical (< 10%): 🔴 Red alert             │
│     └─> Phone died (0%): 💀 Special message        │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Firebase Data Structure

### Updated Family Document

```javascript
families/{familyId}/
{
  // Existing fields
  elderlyName: "이영훈",
  lastPhoneActivity: Timestamp(2025-10-26 14:30:00),
  lastActivityType: "screen_on_activity",

  location: {
    latitude: 37.5665,
    longitude: 126.9780,
    timestamp: Timestamp(2025-10-26 14:30:00),
    address: ""
  },

  // NEW: Battery information
  batteryLevel: 85,                           // 0-100 (percentage)
  isCharging: false,                          // true/false
  batteryTimestamp: Timestamp(2025-10-26 14:30:00),  // When battery was read

  // Optional: Battery health info
  batteryHealth: "GOOD",                      // GOOD, OVERHEAT, DEAD, etc.
  batteryTemperature: 30.5,                   // Celsius (optional)

  settings: {
    survivalSignalEnabled: true,
    alertHours: 12,
    sleepExclusionEnabled: true,
    sleepStartHour: 22,
    sleepEndHour: 6
  }
}
```

### Battery Level States

```javascript
batteryLevel: 100-50  → 🔋 Good (Green)
batteryLevel: 49-20   → 🪫 Medium (Orange)
batteryLevel: 19-1    → 🔴 Critical (Red)
batteryLevel: 0       → (0% - Phone Off) - No emoji, just text
isCharging: true      → 🔌 Charging (Blue)
```

---

## Parent App Implementation

### Step 1: Add Battery Permission

**File:** `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Existing permissions -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

    <!-- NEW: Battery info permission (not dangerous, no runtime request needed) -->
    <!-- This permission is automatically granted, no user prompt -->
    <uses-permission android:name="android.permission.BATTERY_STATS" />

    <application>
        <!-- ... -->
    </application>
</manifest>
```

**Note:** `BATTERY_STATS` is a normal permission, automatically granted. No runtime permission request needed.

### Step 2: Create Battery Service (Kotlin)

**File:** `android/app/src/main/kotlin/com/thousandemfla/thanks_everyday/services/BatteryService.kt`

Create new file:

```kotlin
package com.thousandemfla.thanks_everyday.services

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log

/**
 * Service to read battery information
 */
object BatteryService {
    private const val TAG = "BatteryService"

    /**
     * Get current battery information
     * Returns a map with battery data
     */
    fun getBatteryInfo(context: Context): Map<String, Any> {
        try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

            // Get battery level (0-100)
            val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

            // Get charging status
            val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
                context.registerReceiver(null, filter)
            }

            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                           status == BatteryManager.BATTERY_STATUS_FULL

            // Get charging method (USB, AC, Wireless)
            val chargePlug = batteryStatus?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
            val chargingMethod = when (chargePlug) {
                BatteryManager.BATTERY_PLUGGED_USB -> "USB"
                BatteryManager.BATTERY_PLUGGED_AC -> "AC"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
                else -> "Not charging"
            }

            // Get battery health
            val health = batteryStatus?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) ?: -1
            val batteryHealth = when (health) {
                BatteryManager.BATTERY_HEALTH_GOOD -> "GOOD"
                BatteryManager.BATTERY_HEALTH_OVERHEAT -> "OVERHEAT"
                BatteryManager.BATTERY_HEALTH_DEAD -> "DEAD"
                BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "OVER_VOLTAGE"
                BatteryManager.BATTERY_HEALTH_COLD -> "COLD"
                else -> "UNKNOWN"
            }

            // Get battery temperature (in tenths of degrees Celsius)
            val temperature = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
            val temperatureCelsius = if (temperature > 0) temperature / 10.0 else null

            Log.d(TAG, "Battery: ${batteryLevel}%, Charging: $isCharging, Health: $batteryHealth")

            return mapOf(
                "batteryLevel" to batteryLevel,
                "isCharging" to isCharging,
                "chargingMethod" to chargingMethod,
                "batteryHealth" to batteryHealth,
                "batteryTemperature" to temperatureCelsius,
                "timestamp" to System.currentTimeMillis()
            )

        } catch (e: Exception) {
            Log.e(TAG, "Failed to get battery info: ${e.message}")
            return mapOf(
                "batteryLevel" to -1,
                "isCharging" to false,
                "error" to e.message.toString()
            )
        }
    }

    /**
     * Get battery level emoji based on percentage and charging status
     */
    fun getBatteryEmoji(batteryLevel: Int, isCharging: Boolean): String {
        return when {
            isCharging -> "🔌"
            batteryLevel >= 80 -> "🔋"
            batteryLevel >= 50 -> "🔋"
            batteryLevel >= 20 -> "🪫"
            batteryLevel >= 10 -> "⚠️"
            batteryLevel > 0 -> "🔴"
            else -> "💀"
        }
    }
}
```

### Step 3: Update AlarmUpdateReceiver to Include Battery

**File:** `android/app/src/main/kotlin/com/thousandemfla/thanks_everyday/elder/AlarmUpdateReceiver.kt`

Add battery import at top:
```kotlin
import com.thousandemfla.thanks_everyday.services.BatteryService
```

Find the survival signal update section (around line 500-550) and modify:

```kotlin
// Find this section in handleSurvivalSignalAlarm():
private fun handleSurvivalSignalAlarm(context: Context) {
    // ... existing code ...

    // Get battery info
    val batteryInfo = BatteryService.getBatteryInfo(context)
    val batteryLevel = batteryInfo["batteryLevel"] as Int
    val isCharging = batteryInfo["isCharging"] as Boolean
    val batteryHealth = batteryInfo["batteryHealth"] as String

    Log.d(TAG, "📱 Phone status: Battery ${batteryLevel}%, Charging: $isCharging")

    // Update Firebase with battery info
    val updates = hashMapOf<String, Any>(
        "lastPhoneActivity" to com.google.firebase.Timestamp.now(),
        "lastActivityType" to "survival_signal",
        "batteryLevel" to batteryLevel,
        "isCharging" to isCharging,
        "batteryTimestamp" to com.google.firebase.Timestamp.now()
    )

    // Optional: Add battery health if available
    if (batteryHealth != "UNKNOWN") {
        updates["batteryHealth"] = batteryHealth
    }

    // Optional: Add temperature if available
    val temperature = batteryInfo["batteryTemperature"]
    if (temperature != null && temperature is Double) {
        updates["batteryTemperature"] = temperature
    }

    // Update Firestore
    firestore.collection("families")
        .document(familyId)
        .update(updates)
        .addOnSuccessListener {
            Log.d(TAG, "✅ Firebase updated with battery info: ${batteryLevel}%")
        }
        .addOnFailureListener { e ->
            Log.e(TAG, "❌ Failed to update Firebase: ${e.message}")
        }
}
```

### Step 4: Add Battery Method Channel (Flutter Bridge)

**File:** `android/app/src/main/kotlin/com/thousandemfla/thanks_everyday/MainActivity.kt`

Add to the method channel handler:

```kotlin
// Find the setMethodCallHandler section and add:
"getBatteryInfo" -> {
    val batteryInfo = BatteryService.getBatteryInfo(this)
    result.success(batteryInfo)
}
```

### Step 5: Create Flutter Battery Service

**File:** `lib/services/battery_service.dart`

Create new file:

```dart
import 'package:flutter/services.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class BatteryService {
  static const MethodChannel _channel = MethodChannel('com.thousandemfla.thanks_everyday/screen_monitor');

  /// Get current battery information from native Android
  static Future<Map<String, dynamic>?> getBatteryInfo() async {
    try {
      final result = await _channel.invokeMethod('getBatteryInfo');

      if (result != null && result is Map) {
        final batteryInfo = Map<String, dynamic>.from(result);

        final batteryLevel = batteryInfo['batteryLevel'] ?? -1;
        final isCharging = batteryInfo['isCharging'] ?? false;

        AppLogger.debug(
          'Battery: $batteryLevel%, Charging: $isCharging',
          tag: 'BatteryService'
        );

        return batteryInfo;
      }

      return null;
    } catch (e) {
      AppLogger.error('Failed to get battery info: $e', tag: 'BatteryService');
      return null;
    }
  }

  /// Get battery level emoji
  static String getBatteryEmoji(int batteryLevel, bool isCharging) {
    if (isCharging) return '🔌';
    if (batteryLevel >= 80) return '🔋';
    if (batteryLevel >= 50) return '🔋';
    if (batteryLevel >= 20) return '🪫';
    if (batteryLevel >= 10) return '⚠️';
    if (batteryLevel > 0) return '🔴';
    return '💀';
  }

  /// Get battery status text
  static String getBatteryStatusText(int batteryLevel, bool isCharging) {
    if (isCharging) return 'Charging';
    if (batteryLevel >= 80) return 'Good';
    if (batteryLevel >= 50) return 'Good';
    if (batteryLevel >= 20) return 'Medium';
    if (batteryLevel >= 10) return 'Low';
    if (batteryLevel > 0) return 'Critical';
    return 'Dead';
  }

  /// Get battery color for UI
  static String getBatteryColor(int batteryLevel, bool isCharging) {
    if (isCharging) return 'blue';
    if (batteryLevel >= 50) return 'green';
    if (batteryLevel >= 20) return 'yellow';
    if (batteryLevel >= 10) return 'orange';
    return 'red';
  }
}
```

### Step 6: Update FirebaseService to Send Battery

**File:** `lib/services/firebase_service.dart`

Find the `updatePhoneActivity()` method and add battery info:

```dart
Future<bool> updatePhoneActivity({bool forceImmediate = false}) async {
  try {
    if (_familyId == null) {
      AppLogger.warning('Cannot update phone activity: no family ID', tag: 'FirebaseService');
      return false;
    }

    // Get battery info
    final batteryInfo = await BatteryService.getBatteryInfo();
    final batteryLevel = batteryInfo?['batteryLevel'] ?? -1;
    final isCharging = batteryInfo?['isCharging'] ?? false;
    final batteryHealth = batteryInfo?['batteryHealth'] ?? 'UNKNOWN';

    final updateData = {
      'lastPhoneActivity': FieldValue.serverTimestamp(),
      'lastActivityType': 'app_activity',
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      'batteryTimestamp': FieldValue.serverTimestamp(),
    };

    // Optional: Add battery health if not unknown
    if (batteryHealth != 'UNKNOWN') {
      updateData['batteryHealth'] = batteryHealth;
    }

    // Optional: Add temperature
    final temperature = batteryInfo?['batteryTemperature'];
    if (temperature != null) {
      updateData['batteryTemperature'] = temperature;
    }

    await _firestore.collection('families').doc(_familyId).update(updateData);

    AppLogger.info(
      'Phone activity updated with battery: $batteryLevel% (${isCharging ? "Charging" : "Not charging"})',
      tag: 'FirebaseService'
    );

    return true;
  } catch (e) {
    AppLogger.error('Failed to update phone activity: $e', tag: 'FirebaseService');
    return false;
  }
}
```

### Step 7: Display Battery in Parent App (Optional)

**File:** `lib/screens/settings_screen.dart`

Add battery display widget:

```dart
// Add this widget to show current battery status
Widget _buildBatteryStatusCard() {
  return FutureBuilder<Map<String, dynamic>?>(
    future: BatteryService.getBatteryInfo(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox();
      }

      final batteryInfo = snapshot.data!;
      final batteryLevel = batteryInfo['batteryLevel'] ?? -1;
      final isCharging = batteryInfo['isCharging'] ?? false;
      final emoji = BatteryService.getBatteryEmoji(batteryLevel, isCharging);
      final status = BatteryService.getBatteryStatusText(batteryLevel, isCharging);

      return Card(
        child: ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 32)),
          title: Text('Battery: $batteryLevel%'),
          subtitle: Text('Status: $status'),
          trailing: isCharging
              ? const Icon(Icons.charging_station, color: Colors.blue)
              : null,
        ),
      );
    },
  );
}
```

---

## Child App Implementation

### Step 1: Update Family Model

**File:** `lib/models/family.dart` (or similar)

```dart
class Family {
  final String id;
  final String elderlyName;
  final DateTime? lastPhoneActivity;

  // NEW: Battery information
  final int? batteryLevel;          // 0-100
  final bool? isCharging;           // true/false
  final DateTime? batteryTimestamp; // When battery was read
  final String? batteryHealth;      // GOOD, OVERHEAT, etc.
  final double? batteryTemperature; // Celsius

  final Map<String, dynamic>? location;
  final Map<String, dynamic>? settings;

  Family({
    required this.id,
    required this.elderlyName,
    this.lastPhoneActivity,
    this.batteryLevel,
    this.isCharging,
    this.batteryTimestamp,
    this.batteryHealth,
    this.batteryTemperature,
    this.location,
    this.settings,
  });

  factory Family.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Family(
      id: doc.id,
      elderlyName: data['elderlyName'] ?? 'Unknown',
      lastPhoneActivity: (data['lastPhoneActivity'] as Timestamp?)?.toDate(),

      // Parse battery info
      batteryLevel: data['batteryLevel'] as int?,
      isCharging: data['isCharging'] as bool?,
      batteryTimestamp: (data['batteryTimestamp'] as Timestamp?)?.toDate(),
      batteryHealth: data['batteryHealth'] as String?,
      batteryTemperature: (data['batteryTemperature'] as num?)?.toDouble(),

      location: data['location'] as Map<String, dynamic>?,
      settings: data['settings'] as Map<String, dynamic>?,
    );
  }
}
```

### Step 2: Create Battery Widget

**File:** `lib/widgets/battery_status_widget.dart`

```dart
import 'package:flutter/material.dart';

class BatteryStatusWidget extends StatelessWidget {
  final int? batteryLevel;
  final bool? isCharging;
  final DateTime? batteryTimestamp;
  final String? batteryHealth;

  const BatteryStatusWidget({
    Key? key,
    this.batteryLevel,
    this.isCharging,
    this.batteryTimestamp,
    this.batteryHealth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // No battery data
    if (batteryLevel == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.battery_unknown, color: Colors.grey),
          title: const Text('Battery Status'),
          subtitle: const Text('No data available'),
        ),
      );
    }

    // Get battery info
    final level = batteryLevel!;
    final charging = isCharging ?? false;
    final emoji = _getBatteryEmoji(level, charging);
    final color = _getBatteryColor(level, charging);
    final statusText = _getBatteryStatusText(level, charging);
    final timeAgo = _getTimeAgo(batteryTimestamp);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Battery: $level%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (charging)
                  const Icon(Icons.charging_station, color: Colors.blue, size: 32),
              ],
            ),
            const SizedBox(height: 8),

            // Battery level bar
            LinearProgressIndicator(
              value: level / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),

            const SizedBox(height: 8),

            // Timestamp
            Text(
              'Updated: $timeAgo',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),

            // Battery health warning
            if (batteryHealth != null && batteryHealth != 'GOOD')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Battery health: $batteryHealth',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getBatteryEmoji(int level, bool charging) {
    if (charging) return '🔌';
    if (level >= 80) return '🔋';
    if (level >= 50) return '🔋';
    if (level >= 20) return '🪫';
    if (level >= 10) return '⚠️';
    return '🔴';  // Red circle for low/empty, no skull emoji
  }

  Color _getBatteryColor(int level, bool charging) {
    if (charging) return Colors.blue;
    if (level >= 50) return Colors.green;
    if (level >= 20) return Colors.orange;
    if (level >= 10) return Colors.deepOrange;
    return Colors.red;
  }

  String _getBatteryStatusText(int level, bool charging) {
    if (charging) return 'Charging';
    if (level >= 50) return 'Good';
    if (level >= 20) return 'Medium';
    if (level >= 10) return 'Low - Remind to charge';
    if (level > 0) return 'Critical - Phone may die soon!';
    return 'Phone died';
  }

  String _getTimeAgo(DateTime? timestamp) {
    if (timestamp == null) return 'Unknown';

    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} minutes ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    return '${difference.inDays} days ago';
  }
}
```

### Step 3: Add Battery to Family Dashboard

**File:** `lib/screens/family_dashboard_screen.dart` (or main family screen)

```dart
// In your family dashboard, add the battery widget:

@override
Widget build(BuildContext context) {
  return StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const CircularProgressIndicator();
      }

      final family = Family.fromFirestore(snapshot.data!);

      return Column(
        children: [
          // Existing widgets...

          // NEW: Battery status widget
          BatteryStatusWidget(
            batteryLevel: family.batteryLevel,
            isCharging: family.isCharging,
            batteryTimestamp: family.batteryTimestamp,
            batteryHealth: family.batteryHealth,
          ),

          // Other widgets...
        ],
      );
    },
  );
}
```

### Step 4: Show Battery in Alerts

**File:** `lib/screens/alert_screen.dart` (or alert handling)

Enhance survival alerts with battery context:

```dart
Widget _buildSurvivalAlert(Family family) {
  final hoursInactive = _calculateHoursInactive(family.lastPhoneActivity);
  final batteryLevel = family.batteryLevel;
  final isCharging = family.isCharging ?? false;

  // Determine alert message based on battery
  String alertMessage;
  Color alertColor;
  IconData alertIcon;

  if (batteryLevel != null && batteryLevel == 0) {
    // Phone died
    alertMessage = '${family.elderlyName}님의 휴대폰 배터리가 방전되었습니다 (0%)';
    alertColor = Colors.grey;
    alertIcon = Icons.battery_0_bar;
  } else if (batteryLevel != null && batteryLevel < 10) {
    // Critical battery
    alertMessage = '${family.elderlyName}님의 휴대폰 배터리가 거의 없습니다 ($batteryLevel%)';
    alertColor = Colors.red;
    alertIcon = Icons.battery_alert;
  } else {
    // Normal survival alert - include battery info
    final batteryInfo = _getBatteryDisplay(family);
    alertMessage = '${family.elderlyName}님 $batteryInfo이 $hoursInactive시간 이상 활동이 없습니다';
    alertColor = Colors.orange;
    alertIcon = Icons.warning;
  }

  return Card(
    color: alertColor.withOpacity(0.1),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(alertIcon, color: alertColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  alertMessage,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: alertColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Last activity: ${_formatDateTime(family.lastPhoneActivity)}',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    ),
  );
}

// Same helper function as before
String _getBatteryDisplay(Family family) {
  if (family.batteryLevel == null) return '';
  final level = family.batteryLevel!;
  final charging = family.isCharging ?? false;
  if (level == 0) return '(0% - Phone Off)';
  final emoji = charging ? '🔌' : level >= 50 ? '🔋' : level >= 20 ? '🪫' : '🔴';
  return '$emoji $level%';
}
```

### Step 5: Add Battery Notification

Enhance FCM notifications with battery info:

```dart
// When sending survival alert, include battery in notification

final notificationBody = batteryLevel != null && batteryLevel < 10
    ? '${elderlyName}님이 $hoursInactive시간 이상 활동이 없습니다 (배터리: $batteryLevel%)'
    : '${elderlyName}님이 $hoursInactive시간 이상 활동이 없습니다';
```

---

## Testing

### Parent App Testing

#### 1. Test Battery Reading

```dart
// Add test button in settings screen
ElevatedButton(
  onPressed: () async {
    final batteryInfo = await BatteryService.getBatteryInfo();
    print('Battery Info: $batteryInfo');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Battery: ${batteryInfo?['batteryLevel']}%')),
    );
  },
  child: const Text('Test Battery Reading'),
)
```

#### 2. Test Firebase Update

Check Firestore after update:
1. Open Firebase Console → Firestore
2. Navigate to `families/{your-family-id}`
3. Verify new fields exist:
   - `batteryLevel`: (number)
   - `isCharging`: (boolean)
   - `batteryTimestamp`: (timestamp)

#### 3. Test Different Battery Levels

Simulate battery changes:
- Unplug charger: `isCharging` should change to `false`
- Plug in charger: `isCharging` should change to `true`
- Wait for battery to drain: `batteryLevel` should decrease

### Child App Testing

#### 1. Real-time Updates

Open child app and watch battery widget update every 15 minutes when parent app sends updates.

#### 2. UI States

Test all battery level ranges:
- 100-80%: Green, "Good"
- 50-20%: Orange, "Medium"
- 20-10%: Red, "Low"
- 10-0%: Dark red, "Critical"
- 0%: Grey, "Dead"

#### 3. Charging Indicator

- Plug/unplug parent phone
- Verify charging icon appears/disappears in child app

---

## Cost Impact

### Additional Firebase Writes

**Per Update:**
- Old: 1 field (`lastPhoneActivity`)
- New: 3-5 fields (`lastPhoneActivity`, `batteryLevel`, `isCharging`, `batteryTimestamp`, `batteryHealth`)

**Cost Impact:**
- Same write operation (updating same document)
- No additional cost (writes are counted per operation, not per field)
- **Cost increase: $0**

### Additional Storage

**Per Family Document:**
- Old: ~200 bytes
- New: ~250 bytes (50 bytes more)
- Increase: 25%

**For 1,000 families:**
- Old: 200 KB
- New: 250 KB
- Increase: 50 KB (negligible cost)

### Summary

✅ **No additional cost** for Firebase writes
✅ **Minimal storage increase** (~50 KB for 1,000 families)
✅ **No additional function executions** needed
✅ **Free feature** with existing infrastructure

---

## Advanced Features (Optional)

### 1. Battery History Chart

Track battery levels over time:

```dart
// Store battery history in subcollection
families/{familyId}/batteryHistory/{timestamp}/
{
  batteryLevel: 75,
  isCharging: false,
  timestamp: Timestamp
}
```

Display as chart in child app.

### 2. Low Battery Notifications

Send proactive notification when battery is low:

```javascript
// In Firebase Function
if (batteryLevel < 20 && !isCharging) {
  await sendLowBatteryAlert(familyId, elderlyName, batteryLevel);
}
```

### 3. Charging Reminders

Remind parent to charge phone:

```dart
// Parent app: Show notification when battery < 15%
if (batteryLevel < 15 && !isCharging) {
  showLocalNotification('배터리가 부족합니다. 충전해주세요.');
}
```

### 4. Battery Health Monitoring

Track battery degradation over time:
- Average battery health
- Charging cycles
- Battery capacity reduction

---

## Troubleshooting

### Issue 1: Battery Level Always -1

**Cause:** Permission not granted or method not working

**Solution:**
1. Check `BATTERY_STATS` permission in AndroidManifest.xml
2. Verify BatteryService.kt is compiled
3. Check logcat for errors: `adb logcat | grep Battery`

### Issue 2: Battery Not Updating in Child App

**Cause:** Firebase not receiving updates

**Solution:**
1. Check parent app logs: Battery info being sent?
2. Check Firestore: Fields exist in database?
3. Check child app stream: Listening to correct document?

### Issue 3: isCharging Always False

**Cause:** Battery status not being read correctly

**Solution:**
- Verify battery broadcast intent is working
- Test with charger plugged in
- Check Android version compatibility

---

## Summary

### Implementation Checklist

**Parent App:**
- [ ] Add `BATTERY_STATS` permission to AndroidManifest.xml
- [ ] Create `BatteryService.kt`
- [ ] Update `AlarmUpdateReceiver.kt` to include battery
- [ ] Create `battery_service.dart` (Flutter)
- [ ] Update `firebase_service.dart` to send battery
- [ ] (Optional) Display battery in settings screen

**Child App:**
- [ ] Update Family model with battery fields
- [ ] Add battery helper function `_getBatteryDisplay()`
- [ ] Show battery next to elderly name in dashboard
- [ ] Show battery in survival alerts
- [ ] (Optional) Add battery in notifications

**Testing:**
- [ ] Test battery reading in parent app
- [ ] Verify Firebase updates with battery info
- [ ] Test real-time updates in child app
- [ ] Test all battery level ranges (0-100%)
- [ ] Test charging/not charging states

### Benefits Achieved

✅ **Better context** for survival alerts
✅ **Reduce false alarms** (distinguish battery death from emergency)
✅ **Proactive monitoring** (family can remind to charge)
✅ **Low battery warnings** (prevent phone death)
✅ **No additional cost** (uses existing infrastructure)

---

**Document Version:** 1.0
**Date:** 2025-10-26
**Status:** Implementation Guide
**Estimated Implementation Time:** 2-3 hours
**Cost Impact:** $0 (no additional Firebase cost)
