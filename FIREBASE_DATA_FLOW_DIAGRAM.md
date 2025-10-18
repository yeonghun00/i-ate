# Firebase Data Flow Diagrams

## 1. Setup Complete Flow ("설정 완료" Button)

```
User presses "설정 완료"
    ↓
InitialSetupScreen._setupFamily()
    ↓
FirebaseService.setupFamilyCode("김할머니")
    ├─→ Generate unique connection code (e.g., "A2K4")
    │   └─→ READ: connection_codes/{A2K4}.get() [verify uniqueness]
    │
    ├─→ Generate unique family ID (e.g., "f_abc123")
    │   └─→ READ QUERY: connection_codes where familyId == "f_abc123"
    │
    └─→ Create both documents
        ├─→ CREATE: connection_codes/{A2K4}
        │   Data: { familyId, elderlyName, createdAt }
        │
        └─→ CREATE: families/{f_abc123}
            Data: { familyId, connectionCode, elderlyName, settings, alerts, location, lastMeal, lastPhoneActivity }
                 └─→ settings.survivalSignalEnabled = false (default)
                 └─→ approved = null (waiting for child app)
    ↓
InitialSetupScreen._startListeningForApproval()
    ↓
FamilyDataManager.listenForApproval(connectionCode)
    └─→ LISTEN: families/{f_abc123}.snapshots()
        └─→ Watch field: "approved"
            ├─→ null (waiting) → Keep listening
            ├─→ true (approved) → Navigate to GuideScreen
            └─→ false (rejected) → Show error
    ↓
TIMEOUT after 2 minutes
    ├─→ If not approved:
    │   ├─→ FirebaseService.deleteFamilyCode(connectionCode)
    │   │   └─→ DELETE: families/{f_abc123}
    │   └─→ Show: "연결 시간이 초과되었습니다"
    │
    └─→ If approved:
        └─→ Navigate to GuideScreen
```

---

## 2. Meal Recording Flow (User Records Meal)

```
User clicks "식사했어요" (Meal Button)
    ↓
HomePage._recordMeal()
    ├─→ Check if canRecordMeal (max 3 meals/day)
    ├─→ Set isSaving = true (disable button)
    │
    ├─→ Step 1: UPDATE Activity BEFORE meal recording
    │   └─→ FirebaseService.updatePhoneActivity(forceImmediate: true)
    │       └─→ ActivityBatcher.shouldBatchUpdate(forceImmediate: true)
    │           └─→ Return false (send immediately, not batch)
    │       └─→ UPDATE: families/{familyId}
    │           Data: { lastPhoneActivity: Timestamp, lastActivityType, updateTimestamp }
    │
    ├─→ Step 2: Record meal locally & in Firebase
    │   ├─→ FoodTrackingService.recordFoodIntake() [Local SQLite]
    │   │
    │   └─→ FirebaseService.saveMealRecord()
    │       ├─→ CREATE/UPDATE: families/{familyId}/meals/{2025-10-18}
    │       │   Data: { meals: [...], date, elderlyName }
    │       │   (arrayUnion to add new meal to array)
    │       │
    │       ├─→ READ: families/{familyId}/meals/{2025-10-18}.get()
    │       │   Purpose: Get current meal count (1, 2, or 3)
    │       │
    │       ├─→ UPDATE: families/{familyId}
    │       │   Data: { lastMeal: { timestamp, count, number } }
    │       │
    │       └─→ Send FCM Notification
    │           └─→ FCMv1Service.sendMealNotification(familyId, elderlyName, mealNumber)
    │               └─→ Firebase Cloud Messaging → Child App
    │
    ├─→ Step 3: Force GPS location update AFTER meal
    │   └─→ HomePage._forceLocationUpdateAfterMeal()
    │       ├─→ LocationService.getCurrentLocation()
    │       │   └─→ Get fresh GPS coordinates
    │       │
    │       └─→ FirebaseService.forceLocationUpdate(latitude, longitude)
    │           └─→ LocationThrottler.shouldThrottleUpdate(lat, lon)
    │               └─→ If significant change: UPDATE; else: Skip
    │           └─→ UPDATE: families/{familyId}
    │               Data: { location: { latitude, longitude, timestamp, address } }
    │
    ├─→ Step 4: Reload meal data
    │   └─→ FirebaseService.getTodayMealCount()
    │       └─→ READ: families/{familyId}/meals/{today}.get()
    │           └─→ Get meals array length
    │
    └─→ Set isSaving = false (re-enable button)
        └─→ Show success message with count (1/3, 2/3, or 🎉 3/3)
```

