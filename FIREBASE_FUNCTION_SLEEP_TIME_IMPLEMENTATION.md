# Firebase Function Sleep Time Exception - Implementation Guide

## Overview

This document explains the Firebase Function that monitors elderly users for inactivity and sends survival alerts to family members. It includes the newly implemented **Sleep Time Exception** feature.

---

## Table of Contents

1. [What is Firebase Function](#what-is-firebase-function)
2. [How It Works](#how-it-works)
3. [Sleep Time Exception Feature](#sleep-time-exception-feature)
4. [Configuration](#configuration)
5. [Monitoring & Logs](#monitoring--logs)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)

---

## What is Firebase Function

### Firebase Function vs Parent App

**Firebase Function:**
- Runs on **Google's servers** (not on user's phone)
- Runs **24/7** automatically
- Works **even if parent app is killed or phone is off**
- Scheduled to run **every 15 minutes**

**Parent App:**
- Runs on elderly person's phone
- Updates Firebase every 15 minutes with survival signal
- Only works when phone is ON
- Stopped when phone is OFF or app is killed

### Why We Need Both

```
┌─────────────────────────────────────────────────────┐
│              Normal Operation                        │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Parent App (Phone ON)                               │
│    └─> Updates Firebase every 15 min                │
│                                                      │
│  Firebase Function (Google Server)                  │
│    └─> Checks every 15 min                          │
│    └─> Sees recent update                           │
│    └─> No alert needed ✅                           │
│                                                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              Emergency: Phone OFF                    │
├─────────────────────────────────────────────────────┤
│                                                      │
│  15:00 - Parent app sends last update               │
│  15:30 - Phone dies / turns off ❌                  │
│  16:00 - No update (phone is off)                   │
│  20:00 - No update (4 hours passed)                 │
│  03:00 - 12 hours passed                            │
│                                                      │
│  Firebase Function (Google Server)                  │
│    └─> Checks at 03:15                              │
│    └─> Sees lastPhoneActivity: 15:00 (12+ hours)    │
│    └─> Sends alert to family! 🚨                    │
│                                                      │
└─────────────────────────────────────────────────────┘
```

---

## How It Works

### Function Schedule

**Execution:** Every 15 minutes, automatically
**Timezone:** Asia/Seoul (Korean time)
**Schedule Definition:**
```javascript
exports.checkFamilySurvival = functions.pubsub
  .schedule('every 15 minutes')
  .timeZone('Asia/Seoul')
  .onRun(async (context) => {
    // Check all families...
  });
```

### What It Does Every 15 Minutes

```
1. Query Firestore
   ├─> Get all families where:
   │   └─> settings.survivalSignalEnabled == true
   │
2. For Each Family:
   ├─> Get lastPhoneActivity timestamp
   ├─> Get alertHours threshold (default: 12)
   ├─> Calculate: hoursSinceActivity = (now - lastPhoneActivity) / 3600000
   │
3. Check Conditions:
   ├─> If hoursSinceActivity < alertHours
   │   └─> ✅ User is active, no alert needed
   │
   ├─> If hoursSinceActivity >= alertHours
   │   ├─> Check: Is currently in sleep time?
   │   │   ├─> YES → 😴 Skip alert (sleep exception)
   │   │   └─> NO → Continue checking
   │   │
   │   ├─> Check: Is alert already active?
   │   │   ├─> YES → Skip (prevent spam)
   │   │   └─> NO → Send alert
   │   │
   │   └─> Send Alert:
   │       ├─> Update Firestore: survivalAlert.isActive = true
   │       ├─> Get child app FCM tokens
   │       └─> Send FCM notification to all child devices
   │
4. Log Results:
   └─> "✅ Family survival check completed: X families checked, Y alerts sent"
```

### Firebase Data Structure

```javascript
families/{familyId}/
{
  elderlyName: "이영훈",

  // Updated by parent app every 15 minutes
  lastPhoneActivity: Timestamp(2025-10-26 14:30:00),
  lastActivityType: "screen_on_activity",

  // Location (updated every 15 minutes)
  location: {
    latitude: 37.5665,
    longitude: 126.9780,
    timestamp: Timestamp(2025-10-26 14:30:00),
    address: ""
  },

  // Settings
  settings: {
    survivalSignalEnabled: true,
    alertHours: 12,  // Alert after 12 hours of inactivity

    // Sleep time exception settings
    sleepExclusionEnabled: true,
    sleepStartHour: 22,
    sleepStartMinute: 0,
    sleepEndHour: 6,
    sleepEndMinute: 0,
    sleepActiveDays: [1,2,3,4,5,6,7]  // Monday=1, Sunday=7
  },

  // Alert status (managed by Firebase Function)
  survivalAlert: {
    isActive: true,
    timestamp: Timestamp(2025-10-26 03:00:00),
    elderlyName: "이영훈",
    message: "12시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요.",
    hoursInactive: 12,
    locationData: { ... }
  }
}
```

---

## Sleep Time Exception Feature

### Purpose

**Problem:** When user sets survival alert threshold to a short time (e.g., 2 hours), they may receive false alerts during normal sleep hours (e.g., 22:00 - 06:00). The elderly person is sleeping, not inactive or in danger, but the lack of phone activity triggers an alert.

**Solution:**
1. **Parent App:** During sleep time, skip updating `lastPhoneActivity` (survival signal) but CONTINUE updating GPS location and battery status
2. **Firebase Function:** Check if current time is within configured sleep period before sending alert

**What Still Works During Sleep Time:**
- ✅ GPS location updates (every 15 minutes)
- ✅ Battery status updates (every 15 minutes)
- ❌ Survival signal (`lastPhoneActivity`) - SKIPPED during sleep

**Why This Matters:**
- Family can still track location and battery even during sleep
- Survival alerts are suppressed during configured sleep hours to prevent false alarms
- Example: If alert threshold is 2 hours and elderly person sleeps from 22:00 to 06:00, no alert is sent during this period

### How It Works

#### Sleep Time Check Logic

```javascript
function isCurrentlySleepTime(settings) {
  // Step 1: Check if sleep exclusion is enabled
  if (!settings || !settings.sleepExclusionEnabled) {
    return false;  // Not enabled, don't skip
  }

  // Step 2: Get current time
  const now = new Date();
  const currentHour = now.getHours();
  const currentMinute = now.getMinutes();

  // Step 3: Get sleep settings
  const sleepStartHour = settings.sleepStartHour || 22;
  const sleepStartMinute = settings.sleepStartMinute || 0;
  const sleepEndHour = settings.sleepEndHour || 6;
  const sleepEndMinute = settings.sleepEndMinute || 0;
  const sleepActiveDays = settings.sleepActiveDays || [1,2,3,4,5,6,7];

  // Step 4: Check if today is an active sleep day
  const dayOfWeek = now.getDay(); // 0=Sunday, 6=Saturday
  const mondayBased = dayOfWeek === 0 ? 7 : dayOfWeek; // Convert to Monday=1

  if (!sleepActiveDays.includes(mondayBased)) {
    return false;  // Not a sleep day
  }

  // Step 5: Convert times to minutes since midnight
  const currentMinutes = currentHour * 60 + currentMinute;
  const sleepStartMinutes = sleepStartHour * 60 + sleepStartMinute;
  const sleepEndMinutes = sleepEndHour * 60 + sleepEndMinute;

  // Step 6: Check if in sleep period
  if (sleepStartMinutes > sleepEndMinutes) {
    // Overnight period (e.g., 22:00 - 06:00)
    return currentMinutes >= sleepStartMinutes || currentMinutes <= sleepEndMinutes;
  } else {
    // Same-day period (e.g., 14:00 - 16:00)
    return currentMinutes >= sleepStartMinutes && currentMinutes <= sleepEndMinutes;
  }
}
```

#### Integration in Alert Check

```javascript
if (diffHours > alertHours) {
  console.log(`🚨 SURVIVAL ALERT: ${elderlyName} inactive for ${diffHours.toFixed(1)} hours`);

  // NEW: Check if currently in sleep time
  if (isCurrentlySleepTime(familyData.settings)) {
    const sleepStart = familyData.settings?.sleepStartHour || 22;
    const sleepEnd = familyData.settings?.sleepEndHour || 6;
    console.log(`😴 ${elderlyName} is in sleep period (${sleepStart}:00-${sleepEnd}:00) - skipping alert`);
    return;  // Skip alert
  }

  // Check if alert already active
  if (familyData.survivalAlert?.isActive) {
    console.log(`📢 Alert already active for ${elderlyName}, skipping`);
    return;
  }

  // Send alert...
}
```

### Example Scenarios

#### Scenario 1: Normal Sleep (No Alert)

```
Settings:
- sleepExclusionEnabled: true
- sleepStartHour: 22, sleepEndHour: 6
- alertHours: 12

Timeline:
21:00 - Last activity
22:00 - Sleep time starts
02:00 - Function runs (5 hours inactive)
        → Is in sleep time? YES (22:00-06:00)
        → Action: Skip alert
        → Log: "😴 이영훈 is in sleep period (22:00-6:00) - skipping alert"

06:00 - Sleep time ends
06:15 - Function runs (9.25 hours inactive)
        → Is in sleep time? NO
        → Inactive > 12h? NO (only 9.25h)
        → Action: No alert yet

10:00 - Function runs (13 hours inactive)
        → Is in sleep time? NO
        → Inactive > 12h? YES
        → Action: SEND ALERT 🚨
```

#### Scenario 2: Phone Dies During Day (Alert Sent)

```
Settings:
- sleepExclusionEnabled: true
- sleepStartHour: 22, sleepEndHour: 6
- alertHours: 12

Timeline:
14:00 - Last activity
14:30 - Phone dies
22:00 - Sleep time starts (but already inactive 8h)
02:00 - Function runs (12 hours inactive)
        → Is in sleep time? YES
        → Action: Skip alert (in sleep period)

06:00 - Sleep time ends
06:15 - Function runs (16.25 hours inactive)
        → Is in sleep time? NO
        → Inactive > 12h? YES (16.25h)
        → Action: SEND ALERT 🚨
        → Message: "16시간 이상 휴대폰 사용이 없습니다"
```

#### Scenario 3: Sleep Exclusion Disabled (Always Alert)

```
Settings:
- sleepExclusionEnabled: false
- alertHours: 12

Timeline:
21:00 - Last activity
22:00 - No signal sent (normal sleep)
09:00 - 12 hours passed
09:15 - Function runs
        → Is sleep exclusion enabled? NO
        → Inactive > 12h? YES
        → Action: SEND ALERT 🚨 (even if it's sleep time)
```

#### Scenario 4: Specific Sleep Days (Weekdays Only)

```
Settings:
- sleepExclusionEnabled: true
- sleepStartHour: 22, sleepEndHour: 6
- sleepActiveDays: [1,2,3,4,5]  // Monday-Friday only
- alertHours: 12

Saturday night (dayOfWeek = 6):
23:00 - Inactive for 13 hours
        → Is today in sleepActiveDays? NO (Saturday = 6, not in [1,2,3,4,5])
        → Is in sleep time? NO (not a sleep day)
        → Action: SEND ALERT 🚨 (weekend doesn't have sleep exception)

Tuesday night (dayOfWeek = 2):
23:00 - Inactive for 13 hours
        → Is today in sleepActiveDays? YES (Tuesday = 2)
        → Is in sleep time? YES (23:00 is between 22:00-06:00)
        → Action: Skip alert 😴
```

---

## Configuration

### Firebase Settings

To enable and configure sleep time exception, update the family document in Firestore:

#### Via Firebase Console

1. Go to Firebase Console → Firestore Database
2. Navigate to `families/{familyId}`
3. Edit the `settings` field:

```javascript
settings: {
  // Required: Enable survival monitoring
  survivalSignalEnabled: true,

  // Alert threshold (hours)
  alertHours: 12,

  // Sleep time exception settings
  sleepExclusionEnabled: true,     // Enable/disable sleep exception
  sleepStartHour: 22,               // Start hour (24-hour format)
  sleepStartMinute: 0,              // Start minute
  sleepEndHour: 6,                  // End hour (24-hour format)
  sleepEndMinute: 0,                // End minute
  sleepActiveDays: [1,2,3,4,5,6,7] // Days of week (1=Mon, 7=Sun)
}
```

#### Via Parent App Settings Screen

The parent app's settings screen should save these values to Firebase:

**File:** `lib/screens/settings_screen.dart`

When user enables sleep time exception, save to Firebase:
```dart
await FirebaseFirestore.instance
  .collection('families')
  .doc(familyId)
  .update({
    'settings.sleepExclusionEnabled': true,
    'settings.sleepStartHour': 22,
    'settings.sleepStartMinute': 0,
    'settings.sleepEndHour': 6,
    'settings.sleepEndMinute': 0,
    'settings.sleepActiveDays': [1,2,3,4,5,6,7],
  });
```

### Common Configurations

#### Default Configuration (All Days, 22:00-06:00)
```javascript
{
  sleepExclusionEnabled: true,
  sleepStartHour: 22,
  sleepStartMinute: 0,
  sleepEndHour: 6,
  sleepEndMinute: 0,
  sleepActiveDays: [1,2,3,4,5,6,7]
}
```

#### Weekdays Only (Monday-Friday)
```javascript
{
  sleepExclusionEnabled: true,
  sleepStartHour: 22,
  sleepStartMinute: 0,
  sleepEndHour: 6,
  sleepEndMinute: 0,
  sleepActiveDays: [1,2,3,4,5]  // Monday-Friday only
}
```

#### Early Sleeper (20:00-05:00)
```javascript
{
  sleepExclusionEnabled: true,
  sleepStartHour: 20,
  sleepStartMinute: 0,
  sleepEndHour: 5,
  sleepEndMinute: 0,
  sleepActiveDays: [1,2,3,4,5,6,7]
}
```

#### Afternoon Nap (14:00-16:00)
```javascript
{
  sleepExclusionEnabled: true,
  sleepStartHour: 14,
  sleepStartMinute: 0,
  sleepEndHour: 16,
  sleepEndMinute: 0,
  sleepActiveDays: [1,2,3,4,5,6,7]
}
```

#### Disable Sleep Exception
```javascript
{
  sleepExclusionEnabled: false,
  // Other settings don't matter when disabled
}
```

---

## Monitoring & Logs

### Viewing Function Logs

#### Command Line
```bash
# View recent logs for checkFamilySurvival function
firebase functions:log --only checkFamilySurvival -n 30

# View all function logs
firebase functions:log

# Follow logs in real-time (not available for scheduled functions)
# Scheduled functions only log during execution
```

#### Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `thanks-everyday`
3. Go to **Functions** in left menu
4. Click on `checkFamilySurvival`
5. Click **Logs** tab

### Understanding Log Messages

#### Normal Operation Logs

```
🔍 Checking family survival status every 15 minutes...
📊 Found 3 families with survival monitoring enabled
📱 Family family_xxx (이영훈): 2.5 hours since last activity (threshold: 12h)
📊 이영훈 status: Phone activity: 2.5h ago | Location: 2.0h ago
✅ 이영훈 is active (2.5h ago)
✅ Family survival check completed
```

**Meaning:** All families are active, no alerts needed.

#### Sleep Time Skip Logs

```
🔍 Checking family survival status every 15 minutes...
📊 Found 2 families with survival monitoring enabled
📱 Family family_xxx (이영훈): 13.2 hours since last activity (threshold: 12h)
📊 이영훈 status: Phone activity: 13.2h ago | Location: 13.0h ago
🚨 SURVIVAL ALERT: 이영훈 inactive for 13.2 hours
😴 이영훈 is in sleep period (22:00-6:00) - skipping alert
✅ Family survival check completed
```

**Meaning:** User is inactive for 13+ hours, but currently in sleep time, so alert is skipped.

#### Alert Sent Logs

```
🔍 Checking family survival status every 15 minutes...
📊 Found 2 families with survival monitoring enabled
📱 Family family_xxx (이영훈): 14.5 hours since last activity (threshold: 12h)
📊 이영훈 status: Phone activity: 14.5h ago | Location: 14.3h ago
🚨 SURVIVAL ALERT: 이영훈 inactive for 14.5 hours
✅ Survival alert status updated for 이영훈
📢 Sending survival notification for 이영훈
📱 Sending alert to 2 child device(s)
✅ Survival alert sent to token: abc123... MessageID: xyz789
✅ Survival alert sent to token: def456... MessageID: uvw012
✅ Survival alerts sent: 2/2
✅ Family survival check completed
```

**Meaning:** User inactive for 14+ hours, NOT in sleep time, alert sent to 2 child devices.

#### Already Active Alert (Preventing Spam)

```
🔍 Checking family survival status every 15 minutes...
📊 Found 2 families with survival monitoring enabled
📱 Family family_xxx (p000): 108.6 hours since last activity (threshold: 1h)
🚨 SURVIVAL ALERT: p000 inactive for 108.6 hours
📢 Alert already active for p000, skipping
✅ Family survival check completed
```

**Meaning:** Alert already sent previously, not sending duplicate alert.

### Log Analysis

#### Check When Function Last Ran

```bash
firebase functions:log --only checkFamilySurvival -n 1
```

Look for timestamp like:
```
2025-10-26T13:38:01.930810088Z
```

This shows the last execution time in UTC. Convert to Korean time (UTC+9).

#### Count Alert Frequency

```bash
firebase functions:log --only checkFamilySurvival -n 100 | grep "🚨 SURVIVAL ALERT"
```

Shows how many alerts were triggered in recent executions.

#### Check Sleep Time Skips

```bash
firebase functions:log --only checkFamilySurvival -n 100 | grep "😴"
```

Shows when alerts were skipped due to sleep time.

---

## Testing

### Test 1: Verify Function is Running

**Goal:** Confirm function executes every 15 minutes

**Steps:**
1. Wait for next 15-minute mark (e.g., 14:15, 14:30, 14:45, 15:00)
2. Wait 1 minute for execution to complete
3. Check logs:
```bash
firebase functions:log --only checkFamilySurvival -n 10
```

**Expected Result:**
- See log entry with timestamp within last 2 minutes
- See: `🔍 Checking family survival status every 15 minutes...`
- See: `📊 Found X families with survival monitoring enabled`
- See: `✅ Family survival check completed`

### Test 2: Test Sleep Time Exception (Daytime)

**Goal:** Verify sleep time check works during day

**Setup:**
1. Set test family's `lastPhoneActivity` to 14 hours ago
2. Configure sleep time: 22:00 - 06:00
3. Enable sleep exclusion
4. Current time should be between 08:00 - 21:00 (NOT in sleep period)

**Steps:**
```javascript
// Update in Firebase Console
families/TEST_FAMILY_ID
{
  lastPhoneActivity: <14 hours ago>,
  settings: {
    survivalSignalEnabled: true,
    alertHours: 12,
    sleepExclusionEnabled: true,
    sleepStartHour: 22,
    sleepEndHour: 6
  }
}
```

**Wait for next function execution (up to 15 minutes)**

**Expected Result:**
```
📱 Family TEST_FAMILY_ID (Test User): 14.0 hours since last activity (threshold: 12h)
🚨 SURVIVAL ALERT: Test User inactive for 14.0 hours
✅ Survival alert status updated for Test User
📢 Sending survival notification for Test User
```

**Alert should be sent** because it's NOT in sleep time.

### Test 3: Test Sleep Time Exception (Night)

**Goal:** Verify alert is skipped during sleep time

**Setup:**
1. Set test family's `lastPhoneActivity` to 14 hours ago
2. Configure sleep time: 22:00 - 06:00
3. Enable sleep exclusion
4. Current time should be between 22:00 - 06:00 (IN sleep period)
   - If testing during day, temporarily change sleep time to include current hour

**Steps:**
```javascript
// For testing during day (e.g., current time is 15:00)
families/TEST_FAMILY_ID
{
  lastPhoneActivity: <14 hours ago>,
  settings: {
    survivalSignalEnabled: true,
    alertHours: 12,
    sleepExclusionEnabled: true,
    sleepStartHour: 14,  // Temporarily set to include current time
    sleepEndHour: 16
  }
}
```

**Wait for next function execution**

**Expected Result:**
```
📱 Family TEST_FAMILY_ID (Test User): 14.0 hours since last activity (threshold: 12h)
🚨 SURVIVAL ALERT: Test User inactive for 14.0 hours
😴 Test User is in sleep period (14:00-16:00) - skipping alert
```

**Alert should NOT be sent** because it's in sleep time.

### Test 4: Test Sleep Exception Disabled

**Goal:** Verify alert is always sent when sleep exception disabled

**Setup:**
```javascript
families/TEST_FAMILY_ID
{
  lastPhoneActivity: <14 hours ago>,
  settings: {
    survivalSignalEnabled: true,
    alertHours: 12,
    sleepExclusionEnabled: false  // Disabled
  }
}
```

**Expected Result:**
Alert should be sent regardless of current time (no sleep check).

### Test 5: Test Specific Sleep Days

**Goal:** Verify sleep exception only applies on configured days

**Setup (Monday test):**
```javascript
families/TEST_FAMILY_ID
{
  lastPhoneActivity: <14 hours ago>,
  settings: {
    sleepExclusionEnabled: true,
    sleepStartHour: 22,
    sleepEndHour: 6,
    sleepActiveDays: [2,3,4,5,6]  // Tuesday-Saturday only (excluding Monday)
  }
}
```

**Test on Monday night (between 22:00-06:00):**
- Expected: Alert SENT (Monday not in sleepActiveDays)

**Test on Tuesday night (between 22:00-06:00):**
- Expected: Alert SKIPPED (Tuesday in sleepActiveDays)

---

## Troubleshooting

### Issue 1: Function Not Running

**Symptoms:**
- No logs appearing in last 15 minutes
- Last log entry is hours old

**Possible Causes & Solutions:**

1. **Function deployment failed**
   ```bash
   # Check deployment status
   firebase functions:list

   # Should show:
   # checkFamilySurvival | v1 | scheduled | us-central1

   # If not listed, redeploy:
   firebase deploy --only functions
   ```

2. **Cloud Scheduler disabled**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Select project: `thanks-everyday`
   - Go to: Cloud Scheduler
   - Check if `firebase-schedule-checkFamilySurvival-...` is enabled
   - If paused, click "Enable"

3. **Billing issues**
   - Cloud Functions require Blaze Plan (pay-as-you-go)
   - Check Firebase Console → Spark plan → Upgrade to Blaze

### Issue 2: Sleep Time Not Working

**Symptoms:**
- Alerts sent during sleep time
- No `😴` emoji in logs during sleep period

**Check:**

1. **Verify settings in Firestore:**
   ```javascript
   families/{familyId}/settings
   {
     sleepExclusionEnabled: true,  // Must be true
     sleepStartHour: 22,
     sleepStartMinute: 0,
     sleepEndHour: 6,
     sleepEndMinute: 0,
     sleepActiveDays: [1,2,3,4,5,6,7]
   }
   ```

2. **Check current day of week:**
   - Monday = 1, Sunday = 7
   - Verify current day is in `sleepActiveDays` array

3. **Check time calculation:**
   - Function uses Korean time (Asia/Seoul)
   - Verify current hour is between start and end hours

4. **Check function code:**
   ```bash
   # View deployed function code
   cat /Users/yeonghun/thanks_everyday/functions/index.js | grep -A 30 "isCurrentlySleepTime"
   ```

### Issue 3: No Alerts Being Sent

**Symptoms:**
- User inactive for 12+ hours
- NOT in sleep time
- No alert sent

**Check:**

1. **Verify survival monitoring enabled:**
   ```javascript
   families/{familyId}/settings
   {
     survivalSignalEnabled: true  // Must be true
   }
   ```

2. **Check if alert already active:**
   ```javascript
   families/{familyId}/survivalAlert
   {
     isActive: true,  // If true, no duplicate alert sent
     timestamp: <...>
   }
   ```

   **Solution:** Clear the alert:
   ```javascript
   survivalAlert: {
     isActive: false
   }
   ```

3. **Check child app tokens exist:**
   - Go to: `families/{familyId}/child_devices`
   - Verify documents exist with:
     - `fcm_token`: (not null)
     - `is_active`: true

4. **Check logs for errors:**
   ```bash
   firebase functions:log --only checkFamilySurvival -n 50 | grep "❌"
   ```

### Issue 4: Duplicate Alerts

**Symptoms:**
- Multiple alerts sent for same inactivity period
- Family receiving too many notifications

**Solution:**

Function should automatically prevent duplicates by checking `survivalAlert.isActive`.

If duplicates still occur:

1. **Check function code** has duplicate prevention:
   ```javascript
   if (currentAlert?.isActive) {
     console.log(`📢 Alert already active for ${elderlyName}, skipping`);
     return;
   }
   ```

2. **Add cooldown period** (optional enhancement):
   ```javascript
   if (currentAlert?.isActive) {
     const hoursSinceAlert = (now - currentAlert.timestamp) / (1000 * 60 * 60);
     if (hoursSinceAlert < 6) {  // Don't re-alert within 6 hours
       console.log(`⏰ Alert sent ${hoursSinceAlert}h ago, skipping`);
       return;
     }
   }
   ```

### Issue 5: Function Timeout

**Symptoms:**
- Logs show: `Function execution took too long`
- Function stops before checking all families

**Solution:**

1. **Increase timeout:**
   ```javascript
   exports.checkFamilySurvival = functions
     .runWith({ timeoutSeconds: 300 })  // 5 minutes
     .pubsub.schedule('every 15 minutes')
     // ...
   ```

2. **Deploy:**
   ```bash
   firebase deploy --only functions
   ```

### Issue 6: High Costs

**Symptoms:**
- Unexpected Firebase bill
- Firestore reads exceeding free tier

**Check Usage:**
1. Go to Firebase Console → Usage and Billing
2. Check:
   - Firestore reads per day
   - Function invocations per month
   - Function compute time

**Optimize:**

1. **Add query filter** (for 1000+ families):
   ```javascript
   // Instead of querying all families:
   const familiesSnapshot = await admin.firestore()
     .collection('families')
     .where('settings.survivalSignalEnabled', '==', true)
     .get();

   // Query only potentially inactive families:
   const twelveHoursAgo = new Date(Date.now() - 12 * 60 * 60 * 1000);
   const familiesSnapshot = await admin.firestore()
     .collection('families')
     .where('settings.survivalSignalEnabled', '==', true)
     .where('lastPhoneActivity', '<', twelveHoursAgo)
     .get();
   ```

2. **Reduce check frequency:**
   ```javascript
   // Change from every 15 minutes to every 30 minutes
   .schedule('every 30 minutes')
   ```

---

## Deployment

### Initial Deployment

Already completed! Function is deployed and running.

### Update Deployment

When you make changes to `functions/index.js`:

```bash
cd /Users/yeonghun/thanks_everyday
firebase deploy --only functions
```

**Expected output:**
```
✔  functions[checkFamilySurvival(us-central1)] Successful update operation.
```

### Rollback

If new deployment has issues:

```bash
# List versions
firebase functions:list

# Rollback to previous version
firebase functions:rollback checkFamilySurvival
```

---

## Summary

### What We Implemented

✅ **Firebase Cloud Function** runs every 15 minutes on Google's servers
✅ **Survival Alert System** checks all families for inactivity
✅ **Sleep Time Exception** skips alerts during configured sleep hours
✅ **Duplicate Prevention** avoids spamming family with alerts
✅ **Multi-device Support** sends to all connected child apps
✅ **Automatic Clearing** removes alert when person becomes active

### Key Benefits

1. **Works 24/7** - Even when parent phone is OFF
2. **Independent** - Runs on Google's servers, not user's phone
3. **Reliable** - Scheduled execution guaranteed by Google
4. **Smart** - Respects sleep time to avoid false alerts
5. **Flexible** - Configurable per family

### Configuration Quick Reference

```javascript
families/{familyId}/settings
{
  // Required
  survivalSignalEnabled: true,
  alertHours: 12,

  // Sleep time exception
  sleepExclusionEnabled: true,
  sleepStartHour: 22,
  sleepStartMinute: 0,
  sleepEndHour: 6,
  sleepEndMinute: 0,
  sleepActiveDays: [1,2,3,4,5,6,7]
}
```

### Monitoring Commands

```bash
# View recent logs
firebase functions:log --only checkFamilySurvival -n 30

# Check deployment
firebase functions:list

# View function in console
open https://console.firebase.google.com/project/thanks-everyday/functions
```

---

**Document Version:** 1.0
**Last Updated:** 2025-10-26
**Function Version:** Deployed with sleep time exception
**Schedule:** Every 15 minutes
**Timezone:** Asia/Seoul
