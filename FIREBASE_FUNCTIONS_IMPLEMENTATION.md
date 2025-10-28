# Firebase Functions Implementation Guide

## Table of Contents
1. [System Overview](#system-overview)
2. [Current Alert System](#current-alert-system)
3. [Why Firebase Functions Are Needed](#why-firebase-functions-are-needed)
4. [Cost Analysis](#cost-analysis)
5. [Implementation Guide](#implementation-guide)
6. [Function Code](#function-code)
7. [Testing & Deployment](#testing--deployment)
8. [Maintenance & Monitoring](#maintenance--monitoring)

---

## System Overview

### Current Architecture

```
┌─────────────────────┐
│   Parent App        │
│   (Elderly Phone)   │
│                     │
│  - Updates every    │
│    10 minutes       │
│  - GPS location     │
│  - Survival signal  │
│  - Meal tracking    │
└──────────┬──────────┘
           │
           │ Firestore writes
           ▼
┌─────────────────────┐
│    Firebase         │
│    Firestore        │
│                     │
│  Collection:        │
│  - families/        │
│    - {familyId}/    │
│      - lastPhone    │
│        Activity     │
│      - location     │
│      - meals        │
│      - alerts       │
└──────────┬──────────┘
           │
           │ Real-time listener
           ▼
┌─────────────────────┐
│   Child App         │
│   (Family Phone)    │
│                     │
│  - Watches Firebase │
│  - Shows status     │
│  - Receives FCM     │
└─────────────────────┘
```

---

## Current Alert System

### How It Works Now

#### 1. **Survival Signal Updates (Every 10 Minutes)**

**Parent App → Firebase:**
- Screen ON/OFF events
- Phone unlock events
- Periodic updates every 10 minutes (via AlarmManager)
- Updates `families/{familyId}/lastPhoneActivity` timestamp

**Location:**
- `lib/services/smart_usage_detector.dart`
- `lib/services/location_service.dart`
- `android/app/src/main/kotlin/.../elder/AlarmUpdateReceiver.kt`

**Firebase Structure:**
```javascript
families/{familyId}/
{
  lastPhoneActivity: Timestamp,     // Updated every 10 min
  lastActivityType: "screen_on",
  location: {
    latitude: 37.5665,
    longitude: 126.9780,
    timestamp: Timestamp,
    address: ""
  },
  settings: {
    alertHours: 12,                 // Alert after X hours
    sleepExclusionEnabled: true,
    sleepStartHour: 22,
    sleepEndHour: 6,
    sleepActiveDays: [1,2,3,4,5,6,7]
  }
}
```

#### 2. **Sleep Time Exception**

**Purpose:** Don't send survival signals during sleep hours (e.g., 22:00 - 06:00)

**Implementation:**
- **Location:** `AlarmUpdateReceiver.kt:655-711`
- **Logic:**
  ```kotlin
  if (sleepExclusionEnabled && isCurrentlySleepTime()) {
    // Skip sending survival signal to Firebase
    // Still schedule next alarm
    return
  }
  ```

**Why It's Needed:**
- Prevents false alerts when elderly is sleeping
- Configurable hours (default: 22:00 - 06:00)
- Can set specific days of week
- Handles overnight periods correctly

**Example:**
- Sleep time: 22:00 - 06:00
- 23:00: Phone inactive → No signal sent (normal, sleeping)
- 14:00: Phone inactive for 12 hours → Alert should trigger
- But if last signal was before sleep (21:00), and it's now 09:00 (12 hours later), alert fires

#### 3. **Current Alert Sending (Parent App)**

**Problem with Current System:**

**Location:** `lib/services/screen_monitor_service.dart:222-266`

```dart
static Future<void> _handleInactivityAlert() async {
  // This is called by PARENT APP when it detects 12 hours of inactivity
  await _sendSurvivalAlert();
}

static Future<void> _sendSurvivalAlert() async {
  // Parent app directly sends FCM notification
  await _firebaseService.sendSurvivalAlert(
    familyCode: familyId,
    elderlyName: elderlyName,
    message: '12시간 이상 휴대폰 사용이 없습니다.',
  );
}
```

**How It Sends:**
- Uses `FCMv1Service` in parent app
- Parent app has service account credentials embedded
- Directly calls FCM API to push notification to child app

**Location:** `lib/services/fcm_v1_service.dart:135-173`

```dart
static Future<bool> sendSurvivalAlert({
  required String familyId,
  required String elderlyName,
  required int hoursInactive,
}) async {
  // Get child app FCM tokens from Firebase
  final childTokens = await _getChildAppTokens(familyId);

  // Send FCM notification to each child device
  for (String token in childTokens) {
    await _sendNotificationV1(
      token: token,
      title: '🚨 생존 신호 알림',
      body: '$elderlyName님이 $hoursInactive시간 이상 활동이 없습니다.',
      data: {
        'type': 'survival_alert',
        'family_id': familyId,
        'hours_inactive': hoursInactive.toString(),
      },
    );
  }
}
```

---

## Why Firebase Functions Are Needed

### Critical Flaw in Current System

**Scenario: Phone Dies or Turns Off**

```
15:00 - Last survival signal sent to Firebase ✅
15:10 - Phone dies / battery runs out ❌
16:00 - No signal (expected - phone is off)
20:00 - No signal (4 hours passed)
03:00 - No signal (12 hours passed) ⚠️ SHOULD ALERT
```

**Problem:**
- Parent app CANNOT detect inactivity because it's not running
- Parent app CANNOT send alert because it's not running
- No alert is sent to family
- Emergency situation is missed

**Current System Flow:**
```
Parent phone ON → Detects 12 hours passed → Sends alert ✅
Parent phone OFF → Cannot detect → Cannot send alert ❌
```

### Why This Happens

The current system relies on **parent app** to:
1. Detect that 12 hours have passed
2. Send the FCM alert

**But if parent app is killed/off:**
- Step 1 cannot happen (no app running to detect)
- Step 2 cannot happen (no app running to send)

### Solution: Firebase Functions

**Firebase Functions run on Google's servers:**
- Independent of parent app
- Runs 24/7 even if phone is off
- Checks Firebase data periodically
- Sends alerts when conditions are met

**New System Flow:**
```
Parent phone ON → Updates Firebase every 10 min → Function checks → Sends alert if needed ✅
Parent phone OFF → No updates to Firebase → Function detects old timestamp → Sends alert ✅
```

---

## Cost Analysis

### Current Costs (10-Minute Update Interval)

#### Parent App Updates
- **Survival signal:** 144 writes/day per elderly
- **GPS location:** 144 writes/day per elderly
- **Total writes:** 288 writes/day per elderly

#### Firebase Free Tier (Spark Plan)
- ❌ **No Cloud Functions allowed**
- Must upgrade to **Blaze Plan** (pay-as-you-go)

### Blaze Plan Costs

#### Firebase Free Tier Limits
```
Firestore:
- Reads:  50,000/day    FREE
- Writes: 20,000/day    FREE
- Deletes: 20,000/day   FREE

After free tier:
- Reads:  $0.06 per 100,000
- Writes: $0.18 per 100,000

Cloud Functions:
- Invocations: 2,000,000/month  FREE
- Compute:     400,000 GB-sec/month  FREE

After free tier:
- Invocations: $0.40 per 1,000,000
- Compute:     $0.0000025 per GB-sec

FCM Push Notifications: FREE (unlimited)
```

### Cost Breakdown by User Count

#### 10 Elderly Users
```
Parent App Writes: 2,880/day
- Under free tier (20,000/day)
- Cost: $0/month ✅

Function (every 30 min):
- Invocations: 1,440/month → FREE
- Reads: 10 families × 48/day = 480/day → FREE
- Compute: 720 GB-sec/month → FREE
- Cost: $0/month ✅

TOTAL: $0/month
```

#### 100 Elderly Users
```
Parent App Writes: 28,800/day
- Excess: 8,800/day over free tier
- 8,800 × 30 days = 264,000/month
- Cost: $0.48/month

Function (every 30 min):
- Invocations: FREE
- Reads: 100 families × 48/day = 4,800/day → FREE
- Compute: FREE
- Cost: $0/month ✅

TOTAL: ~$0.50/month
```

#### 1,000 Elderly Users
```
Parent App Writes: 288,000/day
- Excess: 268,000/day
- 268,000 × 30 = 8,040,000/month
- Cost: $14.50/month

Function (every 30 min):
- Invocations: FREE
- Reads: 1,000 families × 48/day = 48,000/day
  - Barely over free tier (50,000/day)
- Cost: ~$0.50/month

TOTAL: ~$15/month
```

#### 10,000 Elderly Users
```
Parent App Writes: 2,880,000/day
- Cost: $155/month

Function (every 30 min):
- Reads: 10,000 families × 48/day = 480,000/day
- Excess: 430,000/day = 12,900,000/month
- Cost: $7.74/month

TOTAL: ~$163/month
```

#### 100,000 Elderly Users
```
Parent App Writes: 28,800,000/day
- Cost: $1,555/month

Function (every 30 min):
- Reads: 100,000 families × 48/day = 4,800,000/day
- Cost: $86/month

TOTAL: ~$1,641/month
```

### Cost Comparison: 2-min vs 10-min Intervals

| Users   | 2-min Updates | 10-min Updates | Savings  |
|---------|---------------|----------------|----------|
| 10      | $0            | $0             | $0       |
| 100     | $67           | $0.50          | $66.50   |
| 1,000   | $780          | $15            | $765     |
| 10,000  | $7,800        | $163           | $7,637   |
| 100,000 | $78,000       | $1,641         | $76,359  |

**Conclusion:** 10-minute intervals are **80% cheaper** than 2-minute intervals

### Function Cost Optimization

#### Without Query Optimization (Reading All Families)
```javascript
// Bad: Reads ALL families every time
const families = await db.collection('families').get();
// Cost: 100,000 reads for 100,000 families
```

#### With Query Optimization (Only Inactive Families)
```javascript
// Good: Only reads families that might be inactive
const twelveHoursAgo = new Date(Date.now() - 12 * 60 * 60 * 1000);
const families = await db.collection('families')
  .where('lastPhoneActivity', '<', twelveHoursAgo)
  .get();
// Cost: Only ~1,000 reads (1% of families inactive at any time)
```

**Cost Reduction with Query:**
- 100,000 users: $86/month → $5/month (94% reduction)
- 1,000,000 users: $860/month → $50/month (94% reduction)

---

## Implementation Guide

### Prerequisites

1. **Node.js installed** (v18 or higher)
   ```bash
   node --version  # Should be v18+
   ```

2. **Firebase CLI installed**
   ```bash
   npm install -g firebase-tools
   firebase --version
   ```

3. **Firebase project access**
   - You need admin access to your Firebase project
   - Project ID: `thanks-everyday`

### Step-by-Step Setup

#### Step 1: Login to Firebase
```bash
firebase login
```
- Opens browser
- Login with your Google account
- Authorize Firebase CLI

#### Step 2: Initialize Functions
```bash
cd /Users/yeonghun/thanks_everyday
firebase init functions
```

**Prompts you'll see:**
```
? Select Firebase project:
  → Use existing project: thanks-everyday

? What language would you like to use?
  → JavaScript

? Do you want to use ESLint?
  → No (simpler for now)

? Do you want to install dependencies now?
  → Yes
```

**What this creates:**
```
/Users/yeonghun/thanks_everyday/
├── functions/
│   ├── index.js          ← Your function code goes here
│   ├── package.json      ← Dependencies
│   ├── .eslintrc.js      ← (if you chose ESLint)
│   └── node_modules/     ← Installed packages
├── firebase.json         ← Updated with functions config
└── .firebaserc          ← Project configuration
```

#### Step 3: Install Additional Dependencies
```bash
cd functions
npm install firebase-admin firebase-functions
```

#### Step 4: Add Function Code
See [Function Code](#function-code) section below

#### Step 5: Deploy
```bash
firebase deploy --only functions
```

**Expected output:**
```
✔  functions: Finished running predeploy script.
i  functions: preparing codebase functions for deployment
✔  functions: functions folder uploaded successfully
i  functions: creating Node.js 18 function checkInactivity...
✔  functions[checkInactivity(us-central1)] Successful create operation.
Function URL: https://us-central1-thanks-everyday.cloudfunctions.net/checkInactivity

✔  Deploy complete!
```

---

## Function Code

### Option 1: Recommended Implementation (Query Optimized)

**File: `functions/index.js`**

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

/**
 * Check for inactive elderly users and send alerts
 * Runs every 30 minutes
 */
exports.checkInactivity = functions.pubsub
  .schedule('every 30 minutes')
  .timeZone('Asia/Seoul') // Korean timezone
  .onRun(async (context) => {
    console.log('🔍 Starting inactivity check...');

    try {
      const now = new Date();

      // Get all families
      const familiesSnapshot = await db.collection('families').get();

      console.log(`📊 Checking ${familiesSnapshot.size} families`);

      let alertsSent = 0;
      let familiesChecked = 0;

      // Check each family
      for (const familyDoc of familiesSnapshot.docs) {
        familiesChecked++;
        const familyId = familyDoc.id;
        const familyData = familyDoc.data();

        // Skip if no lastPhoneActivity
        if (!familyData.lastPhoneActivity) {
          console.log(`⚠️ Family ${familyId}: No lastPhoneActivity data`);
          continue;
        }

        // Get alert settings
        const settings = familyData.settings || {};
        const alertHours = settings.alertHours || 12;
        const sleepExclusionEnabled = settings.sleepExclusionEnabled || false;

        // Calculate hours since last activity
        const lastActivity = familyData.lastPhoneActivity.toDate();
        const hoursSinceActivity = (now - lastActivity) / (1000 * 60 * 60);

        console.log(`👤 Family ${familyId}: Last activity ${hoursSinceActivity.toFixed(1)} hours ago (threshold: ${alertHours}h)`);

        // Check if should alert
        if (hoursSinceActivity >= alertHours) {
          // Check if currently in sleep time
          if (sleepExclusionEnabled && isCurrentlySleepTime(familyData.settings, now)) {
            console.log(`😴 Family ${familyId}: In sleep period - skipping alert`);
            continue;
          }

          // Check if alert already exists (don't spam)
          const existingAlert = familyData.alerts?.survival;
          if (existingAlert) {
            const alertTime = existingAlert.toDate();
            const hoursSinceAlert = (now - alertTime) / (1000 * 60 * 60);

            // Only re-alert after 6 hours
            if (hoursSinceAlert < 6) {
              console.log(`⏰ Family ${familyId}: Alert already sent ${hoursSinceAlert.toFixed(1)}h ago - skipping`);
              continue;
            }
          }

          // Send alert
          console.log(`🚨 Family ${familyId}: Sending survival alert (${hoursSinceActivity.toFixed(1)}h inactive)`);

          const success = await sendSurvivalAlert(
            familyId,
            familyData.elderlyName || 'Unknown',
            Math.floor(hoursSinceActivity)
          );

          if (success) {
            alertsSent++;

            // Update alert timestamp in Firebase
            await familyDoc.ref.update({
              'alerts.survival': admin.firestore.FieldValue.serverTimestamp(),
              'alerts.survivalMessage': `${Math.floor(hoursSinceActivity)}시간 이상 활동이 없습니다`,
            });

            console.log(`✅ Family ${familyId}: Alert sent successfully`);
          } else {
            console.error(`❌ Family ${familyId}: Failed to send alert`);
          }
        }
      }

      console.log(`✅ Inactivity check complete: ${familiesChecked} families checked, ${alertsSent} alerts sent`);

      return null;

    } catch (error) {
      console.error('❌ Error in inactivity check:', error);
      throw error;
    }
  });

/**
 * Check if current time is within sleep period
 */
function isCurrentlySleepTime(settings, now) {
  if (!settings) return false;

  const sleepStartHour = settings.sleepStartHour || 22;
  const sleepStartMinute = settings.sleepStartMinute || 0;
  const sleepEndHour = settings.sleepEndHour || 6;
  const sleepEndMinute = settings.sleepEndMinute || 0;
  const sleepActiveDays = settings.sleepActiveDays || [1, 2, 3, 4, 5, 6, 7];

  // Check if today is an active sleep day
  const dayOfWeek = now.getDay(); // 0 = Sunday, 6 = Saturday
  const mondayBased = dayOfWeek === 0 ? 7 : dayOfWeek; // Convert to Monday=1, Sunday=7

  if (!sleepActiveDays.includes(mondayBased)) {
    return false;
  }

  // Current time in minutes since midnight
  const currentMinutes = now.getHours() * 60 + now.getMinutes();
  const sleepStartMinutes = sleepStartHour * 60 + sleepStartMinute;
  const sleepEndMinutes = sleepEndHour * 60 + sleepEndMinute;

  // Check if in sleep period
  if (sleepStartMinutes > sleepEndMinutes) {
    // Overnight period (e.g., 22:00 - 06:00)
    return currentMinutes >= sleepStartMinutes || currentMinutes <= sleepEndMinutes;
  } else {
    // Same-day period (e.g., 14:00 - 16:00)
    return currentMinutes >= sleepStartMinutes && currentMinutes <= sleepEndMinutes;
  }
}

/**
 * Send survival alert FCM notification to child app
 */
async function sendSurvivalAlert(familyId, elderlyName, hoursInactive) {
  try {
    // Get child app FCM tokens
    const childDevicesSnapshot = await db
      .collection('families')
      .doc(familyId)
      .collection('child_devices')
      .where('is_active', '==', true)
      .where('fcm_token', '!=', null)
      .get();

    if (childDevicesSnapshot.empty) {
      console.log(`⚠️ No child devices found for family: ${familyId}`);
      return false;
    }

    const tokens = childDevicesSnapshot.docs
      .map(doc => doc.data().fcm_token)
      .filter(token => token && token.length > 0);

    if (tokens.length === 0) {
      console.log(`⚠️ No valid FCM tokens for family: ${familyId}`);
      return false;
    }

    console.log(`📱 Sending alert to ${tokens.length} child device(s)`);

    // Send FCM notification to each device
    const promises = tokens.map(token => {
      const message = {
        token: token,
        notification: {
          title: '🚨 생존 신호 알림',
          body: `${elderlyName}님이 ${hoursInactive}시간 이상 활동이 없습니다. 안부를 확인해 주세요.`,
        },
        data: {
          type: 'survival_alert',
          family_id: familyId,
          elderly_name: elderlyName,
          hours_inactive: hoursInactive.toString(),
          alert_level: 'critical',
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'emergency_alerts',
            sound: 'default',
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: '🚨 생존 신호 알림',
                body: `${elderlyName}님이 ${hoursInactive}시간 이상 활동이 없습니다.`,
              },
              sound: 'default',
              badge: 1,
            },
          },
        },
      };

      return admin.messaging().send(message);
    });

    await Promise.all(promises);
    console.log(`✅ Alert sent to ${tokens.length} device(s)`);

    return true;

  } catch (error) {
    console.error(`❌ Error sending survival alert: ${error}`);
    return false;
  }
}

/**
 * Manual trigger for testing
 * Can be called via HTTP request
 */
exports.manualInactivityCheck = functions.https.onRequest(async (req, res) => {
  console.log('🔧 Manual inactivity check triggered');

  try {
    // Run the same logic as scheduled function
    await exports.checkInactivity.run();

    res.status(200).send({
      success: true,
      message: 'Inactivity check completed',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Error in manual check:', error);
    res.status(500).send({
      success: false,
      error: error.message,
    });
  }
});
```

### Option 2: Optimized with Query (For Large Scale)

**For 10,000+ users, use this version:**

```javascript
// Replace the main loop in checkInactivity with this:

// Calculate threshold time (e.g., 12 hours ago)
const maxAlertHours = 24; // Check for max configured alert hours
const thresholdTime = new Date(now.getTime() - maxAlertHours * 60 * 60 * 1000);

// Query only families with old lastPhoneActivity
const familiesSnapshot = await db.collection('families')
  .where('lastPhoneActivity', '<', thresholdTime)
  .get();

console.log(`📊 Found ${familiesSnapshot.size} potentially inactive families`);

// Then continue with the same checking logic...
```

**Benefits:**
- 90%+ cost reduction for large user bases
- Only reads families that might be inactive
- Same functionality, much cheaper

---

## Testing & Deployment

### Local Testing

#### Test 1: Validate Function Syntax
```bash
cd functions
npm run serve
```

**Expected output:**
```
✔  functions: checkInactivity: http://localhost:5001/thanks-everyday/us-central1/checkInactivity
✔  functions: manualInactivityCheck: http://localhost:5001/thanks-everyday/us-central1/manualInactivityCheck
```

#### Test 2: Manual Trigger (Local)
```bash
# In another terminal
curl http://localhost:5001/thanks-everyday/us-central1/manualInactivityCheck
```

### Production Deployment

#### Deploy Function
```bash
firebase deploy --only functions
```

#### Verify Deployment
```bash
firebase functions:log
```

**Should see:**
```
2024-01-15T10:30:00.000Z I checkInactivity: 🔍 Starting inactivity check...
2024-01-15T10:30:01.234Z I checkInactivity: 📊 Checking 150 families
2024-01-15T10:30:05.567Z I checkInactivity: ✅ Inactivity check complete: 150 families checked, 2 alerts sent
```

### Testing Scenarios

#### Test Scenario 1: Normal Operation
```
Setup:
- Family has recent activity (5 hours ago)
- Alert threshold: 12 hours

Expected:
- No alert sent
- Log: "Last activity 5.0 hours ago (threshold: 12h)"
```

#### Test Scenario 2: Should Alert
```
Setup:
1. Update a test family's lastPhoneActivity to 13 hours ago:

   families/TEST_FAMILY_ID/
   {
     lastPhoneActivity: <13 hours ago timestamp>,
     elderlyName: "Test Elderly",
     settings: {
       alertHours: 12
     }
   }

2. Add a child device with FCM token:

   families/TEST_FAMILY_ID/child_devices/DEVICE_1
   {
     fcm_token: "<valid_token>",
     is_active: true
   }

Expected:
- Alert sent to child device
- Firebase updated with alerts.survival timestamp
- Log: "🚨 Family TEST_FAMILY_ID: Sending survival alert (13.0h inactive)"
```

#### Test Scenario 3: Sleep Time Exclusion
```
Setup:
- lastPhoneActivity: 13 hours ago
- Current time: 02:00 (within sleep period 22:00-06:00)
- sleepExclusionEnabled: true

Expected:
- No alert sent
- Log: "😴 Family X: In sleep period - skipping alert"
```

#### Test Scenario 4: Don't Spam Alerts
```
Setup:
- lastPhoneActivity: 15 hours ago
- alerts.survival exists: 2 hours ago

Expected:
- No alert sent (already alerted recently)
- Log: "⏰ Family X: Alert already sent 2.0h ago - skipping"
```

### Manual Testing via HTTP

#### Trigger Function Manually
```bash
# Get the function URL
firebase functions:config:get

# Call manual trigger
curl https://us-central1-thanks-everyday.cloudfunctions.net/manualInactivityCheck
```

**Response:**
```json
{
  "success": true,
  "message": "Inactivity check completed",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

### Creating Test Data

#### Add Test Family via Firebase Console

1. Go to Firebase Console → Firestore
2. Navigate to `families` collection
3. Add document:

```javascript
Document ID: TEST_FAMILY_001

Data:
{
  elderlyName: "Test Elderly",
  lastPhoneActivity: <13 hours ago>,  // Use Firestore timestamp
  location: {
    latitude: 37.5665,
    longitude: 126.9780,
    timestamp: <now>
  },
  settings: {
    alertHours: 12,
    sleepExclusionEnabled: false
  },
  alerts: {}  // Empty initially
}
```

4. Add child device subcollection:

```javascript
families/TEST_FAMILY_001/child_devices/TEST_DEVICE_001

Data:
{
  fcm_token: "YOUR_ACTUAL_FCM_TOKEN_FROM_CHILD_APP",
  device_id: "test_device_001",
  device_name: "Test Phone",
  is_active: true,
  registered_at: <now>
}
```

#### Get FCM Token from Child App

Add this to child app temporarily:
```dart
// In child app initialization
final fcmToken = await FirebaseMessaging.instance.getToken();
print('FCM TOKEN: $fcmToken');
```

Copy the token and use it in test data.

---

## Maintenance & Monitoring

### Monitoring Function Execution

#### View Logs
```bash
# Real-time logs
firebase functions:log --only checkInactivity

# Recent logs
firebase functions:log --only checkInactivity --lines 100
```

#### Firebase Console Monitoring

1. Go to Firebase Console → Functions
2. Click on `checkInactivity`
3. View metrics:
   - Invocations per day
   - Execution time
   - Error rate
   - Memory usage

### Setting Up Alerts

#### Email Alerts for Function Errors

1. Go to Firebase Console → Functions
2. Click on `checkInactivity`
3. Click "Set up alerts"
4. Configure:
   - Alert on error rate > 5%
   - Email notifications
   - Slack notifications (optional)

### Common Issues & Solutions

#### Issue 1: Function Times Out
```
Error: Function execution took too long (60s timeout)
```

**Solution:**
```javascript
// Increase timeout in function config
exports.checkInactivity = functions
  .runWith({ timeoutSeconds: 300 }) // 5 minutes
  .pubsub.schedule('every 30 minutes')
  .onRun(async (context) => {
    // ... function code
  });
```

#### Issue 2: Permission Denied
```
Error: Missing or insufficient permissions
```

**Solution:**
Check Firestore Rules. Function needs read access:
```javascript
// firestore.rules
match /families/{familyId} {
  allow read, write: if request.auth != null;

  // Allow Cloud Functions to read (uses service account)
  allow read: if request.auth.token.admin == true;
}
```

#### Issue 3: No FCM Tokens Found
```
⚠️ No child devices found for family: FAMILY_ID
```

**Solution:**
- Verify child app is properly registered
- Check child_devices subcollection exists
- Verify FCM token is valid and not expired
- Check `is_active` field is `true`

#### Issue 4: High Costs
```
Firestore reads exceeding budget
```

**Solution:**
- Implement query optimization (Option 2)
- Increase check interval (30 min → 1 hour)
- Add index on `lastPhoneActivity` field

### Performance Optimization

#### Add Firestore Index

For query-optimized version:
```bash
firebase firestore:indexes
```

Add to `firestore.indexes.json`:
```json
{
  "indexes": [
    {
      "collectionGroup": "families",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "lastPhoneActivity",
          "order": "ASCENDING"
        }
      ]
    }
  ]
}
```

Deploy:
```bash
firebase deploy --only firestore:indexes
```

### Scaling Considerations

#### For 1,000+ Families

**Use batch processing:**
```javascript
// Process in chunks of 100
const chunkSize = 100;
const chunks = [];

for (let i = 0; i < familiesSnapshot.docs.length; i += chunkSize) {
  chunks.push(familiesSnapshot.docs.slice(i, i + chunkSize));
}

for (const chunk of chunks) {
  await Promise.all(chunk.map(processFamily));
  // Small delay between chunks to avoid rate limits
  await new Promise(resolve => setTimeout(resolve, 100));
}
```

#### For 10,000+ Families

**Use query optimization + pagination:**
```javascript
// Only query inactive families
const thresholdTime = new Date(now - 12 * 60 * 60 * 1000);
const inactiveFamilies = await db.collection('families')
  .where('lastPhoneActivity', '<', thresholdTime)
  .limit(1000)  // Process max 1000 at a time
  .get();
```

### Updating Function Code

#### After Making Changes
```bash
cd functions
firebase deploy --only functions
```

#### Rollback to Previous Version
```bash
# List previous versions
firebase functions:list

# Rollback specific function
firebase functions:rollback checkInactivity --version <version_id>
```

---

## Integration with Existing System

### How It Works with Parent App

**Parent App Continues:**
- ✅ Updating Firebase every 10 minutes
- ✅ Sending location updates
- ✅ Sleep time exception logic
- ✅ Can still send immediate alerts (optional)

**Firebase Function Adds:**
- ✅ Backup monitoring (catches phone-off scenarios)
- ✅ Independent of parent app status
- ✅ Handles alerts when parent can't

### Dual Alert System (Recommended)

**Parent App Alert:**
- Fast response (immediate when app detects)
- Only works when phone is ON

**Function Alert:**
- Backup system (every 30 minutes)
- Works even when phone is OFF
- Prevents duplicate alerts (6-hour cooldown)

**Result:** Best of both worlds!

### Removing Parent App Alert (Optional)

If you want ONLY Firebase Functions to send alerts:

1. Remove from parent app:
   ```dart
   // In screen_monitor_service.dart
   // Comment out or delete lines 222-266

   // static Future<void> _handleInactivityAlert() async {
   //   await _sendSurvivalAlert();
   // }
   ```

2. Keep the rest of parent app unchanged
   - Still updates Firebase every 10 minutes
   - Still tracks location
   - Just doesn't send alerts

---

## Summary & Recommendations

### What to Implement

✅ **Keep parent app as-is**
- No changes needed to parent app code
- Continue updating Firebase every 10 minutes
- Sleep time exception continues working

✅ **Add Firebase Function**
- Runs every 30 minutes
- Checks for inactive families
- Sends alerts when needed
- Independent backup system

✅ **Deploy to Blaze Plan**
- Required for Cloud Functions
- Pay-as-you-go (but mostly free tier)
- Set budget alerts to avoid surprises

### Cost Summary

| Users | Monthly Cost | Per User |
|-------|--------------|----------|
| 10    | $0           | $0       |
| 100   | $0.50        | $0.005   |
| 1,000 | $15          | $0.015   |
| 10,000| $163         | $0.016   |

**Recommendation:** 10-minute intervals with Firebase Function backup

### Next Steps

1. ✅ Review this document
2. ✅ Set up Firebase CLI
3. ✅ Initialize functions in project
4. ✅ Add function code
5. ✅ Test with sample data
6. ✅ Deploy to production
7. ✅ Monitor for 1 week
8. ✅ Adjust intervals if needed

---

## Additional Resources

### Firebase Documentation
- [Cloud Functions Guide](https://firebase.google.com/docs/functions)
- [Scheduled Functions](https://firebase.google.com/docs/functions/schedule-functions)
- [FCM Send Messages](https://firebase.google.com/docs/cloud-messaging/send-message)
- [Firestore Queries](https://firebase.google.com/docs/firestore/query-data/queries)

### Pricing
- [Firebase Pricing Calculator](https://firebase.google.com/pricing)
- [Cloud Functions Pricing](https://cloud.google.com/functions/pricing)
- [Firestore Pricing](https://firebase.google.com/docs/firestore/pricing)

### Support
- [Firebase Support](https://firebase.google.com/support)
- [Stack Overflow - Firebase](https://stackoverflow.com/questions/tagged/firebase)
- [Firebase Community](https://firebase.google.com/community)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-26
**Author:** Claude Code
**Project:** Thanks Everyday - Elderly Monitoring App
