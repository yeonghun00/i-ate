# Sleep Time Exclusion Implementation Guide

**App:** Thanks Everyday (부모 앱 / Parent App)
**Feature:** Sleep Time Exclusion for Survival Signal
**Purpose:** Prevent false survival alerts during user's configured sleep hours
**Created:** 2025-10-30

---

## Overview

The Sleep Time Exclusion feature allows users to configure specific time periods when **survival signal updates should NOT be sent to Firebase**. This prevents false alarms when the elderly user is sleeping and not actively using their phone, especially when short alert thresholds (e.g., 2 hours) are configured.

### Key Principles

1. **GPS Tracking**: ALWAYS works - never affected by sleep time
2. **Battery Status**: ALWAYS works - never affected by sleep time
3. **Survival Signal (lastPhoneActivity)**: SKIPPED during sleep time
4. **Meal Recording**: ALWAYS works - meals override sleep time logic
5. **Child App Display**: Shows sleep time status to family members

### Why This Feature Exists

**Problem Scenario:**
- User sets survival alert threshold to 2 hours
- Elderly person goes to sleep at 22:00
- By midnight (2 hours later), no phone activity detected
- Family receives false alarm even though person is just sleeping

**Solution:**
- During sleep hours (e.g., 22:00 - 06:00), survival signal updates are skipped
- GPS and battery continue to update normally
- Firebase Function also respects sleep time when checking for alerts
- Result: No false alarms during configured sleep period

---

## Current Implementation Status

### ✅ IMPLEMENTED (Android Native - AlarmUpdateReceiver.kt)

The Android native alarm service **implements sleep time checking** for scheduled alarms:

**Location:** `android/app/src/main/kotlin/com/thousandemfla/thanks_everyday/elder/AlarmUpdateReceiver.kt:510-519`

```kotlin
private fun handleSurvivalUpdate(context: Context) {
    // ...

    // Check if it's currently sleep time
    if (isCurrentlySleepTime(context)) {
        Log.d(TAG, "😴 Currently in sleep period - skipping survival signal, but updating battery")
        // During sleep: Update battery ONLY, skip survival signal
        updateFirebaseWithBatteryOnly(context)
        // Still record execution and schedule next alarm
        recordAlarmExecution(context, "survival")
        scheduleSurvivalAlarm(context)
        return // ✅ Battery updated, survival signal skipped
    }

    // Normal survival signal update...
    checkScreenStateAndUpdateFirebase(context)
}
```

**New Method - Battery-Only Update During Sleep:**
```kotlin
private fun updateFirebaseWithBatteryOnly(context: Context) {
    // Get battery info
    val batteryInfo = BatteryService.getBatteryInfo(context)

    // Update ONLY battery info, NOT lastPhoneActivity
    val updateData = mapOf(
        "batteryLevel" to batteryInfo["batteryLevel"]!!,
        "isCharging" to batteryInfo["isCharging"]!!,
        "batteryHealth" to batteryInfo["batteryHealth"]!!,
        "batteryTimestamp" to FieldValue.serverTimestamp()
    )

    db.collection("families").document(familyId).update(updateData)
}
```

**Sleep Time Check Logic:** `AlarmUpdateReceiver.kt:682-738`