---

## 3. GPS Location Update Flow (Native Service)

```
Native Android LocationManager (Background Service)
    ├─→ Detects location change
    │
    ├─→ Send to Flutter via MethodChannel
    │   └─→ _channel.invokeMethod('onLocationUpdate', { latitude, longitude, timestamp, accuracy })
    │
    └─→ LocationService._handleLocationUpdate(args)
        ├─→ Extract: latitude, longitude, timestamp, accuracy
        │
        ├─→ LocationThrottler.shouldThrottleUpdate(lat, lon)
        │   └─→ Calculate distance from lastKnownLocation
        │   ├─→ If distance < threshold → Return true (THROTTLE)
        │   └─→ If distance >= threshold → Return false (SEND)
        │
        ├─→ If NOT throttled:
        │   ├─→ Store as _lastKnownPosition
        │   │
        │   └─→ FirebaseService.forceLocationUpdate(latitude, longitude, address)
        │       └─→ UPDATE: families/{familyId}
        │           Data: { location: { latitude, longitude, timestamp, address } }
        │
        └─→ Record throttle update for next check
```

---

## 4. Survival Signal / Activity Monitoring Flow

```
Phone Activity Detection (Various triggers):
├─→ App Startup
│   └─→ HomePage._initializePage()
│       └─→ HomePage._updateActivityInFirebase()
│
├─→ Meal Recording
│   └─→ firebase_service.dart line 230
│       └─→ updatePhoneActivity(forceImmediate: true)
│
├─→ Periodic Activity (user interaction)
│   └─→ Screen interactions, button clicks, etc.
│       └─→ Some trigger calls updatePhoneActivity()
│
└─→ Force Update
    └─→ User/system triggers forceActivityUpdate()

    ↓
    
FirebaseService.updatePhoneActivity(forceImmediate)
    ├─→ Check ActivityBatcher.shouldBatchUpdate(forceImmediate)
    │   ├─→ If forceImmediate=true → return false (DON'T batch, send now)
    │   ├─→ If _lastBatch=null → return false (first activity, send now)
    │   ├─→ If 8+ hours since last batch → return false (breaking inactivity, send now)
    │   ├─→ If 2+ hours since last batch → return false (batch interval exceeded, send now)
    │   └─→ Otherwise → return true (batch this update, don't send)
    │
    ├─→ If should send (not batching):
    │   ├─→ UPDATE: families/{familyId}
    │   │   Data: {
    │   │     lastPhoneActivity: Timestamp(server),
    │   │     lastActivityType: "first_activity" | "batched_activity",
    │   │     updateTimestamp: Timestamp(server)
    │   │   }
    │   │
    │   └─→ ActivityBatcher.recordBatch()
    │       └─→ _lastBatch = now
    │
    └─→ If batching (don't send):
        └─→ Just store in memory, no Firebase update

    ↓
    
Child App Monitors Survival Status (Real-time):
    └─→ Child app reads: families/{familyId}/lastPhoneActivity
        └─→ Calculate hoursSinceLastActivity
            ├─→ If hours < alertHours → NORMAL (green indicator)
            ├─→ If hours >= alertHours → WARNING/ALERT (yellow/red indicator)
            └─→ Send notification if alert threshold reached
```

