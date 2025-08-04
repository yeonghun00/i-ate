# Smart Usage Detection Testing Guide

## Overview
This document outlines testing procedures for the new **Enhanced Hybrid Usage Detection** system that combines immediate critical alerts with efficient batch updates.

## System Architecture

### Immediate Updates (Critical Events)
- **Screen ON/OFF events** - Instant Firebase updates for survival signal
- **Extended inactivity alerts** - When inactivity ≥ alert threshold
- **Activity resumption** - After long periods of inactivity (2+ hours)

### Batch Updates (Every 15 Minutes) 
- **Usage pattern summaries** - App interactions, screen time, activity score
- **Routine activity** - Non-critical status changes
- **Keep-alive updates** - Ensure data freshness even during low activity

### Smart Logic
- **Conditional updates** - Only update Firebase when meaningful changes occur
- **Activity scoring** - 0-100 score based on screen interactions, app usage, active time
- **Emergency detection** - Immediate alerts for critical situations

## Testing Scenarios

### 1. Critical Event Testing

#### Test 1.1: Extended Inactivity Alert
**Objective**: Verify immediate Firebase updates for extended inactivity

**Steps**:
1. Enable survival signal monitoring
2. Set alert threshold to 2 hours (for testing)
3. Don't use phone for 2+ hours
4. Check Firebase for immediate update when threshold reached

**Expected Results**:
- Immediate Firebase update when 2-hour threshold hit
- `isImmedateUpdate: true` in Firebase data
- Child app receives push notification immediately

#### Test 1.2: Activity Resumption After Long Break
**Objective**: Test immediate updates when resuming activity after extended break

**Steps**:
1. Leave phone inactive for 3+ hours
2. Turn screen ON
3. Check Firebase update timing

**Expected Results**:
- Immediate Firebase update within seconds of screen ON
- `lastActivityType: 'critical_activity_resume'` in Firebase
- `previous_inactive_hours` field showing duration

#### Test 1.3: Screen OFF Events
**Objective**: Verify screen OFF events trigger immediate survival signal updates

**Steps**:
1. Use phone normally
2. Turn screen OFF
3. Check Firebase update timing

**Expected Results**:
- Immediate Firebase update within 5 seconds
- `lastActivityType: 'screen_off'`
- Session duration recorded

### 2. Batch Update Testing

#### Test 2.1: 15-Minute Activity Summary
**Objective**: Test batch updates during normal usage

**Steps**:
1. Use phone normally for 15+ minutes (open apps, scroll, interact)
2. Wait for 15-minute batch update
3. Check Firebase data structure

**Expected Results**:
- Update exactly at 15-minute intervals
- `isBatchUpdate: true` in Firebase
- `activityWindow` object with usage statistics:
  ```json
  {
    "screenOnCount": 8,
    "appInteractions": 24,
    "totalActiveMinutes": 12,
    "activityScore": 75,
    "windowStart": "2025-01-01T10:00:00.000Z",
    "windowEnd": "2025-01-01T10:15:00.000Z"
  }
  ```

#### Test 2.2: Low Activity Batch Skipping
**Objective**: Verify batch updates are skipped when no significant activity

**Steps**:
1. Leave phone idle for 15+ minutes (no screen interactions)
2. Check if batch update occurs

**Expected Results**:
- Batch update should be SKIPPED
- Log message: "Skipping batch update - no significant changes"
- Firebase not updated unnecessarily

#### Test 2.3: Keep-Alive Updates
**Objective**: Test forced updates after 45+ minutes of no Firebase updates

**Steps**:
1. Use phone very minimally for 45+ minutes
2. Check for forced keep-alive update

**Expected Results**:
- Update occurs after 45+ minutes regardless of activity
- Prevents data staleness

### 3. Usage Stats Accuracy Testing

#### Test 3.1: App Usage Detection
**Objective**: Verify app interactions are detected properly

**Steps**:
1. Open different apps (social media, browser, games)
2. Use each app for 2-3 minutes
3. Check usage detection logs

**Expected Results**:
- App usage events logged every 2 minutes
- `appInteractionCount` increases appropriately
- `lastAppUsage` timestamp updates

#### Test 3.2: Screen Interaction vs App Usage
**Objective**: Test distinction between screen events and app usage

**Steps**:
1. Turn screen ON/OFF multiple times without using apps
2. Use apps without turning screen OFF
3. Compare detection patterns

**Expected Results**:
- Screen events trigger immediate updates
- App usage contributes to batch activity score
- Both types properly recorded in Firebase