```kotlin
private fun isCurrentlySleepTime(context: Context): Boolean {
    val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    // 1. Check if sleep exclusion is enabled
    val sleepEnabled = prefs.getBoolean("flutter.sleep_exclusion_enabled", false)
    if (!sleepEnabled) return false

    // 2. Get sleep time settings
    val sleepStartHour = prefs.getInt("flutter.sleep_start_hour", 22)
    val sleepStartMinute = prefs.getInt("flutter.sleep_start_minute", 0)
    val sleepEndHour = prefs.getInt("flutter.sleep_end_hour", 6)
    val sleepEndMinute = prefs.getInt("flutter.sleep_end_minute", 0)

    // 3. Get active days (1=Monday, 7=Sunday)
    val activeDaysString = prefs.getString("flutter.sleep_active_days", "1,2,3,4,5,6,7")
    val activeDays = activeDaysString?.split(",")?.mapNotNull { it.trim().toIntOrNull() }

    // 4. Check if today is an active day
    val now = java.util.Calendar.getInstance()
    val currentWeekday = now.get(java.util.Calendar.DAY_OF_WEEK)
    val mondayBasedWeekday = if (currentWeekday == java.util.Calendar.SUNDAY) 7 else currentWeekday - 1

    if (!activeDays.contains(mondayBasedWeekday)) {
        return false // Not an active sleep day
    }

    // 5. Check if current time is within sleep period
    val currentTimeMinutes = currentHour * 60 + currentMinute
    val sleepStartMinutes = sleepStartHour * 60 + sleepStartMinute
    val sleepEndMinutes = sleepEndHour * 60 + sleepEndMinute

    return if (sleepStartMinutes > sleepEndMinutes) {
        // Overnight period (e.g., 22:00 - 06:00)
        currentTimeMinutes >= sleepStartMinutes || currentTimeMinutes <= sleepEndMinutes
    } else {
        // Same-day period (e.g., 14:00 - 16:00)
        currentTimeMinutes >= sleepStartMinutes && currentTimeMinutes <= sleepEndMinutes
    }
}
```

### ✅ IMPLEMENTED (Flutter/Dart - firebase_service.dart)

The Flutter side **now checks for sleep time** before updating activity:

**Location:** `lib/services/firebase_service.dart:635-699`

```dart
Future<bool> updatePhoneActivity({bool forceImmediate = false}) async {
  // ... family ID check ...

  // Get battery info
  final batteryInfo = await BatteryService.getBatteryInfo();

  // ✅ CHECK FOR SLEEP TIME
  final isInSleepTime = await _isCurrentlySleepTime();

  final updateData = <String, dynamic>{};

  if (isInSleepTime) {
    // During sleep time: Update ONLY battery, skip survival signal
    AppLogger.info('😴 Currently in sleep period - skipping survival signal, updating battery only');
  } else {
    // Normal operation: Update survival signal
    updateData['lastPhoneActivity'] = FieldValue.serverTimestamp();
    updateData['lastActivityType'] = '...';
    updateData['updateTimestamp'] = FieldValue.serverTimestamp();
  }

  // Always add battery info (regardless of sleep time)
  if (batteryInfo != null) {
    updateData['batteryLevel'] = batteryInfo['batteryLevel'];
    updateData['isCharging'] = batteryInfo['isCharging'];
    updateData['batteryHealth'] = batteryInfo['batteryHealth'];
    updateData['batteryTimestamp'] = FieldValue.serverTimestamp();
  }

  await _firestore.collection('families').doc(_familyId).update(updateData);
}
```

**Sleep Time Check Method:**
```dart
Future<bool> _isCurrentlySleepTime() async {
  // Check if sleep exclusion is enabled
  final sleepEnabled = await _storage.getBool('sleep_exclusion_enabled') ?? false;
  if (!sleepEnabled) return false;

  // Get sleep settings from SharedPreferences
  final sleepStartHour = await _storage.getInt('sleep_start_hour') ?? 22;
  final sleepStartMinute = await _storage.getInt('sleep_start_minute') ?? 0;
  final sleepEndHour = await _storage.getInt('sleep_end_hour') ?? 6;
  final sleepEndMinute = await _storage.getInt('sleep_end_minute') ?? 0;

  final sleepActiveDaysString = await _storage.getString('sleep_active_days') ?? '1,2,3,4,5,6,7';
  final sleepActiveDays = sleepActiveDaysString.split(',').map((e) => int.parse(e.trim())).toList();

  final now = DateTime.now();
  final currentWeekday = now.weekday; // 1=Monday, 7=Sunday

  // Check if today is an active sleep day
  if (!sleepActiveDays.contains(currentWeekday)) return false;

  // Check if current time is within sleep period
  final currentMinutes = now.hour * 60 + now.minute;
  final sleepStartMinutes = sleepStartHour * 60 + sleepStartMinute;
  final sleepEndMinutes = sleepEndHour * 60 + sleepEndMinute;

  if (sleepStartMinutes > sleepEndMinutes) {
    // Overnight period (e.g., 22:00 - 06:00)
    return currentMinutes >= sleepStartMinutes || currentMinutes <= sleepEndMinutes;
  } else {
    // Same-day period (e.g., 14:00 - 16:00)
    return currentMinutes >= sleepStartMinutes && currentMinutes <= sleepEndMinutes;
  }
}
```