---

## 5. Child App Joins Flow (Using Connection Code)

```
Child App User enters Connection Code: "A2K4"
    ↓
ChildAppService.getFamilyInfo("A2K4")
    ├─→ READ: connection_codes/{A2K4}.get()
    │   └─→ Returns: { familyId: "f_abc123", elderlyName: "김할머니", createdAt }
    │
    └─→ READ: families/{f_abc123}.get()
        └─→ Returns: All family data including settings, location, lastMeal, alerts
    ↓
Show elderly person info: "김할머니"
    └─→ Display: Photo, meals today, survival signal status, location
    ↓
Child App User clicks "연결 승인" (Approve Connection)
    ↓
ChildAppService.approveFamilyCode("A2K4", approved: true)
    └─→ UPDATE: families/{f_abc123}
        Data: {
          approved: true,
          approvedAt: Timestamp(server),
          memberIds: arrayUnion([childUserId])
        }
    ↓
Parent App's Real-time Listener Detects Change
    └─→ FamilyDataManager.listenForApproval(connectionCode)
        └─→ LISTEN: families/{f_abc123}.snapshots()
            └─→ Receives update: approved = true
                └─→ Yield true to parent app
                    └─→ InitialSetupScreen detects approval
                        └─→ Cancel all timers
                        └─→ Navigate to GuideScreen
                        └─→ Show: "자녀가 승인했습니다! 앱을 시작합니다."
```

---

## 6. Timeout Flow (No Approval After 2 Minutes)

```
User clicks "설정 완료"
    └─→ Start 2-minute countdown timer
    └─→ Start listening for approval
    ↓
2 minutes pass WITHOUT approval
    ↓
InitialSetupScreen._startTimeoutTimer() triggers
    └─→ Check if _isWaitingForApproval && _generatedCode != null
        ├─→ Cancel approval subscription
        ├─→ Cancel polling timer
        ├─→ Cancel countdown timer
        │
        ├─→ FirebaseService.deleteFamilyCode(connectionCode)
        │   ├─→ Query: families where connectionCode == code
        │   └─→ DELETE: families/{familyId}
        │
        ├─→ Clear local data:
        │   ├─→ _generatedCode = null
        │   ├─→ Clear all input fields
        │   └─→ Reset settings
        │
        └─→ Show message: "연결 시간이 초과되었습니다. 다시 설정해주세요."
            └─→ Return to setup form
```

---

## 7. Data Dependencies Tree

```
families/{familyId}/
├─── Settings (set by parent app during setup)
│    ├─ survivalSignalEnabled
│    ├─ alertHours
│    └─ sleepTimeSettings
│
├─── Activity Data (updated continuously)
│    ├─ lastPhoneActivity (used by child app for survival signal)
│    ├─ lastActivityType
│    └─ updateTimestamp
│
├─── Meal Data (updated when user records meal)
│    ├─ lastMeal.timestamp
│    ├─ lastMeal.count (aggregate of meals subcollection)
│    └─ lastMeal.number
│
├─── Location Data (updated by native service)
│    ├─ location.latitude
│    ├─ location.longitude
│    ├─ location.timestamp
│    └─ location.address
│
├─── Approval Status (set by child app)
│    ├─ approved (null/true/false)
│    ├─ approvedAt
│    └─ memberIds
│
├─── Alerts
│    ├─ alerts.survival (timestamp or null)
│    └─ alerts.food (timestamp or null)
│
└─── meals/{YYYY-MM-DD}/ (subcollection)
     └─ meals array (individual meal records)

connection_codes/{connectionCode}/
├─ familyId (foreign key to families)
├─ elderlyName
└─ createdAt
```

---

## 8. Firestore Query & Operation Summary

### All .set() Operations (CREATE)