### 4. Performance & Battery Testing

#### Test 4.1: Battery Drain Analysis
**Objective**: Measure battery impact of enhanced monitoring

**Setup**:
- Test device: Android phone with fresh battery
- Test duration: 24 hours
- Monitoring: Built-in battery usage statistics

**Control Test** (Baseline):
1. Disable smart usage detection
2. Run only basic screen monitoring for 24 hours
3. Record battery usage percentage

**Enhanced Test**:
1. Enable smart usage detection
2. Run for 24 hours with normal usage
3. Record battery usage percentage

**Expected Results**:
- Battery impact increase should be <2% per day
- Background CPU usage should be minimal
- No significant heating issues

#### Test 4.2: Firebase Write Frequency
**Objective**: Verify Firebase writes are optimized for cost

**Steps**:
1. Monitor Firebase writes for 24-hour period
2. Count immediate vs batch updates
3. Calculate daily write cost

**Expected Metrics**:
```
Daily Firebase Writes (Target):
- Immediate updates: ~48 (screen events + emergencies)
- Batch updates: 48-96 (every 15 min, conditional)
- Total: 96-144 writes/day
- Cost: ~$0.22/month per family
```

**Baseline Comparison**:
- Old system: ~48 writes/day (screen only)
- New system: ~96-144 writes/day (enhanced detection)
- Cost increase: ~50-100%
- Detection accuracy increase: ~300%

### 5. Edge Case Testing

#### Test 5.1: Permission Errors
**Objective**: Test behavior when usage stats permission is denied

**Steps**:
1. Deny "Usage Access" permission
2. Enable smart usage detection
3. Verify fallback behavior

**Expected Results**:
- Falls back to screen event monitoring only
- Logs permission warning
- No app crashes or errors

#### Test 5.2: Firebase Connection Loss
**Objective**: Test offline behavior and retry logic

**Steps**:
1. Disable internet connection
2. Use phone normally for 30 minutes
3. Re-enable internet
4. Check data synchronization

**Expected Results**:
- Local state preserved during offline period
- Firebase updates resume when connection restored
- No data loss

#### Test 5.3: App Background/Foreground Transitions
**Objective**: Test monitoring during app lifecycle changes

**Steps**:
1. Open app, then background it
2. Use other apps
3. Return to app after various intervals
4. Check data continuity

**Expected Results**:
- Monitoring continues in background
- Data consistency maintained
- Smooth transitions between states

## Performance Benchmarks

### Target Metrics
- **Battery Impact**: <2% additional drain per day
- **Firebase Writes**: 96-144 per day (vs 48 baseline)
- **Detection Accuracy**: 90%+ for actual phone usage
- **False Positives**: <5% (phantom activity detection)
- **Response Time**: <30 seconds for critical alerts

### Monitoring Commands

```bash
# Check battery usage (Android)
adb shell dumpsys batterystats --checkin | grep -E "^9,"

# Monitor Firebase writes
firebase firestore:indexes

# Check app memory usage
adb shell dumpsys meminfo com.thousandemfla.thanks_everyday

# Monitor CPU usage
adb shell top -n 1 | grep thanks_everyday
```

## Troubleshooting Guide

### Common Issues

1. **No batch updates occurring**
   - Check usage stats permission
   - Verify 15-minute timer is running
   - Look for "activity score" logs

2. **Too many Firebase writes**
   - Check if immediate updates are being triggered unnecessarily
   - Verify batch skipping logic
   - Monitor activity score calculation

3. **Missing app usage detection**
   - Ensure "Usage Access" permission granted
   - Check Android version compatibility (API 21+)
   - Verify app is in foreground during test

4. **Battery drain issues**
   - Check background timer intervals
   - Verify wake locks are properly released
   - Monitor for excessive Firebase connections

### Debug Logs

Enable verbose logging to monitor system behavior:

```dart
// In SmartUsageDetector
print('📦 Batch update completed - Activity Score: $activityScore');
print('⚡ Immediate Firebase update completed: $eventType');
print('📊 Usage check completed - Activity: $hasRecentActivity');
```

## Conclusion

This enhanced system provides:
- **Better accuracy**: Detects actual phone usage, not just screen events
- **Cost efficiency**: Smart batching reduces unnecessary Firebase writes
- **Emergency response**: Immediate alerts for critical situations
- **Battery optimization**: Minimal additional power consumption

The hybrid approach balances real-time responsiveness for emergencies with cost-effective batch processing for routine monitoring.