**Result:** Even if the user wakes up at 3 AM and opens the app, only battery is updated, not survival signal.

---

## Activity Update Trigger Points

### Where `updatePhoneActivity()` is Called

| Location | Trigger | Force Immediate | Needs Sleep Check? |
|----------|---------|-----------------|-------------------|
| `home_page.dart:101` | App startup | Yes | ❌ **YES** |
| `firebase_service.dart:230` | Before meal recording | Yes | ⚠️ **DEBATABLE** |
| `ActivityBatcher` | Periodic (2-hour interval) | No | ❌ **YES** |
| Native alarm (screen on) | Every 15 min (screen on) | N/A | ✅ Already implemented |

**App Startup:** Should respect sleep time - if user briefly checks phone at 3 AM, don't send activity signal

**Before Meal Recording:** Arguably meal recording itself indicates activity, so maybe should override sleep time? But consistency suggests respecting sleep time.

**Periodic Updates:** Should absolutely respect sleep time

---

## Implementation Requirements

### 1. Add Sleep Time Check to `firebase_service.dart`

**Add new method to `SleepTimeSettings` model:**

```dart
// lib/models/sleep_time_settings.dart

extension SleepTimeChecker on SleepTimeSettings {
  /// Check if current DateTime falls within sleep period
  bool isWithinSleepTime({DateTime? checkTime}) {
    if (!enabled) return false;

    final now = checkTime ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final sleepStartMinutes = sleepStart.totalMinutes;
    final sleepEndMinutes = sleepEnd.totalMinutes;

    // Check if today is an active day (1=Monday, 7=Sunday)
    final weekday = now.weekday; // 1=Monday, 7=Sunday (matches our format)
    if (!activeDays.contains(weekday)) {
      return false;
    }

    // Check if current time is within sleep period
    if (sleepStartMinutes > sleepEndMinutes) {
      // Overnight period (e.g., 22:00 - 06:00)
      return currentMinutes >= sleepStartMinutes || currentMinutes <= sleepEndMinutes;
    } else {
      // Same-day period (e.g., 14:00 - 16:00)
      return currentMinutes >= sleepStartMinutes && currentMinutes <= sleepEndMinutes;
    }
  }
}
```

**Load sleep settings in `firebase_service.dart`:**

```dart
class FirebaseService {
  // Add field
  SleepTimeSettings? _sleepTimeSettings;

  // Load from Firebase during initialization
  Future<void> _loadSleepSettings() async {
    if (_familyId == null) return;

    final doc = await _firestore.collection('families').doc(_familyId).get();
    final data = doc.data();

    if (data?['settings']?['sleepTimeSettings'] != null) {
      _sleepTimeSettings = SleepTimeSettings.fromMap(
        data!['settings']['sleepTimeSettings'] as Map<String, dynamic>
      );
    }
  }

  // Refresh when settings are updated
  Future<bool> updateFamilySettings({
    // ... existing params ...
    SleepTimeSettings? sleepTimeSettings,
  }) async {
    // ... existing update logic ...

    // Refresh local cache
    if (sleepTimeSettings != null) {
      _sleepTimeSettings = sleepTimeSettings;
    }
  }
}
```