```
1. connection_codes/{code}.set()
   Location: firebase_service.dart:140
   Trigger: setupFamilyCode()

2. families/{id}.set()
   Location: firebase_service.dart:147
   Trigger: setupFamilyCode()

3. families/{id}/meals/{date}.set(merge: true)
   Location: firebase_service.dart:249-258
   Trigger: saveMealRecord()
```

### All .update() Operations

```
1. families/{id}.update({settings.*})
   Location: family_data_manager.dart:102
   Trigger: updateFamilySettings()

2. families/{id}.update({lastMeal})
   Location: firebase_service.dart:273-279
   Trigger: saveMealRecord()

3. families/{id}.update({lastPhoneActivity, lastActivityType, updateTimestamp})
   Location: firebase_service.dart:623-627 (main activity)
   Location: firebase_service.dart:452-456 (force activity)
   Trigger: updatePhoneActivity() / forceActivityUpdate()

4. families/{id}.update({location})
   Location: firebase_service.dart:656-663
   Trigger: updateLocation() / forceLocationUpdate()

5. families/{id}.update({alerts.survival})
   Location: firebase_service.dart:477
   Trigger: sendSurvivalAlert()

6. families/{id}.update({alerts.food})
   Location: firebase_service.dart:537-539
   Trigger: sendFoodAlert()

7. families/{id}.update({approved, approvedAt, memberIds})
   Location: family_data_manager.dart:120-124
   Trigger: Child app approval
```

### All .get() Operations (READ single document)

```
1. connection_codes/{code}.get()
   Location: firebase_service.dart:57-58
   Purpose: Verify unique code

2. connection_codes (query).get()
   Location: firebase_service.dart:105-109
   Purpose: Verify unique family ID

3. families/{id}/meals/{date}.get()
   Location: firebase_service.dart:261-266
   Purpose: Get current meal count

4. families/{id}/meals/{date}.get()
   Location: home_page.dart:72
   Purpose: Load today's meal data

5. connection_codes/{code}.get()
   Location: family_data_manager.dart:14-17
   Purpose: Get family info for child app

6. families/{id}.get()
   Location: family_data_manager.dart:27
   Purpose: Get full family data
```

### All .snapshots() Operations (LISTEN real-time)

```
1. families/{id}.snapshots()
   Location: family_data_manager.dart:151
   Purpose: Listen for approval changes
   Watches: approved field

2. families/{id}/recordings.snapshots()
   Location: child_app_service.dart:112-117
   Purpose: Listen for new recordings
   Watches: Entire subcollection
```

### All .delete() Operations

```
1. families/{id}.delete()
   Location: firebase_service.dart:406
   Trigger: deleteFamilyCode() [called on timeout or user reset]
```

---

## 9. Real-time Sync Points

```
Parent App Updates Firebase
    ↓
Cloud Firestore
    ↓
Child App Listens to Firestore
    ├─ families/{id}/lastPhoneActivity → Survival Signal Calculation
    ├─ families/{id}/lastMeal → Meal Count Display
    ├─ families/{id}/location → Map Display
    ├─ families/{id}/alerts.* → Alert Notifications
    └─ families/{id}/settings → Load Elderly's Settings

Parent App Listens to Firestore
    ├─ families/{id}/approved → Setup completion
    └─ families/{id} (any changes) → Reflection of approval
```

---

## 10. FCM Notification Flow

```
User records meal
    └─→ FirebaseService.saveMealRecord()
        └─→ FCMv1Service.sendMealNotification(
              familyId: f_abc123,
              elderlyName: "김할머니",
              timestamp: now,
              mealNumber: 1
            )
            └─→ Firebase Cloud Messaging API (v1)
                ├─→ Build message payload
                └─→ Send to child app's FCM token for familyId
                    └─→ Child App receives notification
                        ├─ Title: "식사했어요!"
                        ├─ Body: "김할머니 - 아침 (1/3)"
                        └─ Data: { familyId, mealNumber, timestamp }
```