**Update `updatePhoneActivity()` to check sleep time:**

```dart
Future<bool> updatePhoneActivity({bool forceImmediate = false}) async {
  try {
    if (_familyId == null) {
      AppLogger.error('CRITICAL: Cannot update phone activity - familyId: $_familyId');
      return false;
    }

    // ✅ CHECK SLEEP TIME BEFORE UPDATING
    if (_sleepTimeSettings?.isWithinSleepTime() ?? false) {
      AppLogger.info('😴 Currently in sleep period - skipping activity update',
        tag: 'FirebaseService');
      return true; // Return success, but don't update Firebase
    }

    // ... rest of existing logic ...
  }
}
```

### 2. Meal Recording Exception

**Decision:** Should meal recording override sleep time?

**Option A (Recommended):** Meal recording ALWAYS updates activity (overrides sleep)
- Rationale: User actively recording meal = clear sign of activity
- Implementation: Pass `ignoreSleepTime: true` flag to `updatePhoneActivity()`

```dart
// firebase_service.dart (in saveMealRecord method)
await updatePhoneActivity(
  forceImmediate: true,
  ignoreSleepTime: true, // ✅ Override sleep time for meals
);
```

**Option B:** Respect sleep time even for meals
- Rationale: Consistency - if user sets sleep time, all signals should respect it
- Implementation: No special handling needed

**Recommended: Option A** - Meal recording is an explicit user action indicating full consciousness and activity.

### 3. Settings Synchronization

**Problem:** Sleep settings are stored in both Firebase AND SharedPreferences

**Storage Locations:**
- **Firebase:** `families/{familyId}/settings/sleepTimeSettings`
- **SharedPreferences (Native):** Multiple keys
  - `flutter.sleep_exclusion_enabled`
  - `flutter.sleep_start_hour`
  - `flutter.sleep_start_minute`
  - `flutter.sleep_end_hour`
  - `flutter.sleep_end_minute`
  - `flutter.sleep_active_days`

**Synchronization Strategy:**

1. **Firebase is source of truth** for child app display
2. **SharedPreferences is source of truth** for native alarm checks
3. **Must sync both** whenever settings change

```dart
// In updateFamilySettings()
Future<bool> updateFamilySettings({
  SleepTimeSettings? sleepTimeSettings,
  // ...
}) async {
  // 1. Update Firebase
  await _firestore.collection('families').doc(_familyId).update({
    'settings.sleepTimeSettings': sleepTimeSettings?.toMap(),
  });

  // 2. Update SharedPreferences (for native alarm)
  if (sleepTimeSettings != null) {
    await _storage.setBool('sleep_exclusion_enabled', sleepTimeSettings.enabled);
    await _storage.setInt('sleep_start_hour', sleepTimeSettings.sleepStart.hour);
    await _storage.setInt('sleep_start_minute', sleepTimeSettings.sleepStart.minute);
    await _storage.setInt('sleep_end_hour', sleepTimeSettings.sleepEnd.hour);
    await _storage.setInt('sleep_end_minute', sleepTimeSettings.sleepEnd.minute);
    await _storage.setString('sleep_active_days', sleepTimeSettings.activeDays.join(','));
  }

  // 3. Update local cache
  _sleepTimeSettings = sleepTimeSettings;

  return true;
}
```

---

## Child App Display Strategy

### Firebase Data Structure

The child app needs to read sleep time settings from Firebase to display appropriate status.

**Firebase Path:** `families/{familyId}/settings/sleepTimeSettings`

**Data Structure:**
```json
{
  "enabled": true,
  "sleepStartHour": 22,
  "sleepStartMinute": 30,
  "sleepEndHour": 6,
  "sleepEndMinute": 0,
  "activeDays": [1, 2, 3, 4, 5, 6, 7]
}
```

### Display Strategy

**Scenario 1: Sleep Time Exclusion Disabled**
- Display normal survival signal status
- No special indication needed

**Scenario 2: Sleep Time Exclusion Enabled + Currently NOT in Sleep Period**
- Display normal survival signal status
- Optional: Show small icon indicating sleep time is configured

**Scenario 3: Sleep Time Exclusion Enabled + Currently IN Sleep Period**
- **Primary Display:** Show "😴 Sleep Mode" status
- **Last Activity:** Still show `lastPhoneActivity` timestamp, but with disclaimer
- **Alert Status:** "Monitoring paused during sleep hours (22:30 - 06:00)"
- **Color:** Use neutral/muted color (not red alert)

### UI Mockup

```
┌─────────────────────────────────────┐
│  👵 김할머니                         │
├─────────────────────────────────────┤
│                                     │
│  😴 수면 시간                        │
│  Sleep Mode Active                  │
│                                     │
│  ⏰ 22:30 - 06:00 (Mon-Sun)        │
│                                     │
│  마지막 활동: 2시간 전 (22:15)       │
│  Last Activity: 2h ago (22:15)      │
│                                     │
│  ℹ️  수면 시간 동안 생존 신호        │
│     모니터링이 일시 중지됩니다.       │
│                                     │
│  ✅ GPS 추적은 정상 작동 중          │
│                                     │
└─────────────────────────────────────┘
```

### Implementation (Child App)

```dart
// Child app - family_status_card.dart

class FamilyStatusCard extends StatelessWidget {
  Widget build(BuildContext context) {
    final sleepSettings = familyData.sleepTimeSettings;
    final isCurrentlySleepTime = sleepSettings?.isWithinSleepTime() ?? false;

    if (isCurrentlySleepTime && sleepSettings!.enabled) {
      return _buildSleepModeCard();
    } else {
      return _buildNormalStatusCard();
    }
  }

  Widget _buildSleepModeCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Column(
        children: [
          Icon(Icons.bedtime, size: 48, color: Colors.blue),
          Text('😴 수면 시간', style: Theme.of(context).textTheme.headline6),
          Text('Sleep Mode Active'),
          SizedBox(height: 8),
          Text('⏰ ${formatSleepTime(sleepSettings!)}'),
          SizedBox(height: 16),
          Text('마지막 활동: ${formatLastActivity(familyData.lastPhoneActivity)}'),
          SizedBox(height: 8),
          Text(
            'ℹ️ 수면 시간 동안 생존 신호 모니터링이 일시 중지됩니다.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (familyData.location != null)
            Text('✅ GPS 추적은 정상 작동 중'),
        ],
      ),
    );
  }
}
```

### Alert Logic

**Question:** Should alerts be suppressed during sleep time?

**Recommended Approach:**
1. **Server-side (Firebase Functions):** Check sleep time before sending alert
2. **Client-side (Child App):** Visual indicator that sleep mode is active
3. **Grace Period:** Wait 30 minutes after sleep end time before triggering alert

**Firebase Function Pseudocode:**
```javascript
// functions/index.js - checkSurvivalStatus

function checkSurvivalStatus(familyData) {
  const now = new Date();
  const sleepSettings = familyData.settings.sleepTimeSettings;

  // Check if currently in sleep time
  if (sleepSettings.enabled && isWithinSleepTime(now, sleepSettings)) {
    console.log('Family in sleep time - skipping alert check');
    return; // Don't send alert
  }

  // Check if recently exited sleep time (grace period)
  const sleepEndTime = getSleepEndTime(sleepSettings);
  const minutesSinceWakeup = (now - sleepEndTime) / 60000;

  if (minutesSinceWakeup < 30) {
    console.log('Within grace period after sleep time - skipping alert');
    return;
  }

  // Normal alert logic...
}
```

---

## Testing Checklist

### Parent App (Flutter)

- [ ] Sleep time settings saved to Firebase correctly
- [ ] Sleep time settings saved to SharedPreferences correctly
- [ ] Activity updates SKIPPED during sleep time (Flutter side)
- [ ] Activity updates WORK outside sleep time
- [ ] Meal recording ALWAYS works (overrides sleep time) - if Option A chosen
- [ ] App startup respects sleep time
- [ ] Settings survive app restart
- [ ] Settings survive phone reboot

### Parent App (Native Android)

- [ ] Native alarm respects sleep time (already implemented)
- [ ] Native alarm continues scheduling even when skipping updates
- [ ] GPS tracking ALWAYS works (not affected by sleep time)
- [ ] Screen on/off detection works correctly outside sleep time

### Child App

- [ ] Sleep time settings loaded from Firebase
- [ ] Sleep mode indicator shows during sleep hours
- [ ] Sleep mode indicator hides outside sleep hours
- [ ] Last activity timestamp still displayed during sleep
- [ ] Alerts suppressed during sleep time (if implemented)
- [ ] Grace period working after sleep end time (if implemented)

### Edge Cases

- [ ] Overnight sleep period (22:00 - 06:00) works correctly
- [ ] Same-day sleep period (14:00 - 16:00) works correctly
- [ ] Active days filtering works (e.g., only Mon-Fri)
- [ ] Timezone handling (if family in different timezone)
- [ ] DST transitions don't break sleep time calculation
- [ ] Sleep time disabled mid-sleep-period resumes normal monitoring

---

## Migration Plan

### Phase 1: Add Sleep Time Check to Flutter Side ✅
1. Add `isWithinSleepTime()` method to `SleepTimeSettings`
2. Load sleep settings in `firebase_service.dart`
3. Add sleep time check to `updatePhoneActivity()`
4. Test thoroughly

### Phase 2: Meal Recording Exception (If Option A) ⚠️
1. Add `ignoreSleepTime` parameter to `updatePhoneActivity()`
2. Update meal recording to pass `ignoreSleepTime: true`
3. Test meal recording during sleep time

### Phase 3: Child App Display 📱
1. Add sleep time UI components
2. Implement sleep mode card
3. Add visual indicators
4. Test display logic

### Phase 4: Firebase Functions Integration 🔥
1. Add sleep time check to Firebase Function
2. Implement alert suppression logic
3. Add grace period handling
4. Test alert timing

---

## Summary

### What Works Now ✅
- **Native alarms:** Sleep time check already implemented
- **GPS tracking:** Always works (unaffected)
- **Settings storage:** Firebase + SharedPreferences sync

### What Needs Implementation ❌
- **Flutter activity updates:** No sleep time check
- **Child app display:** No sleep mode indicator
- **Firebase Functions:** No sleep time awareness in alert logic

### Critical Path 🎯
1. **MUST FIX:** Add sleep time check to `firebase_service.dart` `updatePhoneActivity()`
2. **SHOULD HAVE:** Child app sleep mode display
3. **NICE TO HAVE:** Firebase Function alert suppression with grace period

---

## Code Changes Required

### File 1: `lib/models/sleep_time_settings.dart`
- Add `isWithinSleepTime()` extension method

### File 2: `lib/services/firebase_service.dart`
- Add `_sleepTimeSettings` field
- Add `_loadSleepSettings()` method
- Update `initialize()` to load sleep settings
- Update `updatePhoneActivity()` to check sleep time
- Update `updateFamilySettings()` to sync sleep settings
- Optional: Add `ignoreSleepTime` parameter for meal exception

### File 3: Child App - `lib/widgets/family_status_card.dart` (or similar)
- Add sleep mode detection
- Add sleep mode UI card
- Update alert display logic

### File 4: Firebase Functions - `functions/index.js`
- Add sleep time check to `checkSurvivalStatus()`
- Add grace period logic
- Update alert suppression logic

---

**End of Document**
