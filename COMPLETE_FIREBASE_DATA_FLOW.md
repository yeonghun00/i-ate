# Complete Firebase Firestore Data Flow Analysis

**App Name:** Thanks Everyday (식사하셨어요? / 고마워요)  
**Analysis Date:** 2025-10-18  
**Purpose:** Parent app for tracking elderly health status through meal recording and survival signal monitoring

---

## Firestore Collections Overview

```
families/
├── {familyId}/
│   ├── meals/
│   │   └── {YYYY-MM-DD}/
│   └── recordings/
│       └── {YYYY-MM-DD}/
└── (root document fields)

connection_codes/
└── {connectionCode}/
```

---

## COMPLETE DATA FLOW BY USER ACTION

### 1. USER CLICKS "설정 완료" (Setup Complete)

**Flow Location:** `lib/screens/initial_setup_screen.dart` → `_setupFamily()` method

#### Step 1: Generate Connection Code
```dart
// Line 58: Call setupFamilyCode()
final generatedCode = await _firebaseService.setupFamilyCode(
  _nameController.text.trim(), // Example: "김할머니"
);
```

**Firebase Operations:**
- **CREATE** (READ first): Check `connection_codes` collection for uniqueness
  - File: `firebase_service.dart`, Line 57-58
  - Operation: `_firestore.collection('connection_codes').doc(code).get()`
  - Purpose: Verify connection code is unique

#### Step 2: Generate Unique Family ID
```dart
// firebase_service.dart, Line 77
final familyId = await _generateUniqueFamilyId();
```

**Firebase Operations:**
- **READ** Query to check uniqueness
  - File: `firebase_service.dart`, Lines 105-109
  - Query: `.collection('connection_codes').where('familyId', isEqualTo: familyId)`
  - Purpose: Ensure family ID is unique

#### Step 3: Create Two Documents in Firebase

**Operation A - Create Connection Code Lookup Document:**
```dart
// firebase_service.dart, Line 140
await _firestore.collection('connection_codes').doc(connectionCode).set({
  'familyId': familyId,
  'elderlyName': elderlyName,
  'createdAt': FieldValue.serverTimestamp(),
});
```

**Firestore Path:** `connection_codes/{connectionCode}`
**Operation Type:** CREATE (`.set()`)
**Data Written:**
```json
{
  "familyId": "f_1234567890abc",
  "elderlyName": "김할머니",
  "createdAt": Timestamp(server)
}
```

**Operation B - Create Main Family Document:**
```dart
// firebase_service.dart, Line 147
await _firestore.collection('families').doc(familyId).set({
  'familyId': familyId,
  'connectionCode': connectionCode,
  'elderlyName': elderlyName,
  'createdAt': FieldValue.serverTimestamp(),
  'deviceInfo': 'Android Device',
  'isActive': true,
  'approved': null,
  'createdBy': currentUserId,
  'memberIds': [currentUserId],
  'settings': {
    'survivalSignalEnabled': false,
    'familyContact': '',
    'alertHours': 12,
  },
  'alerts': {
    'survival': null,
    'food': null
  },
  'lastMeal': {
    'timestamp': null,
    'count': 0,
    'number': null
  },
  'location': {
    'latitude': null,
    'longitude': null,
    'timestamp': null,
    'address': '',
  },
  'lastPhoneActivity': null,
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** CREATE (`.set()`)
**Key Fields:**
- `connectionCode`: Connection code for child app
- `elderlyName`: Elderly person's name
- `settings`: Default settings (survival signal OFF)
- `alerts`: Survival and food alert tracking
- `lastMeal`: Most recent meal record info
- `location`: GPS location tracking
- `lastPhoneActivity`: Activity timestamp for survival signal

#### Step 4: Save Settings to Firebase

**Operation C - Update Family Settings:**
```dart
// initial_setup_screen.dart, Line 66
final settingsUpdated = await _firebaseService.updateFamilySettings(
  survivalSignalEnabled: _survivalSignalEnabled,
  familyContact: '',
  alertHours: _alertHours,
  sleepTimeSettings: sleepSettings,
);
```

**Firestore Operation:**
```dart
// family_data_manager.dart, Line 102
await _firestore.collection('families').doc(familyId).update({
  'settings.survivalSignalEnabled': survivalSignalEnabled,
  'settings.familyContact': familyContact,
  'settings.alertHours': alertHours ?? 12,
  'settings.sleepTimeSettings': sleepTimeSettings,
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)
**Data Updated:**
```json
{
  "settings.survivalSignalEnabled": true/false,
  "settings.familyContact": "",
  "settings.alertHours": 12,
  "settings.sleepTimeSettings": {
    "enabled": true,
    "sleepStartHour": 22,
    "sleepStartMinute": 30,
    "sleepEndHour": 6,
    "sleepEndMinute": 0,
    "activeDays": [1, 2, 3, 4, 5, 6, 7]
  }
}
```

#### Step 5: Wait for Child App Approval

**Operation D - Listen for Approval Updates:**
```dart
// initial_setup_screen.dart, Line 137-138
_approvalSubscription = _firebaseService
    .listenForApproval(_generatedCode!)
    .listen((approved) { ... });
```

**Firestore Operation:**
```dart
// family_data_manager.dart, Line 151
await for (final snapshot in _firestore.collection('families').doc(familyId).snapshots()) {
  final approved = data?['approved'] as bool?;
  yield approved;
}
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** READ (`.snapshots()` - real-time listener)
**Reading Field:** `approved` (null → true → proceed, null → false → rejected)

#### Step 6: Timeout After 2 Minutes (If No Approval)

**Operation E - Delete Family Code on Timeout:**
```dart
// initial_setup_screen.dart, Line 309
await _firebaseService.deleteFamilyCode(_generatedCode!);
```

**Firestore Operation:**
```dart
// firebase_service.dart, Line 406
await doc.reference.delete();
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** DELETE (`.delete()`)

---

### 2. USER RECORDS A MEAL (User Clicks Meal Record Button)

**Flow Location:** `lib/screens/home_page.dart` → `_recordMeal()` method

#### Step 1: Immediate Activity Update

**Operation A - Force Immediate Activity Update (Before Meal):**
```dart
// firebase_service.dart, Line 230
await updatePhoneActivity(forceImmediate: true);
```

**Firestore Operation:**
```dart
// firebase_service.dart, Line 623-627
await _firestore.collection('families').doc(_familyId).update({
  'lastPhoneActivity': FieldValue.serverTimestamp(),
  'lastActivityType': _activityBatcher.isFirstActivity ? 'first_activity' : 'batched_activity',
  'updateTimestamp': FieldValue.serverTimestamp(),
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)

#### Step 2: Save Meal Record to Meals Subcollection

**Operation B - Save Meal Record:**
```dart
// firebase_service.dart, Line 249-258
await _firestore
    .collection('families')
    .doc(_familyId)
    .collection('meals')
    .doc(dateString)  // "2025-10-18"
    .set({
      'meals': FieldValue.arrayUnion([mealData]),
      'date': dateString,
      'elderlyName': _elderlyName,
    }, SetOptions(merge: true));
```

**Firestore Path:** `families/{familyId}/meals/{YYYY-MM-DD}`
**Operation Type:** CREATE/UPDATE (`.set()` with `merge: true`)
**Data Written:**
```json
{
  "meals": [
    {
      "mealId": "1697596800000_1",
      "timestamp": "2025-10-18T12:30:00.000Z",
      "mealNumber": 1,
      "elderlyName": "김할머니",
      "createdAt": "2025-10-18T12:30:00.000Z"
    }
  ],
  "date": "2025-10-18",
  "elderlyName": "김할머니"
}
```

#### Step 3: Get Current Meal Count

**Operation C - Read Updated Meal Count:**
```dart
// firebase_service.dart, Line 261-266
final updatedDoc = await _firestore
    .collection('families')
    .doc(_familyId)
    .collection('meals')
    .doc(dateString)
    .get();

final currentMealCount = updatedDoc.exists
    ? (updatedDoc.data()?['meals'] as List<dynamic>?)?.length ?? 0
    : 0;
```

**Firestore Path:** `families/{familyId}/meals/{YYYY-MM-DD}`
**Operation Type:** READ (`.get()`)

#### Step 4: Update Family Document with Meal Info

**Operation D - Update Family Meal Metadata:**
```dart
// firebase_service.dart, Line 273-279
await _firestore.collection('families').doc(_familyId).update({
  'lastMeal': {
    'timestamp': FieldValue.serverTimestamp(),
    'count': currentMealCount,
    'number': mealNumber,
  },
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)
**Data Updated:**
```json
{
  "lastMeal": {
    "timestamp": Timestamp(server),
    "count": 1,
    "number": 1
  }
}
```

#### Step 5: Send FCM Notification

**Operation E - Send Meal Notification (via FCM v1 API):**
```dart
// firebase_service.dart, Line 283-288
await FCMv1Service.sendMealNotification(
  familyId: _familyId!,
  elderlyName: _elderlyName ?? '부모님',
  timestamp: timestamp,
  mealNumber: mealNumber,
);
```

**External System:** Firebase Cloud Messaging (FCM)
**Notification Sent To:** Child app subscribers

#### Step 6: Force Location Update After Meal

**Operation F - Force Immediate GPS Update:**
```dart
// home_page.dart, Line 234
await _forceLocationUpdateAfterMeal();
```

**Firestore Operation:**
```dart
// home_page.dart, Line 270
final success = await _firebaseService.forceLocationUpdate(
  latitude: position.latitude,
  longitude: position.longitude,
);
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)
**Data Updated:** (See GPS Location Update section below)

---

### 3. GPS LOCATION UPDATES

**Flow Location:** `lib/services/location_service.dart` → Background native service

#### When Triggered:
- User enables location tracking in setup
- Native Android service detects location change
- Called after app startup and after meal recording

#### Step 1: Native Location Detection

**Source:** Native Android LocationManager → Method Channel

#### Step 2: Handle Location Update

**Operation A - Process Location Update:**
```dart
// location_service.dart, Line 193-229
static Future<void> _handleLocationUpdate(dynamic args) async {
  final latitude = args['latitude'] as double;
  final longitude = args['longitude'] as double;
  
  // Check throttling
  if (_locationThrottler.shouldThrottleUpdate(latitude, longitude)) {
    return; // Skip update if not significant change
  }
  
  // Update Firebase
  await _firebaseService.forceLocationUpdate(
    latitude: latitude,
    longitude: longitude,
    address: '',
  );
}
```

**Firestore Operation:**
```dart
// firebase_service.dart, Line 656-663
await _firestore.collection('families').doc(_familyId).update({
  'location': {
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': FieldValue.serverTimestamp(),
    'address': address ?? '',
  },
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)
**Data Updated:**
```json
{
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "timestamp": Timestamp(server),
    "address": ""
  }
}
```

**Throttling:** Location updates checked via `LocationThrottler` (in `lib/services/location/location_throttler.dart`) - prevents spam updates

---

### 4. SURVIVAL SIGNAL UPDATES (Activity Monitoring)

**Flow Location:** `lib/services/firebase_service.dart` → `updatePhoneActivity()`

#### When Triggered:
1. **App Startup:** `home_page.dart` line 101 - `_updateActivityInFirebase()`
2. **Meal Recording:** Before saving meal - `firebase_service.dart` line 230
3. **Periodic Updates:** Via `ActivityBatcher` with 2-hour interval (after meal/startup)
4. **Force Updates:** `forceActivityUpdate()` method

#### Step 1: Check Activity Batching Logic

**Source:** `lib/services/activity/activity_batcher.dart`

```dart
bool shouldBatchUpdate({bool forceImmediate = false}) {
  final now = DateTime.now();
  
  // Immediate if forced or first activity
  if (forceImmediate || _lastBatch == null) {
    return false; // Don't batch - send immediately
  }
  
  // Immediate if breaking long inactivity (8 hours)
  final timeSinceLastBatch = now.difference(_lastBatch!);
  if (timeSinceLastBatch >= Duration(hours: 8)) {
    return false; // Send immediately
  }
  
  // Batch if within 2-hour interval
  if (timeSinceLastBatch >= Duration(hours: 2)) {
    return false; // Send immediately
  }
  
  return true; // Otherwise, batch
}
```

#### Step 2: Update Activity in Firebase

**Operation A - Send Activity Timestamp:**
```dart
// firebase_service.dart, Line 623-627
await _firestore.collection('families').doc(_familyId).update({
  'lastPhoneActivity': FieldValue.serverTimestamp(),
  'lastActivityType': _activityBatcher.isFirstActivity ? 'first_activity' : 'batched_activity',
  'updateTimestamp': FieldValue.serverTimestamp(),
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)
**Data Updated:**
```json
{
  "lastPhoneActivity": Timestamp(server),
  "lastActivityType": "batched_activity",
  "updateTimestamp": Timestamp(server)
}
```

#### How Child App Detects Survival Signal:

**Operation B - Child App Reads Activity Data (Real-time):**
```dart
// Child app monitors: families/{familyId}/lastPhoneActivity
// If Timestamp older than alertHours (default 12 hours) → Alert triggered
```

---

### 5. PARENT APP RECOVERY (After Reinstallation)

**Flow Location:** `lib/screens/account_recovery_screen.dart` → `lib/services/firebase_service.dart`

#### When Triggered:
- User reinstalls app (all local data lost)
- User clicks "이미 계정이 있어요" button on initial setup
- User enters name + connection code to recover account

#### Step 1: User Enters Recovery Info

**Operation A - Search for Family by Connection Code:**
```dart
// firebase_service.dart, Line 783-786
final query = await _firestore
    .collection('families')
    .where('connectionCode', isEqualTo: connectionCode)
    .get();
```

**Firestore Path:** `families/` (query)
**Operation Type:** READ (`.where().get()`)

#### Step 2: Fuzzy Name Matching

**Operation B - Verify Name Match:**
```dart
// firebase_service.dart, Line 805
final matchScore = _calculateNameMatchScore(name, elderlyName);

if (matchScore >= 0.7) { // 70% similarity threshold
  // Accept as match
}
```

**Matching Features:**
- Removes spaces: "이 영훈" → "이영훈"
- Handles honorifics: "김할머니" vs "김○○할머니"
- Levenshtein distance calculation
- 70% minimum similarity required

#### Step 3: Restore Account with New User ID

**Operation C - Add New User to Family (CRITICAL FIX):**
```dart
// firebase_service.dart, Line 1166-1170
await _firestore.collection('families').doc(familyId).update({
  'memberIds': FieldValue.arrayUnion([currentUserId]),
  'recoveredAt': FieldValue.serverTimestamp(),
  'recoveredBy': currentUserId,
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)
**Data Updated:**
```json
{
  "memberIds": ["old_user_id", "new_user_id"],  // Both devices can access now
  "recoveredAt": Timestamp(server),
  "recoveredBy": "new_user_id"
}
```

**Why This is Critical:**
- Old device: `createdBy: "user_abc123"`, `memberIds: ["user_abc123"]`
- New device: Firebase Auth creates NEW user ID: `"user_xyz789"`
- Without this update: New user not in `memberIds` → Permission denied ❌
- With this update: New user added to `memberIds` → Access granted ✅

#### Step 4: Restore Local Storage

**Operation D - Save Data Locally:**
```dart
// firebase_service.dart, Line 1175-1178
await _storage.setString('family_id', familyId);
await _storage.setString('family_code', connectionCode);
await _storage.setString('elderly_name', elderlyName);
await _storage.setBool('setup_complete', true);
```

**Storage Type:** SharedPreferences (local device)
**Data Restored:**
- `family_id`: Family document ID
- `family_code`: 4-digit connection code
- `elderly_name`: User's registered name
- `setup_complete`: Setup completion flag

#### Step 5: Navigate to Permission Setup

**Operation E - Re-request Permissions:**
```dart
// account_recovery_screen.dart, Line 67-76
Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (context) => SpecialPermissionGuideScreen(
      onPermissionsComplete: () {
        widget.onRecoveryComplete();
      },
    ),
  ),
);
```

**Why Needed:**
- New device needs fresh permission grants
- Location, battery optimization, usage stats, etc.
- Android permissions don't transfer between installations

#### Recovery Flow Summary

```
1. User clicks "이미 계정이 있어요"
   ↓
2. Enter name: "이영훈" + code: "1234"
   ↓
3. Query Firebase: families.where('connectionCode', '==', '1234')
   ↓
4. Fuzzy match name (≥70% similarity)
   ↓
5. CRITICAL: Add new user ID to memberIds
   ├─> Old: memberIds: ["user_abc123"]
   └─> New: memberIds: ["user_abc123", "user_xyz789"]
   ↓
6. Restore local storage
   ├─> family_id
   ├─> family_code
   ├─> elderly_name
   └─> setup_complete
   ↓
7. Navigate to permission setup
   ↓
8. User grants permissions again
   ↓
9. HOME PAGE - Fully recovered! ✅
```

**Firestore Security Rule for Recovery:**
```javascript
// firestore.rules, Line 73-85
function isRecoveringParent() {
  return request.auth != null &&
         request.auth.uid in request.resource.data.get('memberIds', []) &&
         !(request.auth.uid in resource.data.get('memberIds', [])) &&
         request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['memberIds', 'recoveredAt', 'recoveredBy']);
}

// Line 124: Added to UPDATE permission
allow update: if isRecoveringParent() || ...
```

---

### 6. CHILD APP JOINS (Using Connection Code)

**Flow Location:** Child app `lib/services/family_connection_service.dart`

#### Step 1: Child App Retrieves Connection Code Info

**Operation A - Look Up Connection Code:**
```dart
// family_data_manager.dart, Line 14-17
final connectionDoc = await _firestore
    .collection('connection_codes')
    .doc(connectionCode)
    .get();

final connectionData = connectionDoc.data()!;
final familyId = connectionData['familyId'] as String;
```

**Firestore Path:** `connection_codes/{connectionCode}`
**Operation Type:** READ (`.get()`)
**Data Retrieved:**
```json
{
  "familyId": "f_1234567890abc",
  "elderlyName": "김할머니",
  "createdAt": Timestamp
}
```

#### Step 2: Get Family Information

**Operation B - Retrieve Family Document:**
```dart
// family_data_manager.dart, Line 27
final doc = await _firestore.collection('families').doc(familyId).get();
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** READ (`.get()`)
**Data Retrieved:** All family settings and status

#### Step 3: Child App Approves Connection

**Operation C - Set Approval Status:**
```dart
// family_data_manager.dart, Line 120-124
await _firestore.collection('families').doc(familyId).update({
  'approved': approved,
  'approvedAt': FieldValue.serverTimestamp(),
  'memberIds': FieldValue.arrayUnion([userId]),
});
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** UPDATE (`.update()`)
**Data Updated:**
```json
{
  "approved": true,
  "approvedAt": Timestamp(server),
  "memberIds": ["user_id_1", "user_id_2"]
}
```

#### Step 4: Parent App Detects Approval

**Operation D - Real-time Approval Listener:**
```dart
// initial_setup_screen.dart, Line 137-138
_approvalSubscription = _firebaseService
    .listenForApproval(_generatedCode!)
    .listen((approved) {
      if (approved == true) {
        // Proceed to guide screen
      }
    });
```

**Firestore Operation:**
```dart
// family_data_manager.dart, Line 151
await for (final snapshot in _firestore.collection('families').doc(familyId).snapshots()) {
  final approved = snapshot.data()?['approved'] as bool?;
  yield approved;
}
```

**Firestore Path:** `families/{familyId}`
**Operation Type:** READ (`.snapshots()` - real-time listener)
**Listening For:** Field `approved` (null → true or false)

---

## CREATE, UPDATE, READ, DELETE OPERATIONS SUMMARY

### CREATE Operations

| Location | Firestore Path | Data | Trigger |
|----------|-----------------|------|---------|
| `firebase_service.dart:140` | `connection_codes/{code}` | `{familyId, elderlyName, createdAt}` | Setup Complete |
| `firebase_service.dart:147` | `families/{familyId}` | All family fields (see above) | Setup Complete |
| `firebase_service.dart:249-258` | `families/{familyId}/meals/{YYYY-MM-DD}` | Meal records array | Record Meal |

### UPDATE Operations

| Location | Firestore Path | Fields | Trigger |
|----------|-----------------|--------|---------|
| `firebase_service.dart:273-279` | `families/{familyId}` | `lastMeal` | Record Meal |
| `firebase_service.dart:452-456` | `families/{familyId}` | `lastPhoneActivity, lastActivityType, updateTimestamp` | Activity Update |
| `firebase_service.dart:477` | `families/{familyId}` | `alerts.survival` | Survival Alert |
| `firebase_service.dart:537-539` | `families/{familyId}` | `alerts.food` | Food Alert |
| `firebase_service.dart:623-627` | `families/{familyId}` | `lastPhoneActivity, lastActivityType, updateTimestamp` | Periodic Activity |
| `firebase_service.dart:656-663` | `families/{familyId}` | `location` | GPS Update |
| `firebase_service.dart:695-699` | `families/{familyId}` | `settings.alertHours` | Alert Settings Change |
| `family_data_manager.dart:102` | `families/{familyId}` | `settings.*` | Settings Update |
| `family_data_manager.dart:120-124` | `families/{familyId}` | `approved, approvedAt, memberIds` | Child App Approval |

### READ Operations

| Location | Firestore Path | Purpose |
|----------|-----------------|---------|
| `firebase_service.dart:57-58` | `connection_codes/{code}` | Verify unique code |
| `firebase_service.dart:105-109` | `connection_codes` (query) | Verify unique family ID |
| `firebase_service.dart:261-266` | `families/{familyId}/meals/{date}` | Get current meal count |
| `home_page.dart:72` | `families/{familyId}/meals/{date}` | Load today's meals |
| `family_data_manager.dart:14-31` | `connection_codes + families` | Get family info for child app |

### DELETE Operations

| Location | Firestore Path | Trigger |
|----------|-----------------|---------|
| `firebase_service.dart:406` | `families/{familyId}` | Timeout (2 min no approval) |

### LISTEN Operations (Real-time Streams)

| Location | Firestore Path | Purpose |
|----------|-----------------|---------|
| `family_data_manager.dart:151` | `families/{familyId}` | Listen for approval changes |
| `child_app_service.dart:112-117` | `families/{familyId}/recordings` | Listen for new recordings |

---

## Field Names and Data Structure Reference

### families/{familyId} Document

```json
{
  "familyId": "f_1234567890abc",
  "connectionCode": "4-digit-code",
  "elderlyName": "김할머니",
  "createdAt": Timestamp,
  "deviceInfo": "Android Device",
  "isActive": true,
  "approved": null,  // null = pending, true = approved, false = rejected
  "createdBy": "user_id",
  "memberIds": ["user_id"],
  
  "settings": {
    "survivalSignalEnabled": true/false,
    "familyContact": "",
    "alertHours": 12,
    "sleepTimeSettings": {
      "enabled": true,
      "sleepStartHour": 22,
      "sleepStartMinute": 30,
      "sleepEndHour": 6,
      "sleepEndMinute": 0,
      "activeDays": [1,2,3,4,5,6,7]
    }
  },
  
  "alerts": {
    "survival": Timestamp,  // null = inactive, Timestamp = active
    "food": Timestamp       // null = inactive, Timestamp = active
  },
  
  "lastMeal": {
    "timestamp": Timestamp,
    "count": 1,             // 0-3 meals recorded today
    "number": 1             // Which meal (1, 2, or 3)
  },
  
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "timestamp": Timestamp,
    "address": ""
  },
  
  "lastPhoneActivity": Timestamp,
  "lastActivityType": "first_activity" | "batched_activity" | "survival_signal_activation",
  "updateTimestamp": Timestamp,
  
  "approvedAt": Timestamp
}
```

### connection_codes/{connectionCode} Document

```json
{
  "familyId": "f_1234567890abc",
  "elderlyName": "김할머니",
  "createdAt": Timestamp
}
```

### families/{familyId}/meals/{YYYY-MM-DD} Document

```json
{
  "meals": [
    {
      "mealId": "1697596800000_1",
      "timestamp": "2025-10-18T12:30:00.000Z",
      "mealNumber": 1,
      "elderlyName": "김할머니",
      "createdAt": "2025-10-18T12:30:00.000Z"
    },
    {
      "mealId": "1697617200000_2",
      "timestamp": "2025-10-18T18:30:00.000Z",
      "mealNumber": 2,
      "elderlyName": "김할머니",
      "createdAt": "2025-10-18T18:30:00.000Z"
    }
  ],
  "date": "2025-10-18",
  "elderlyName": "김할머니"
}
```

---

## Security & Firebase Rules Reference

**Key Security Fields Used by Rules:**
- `createdBy`: User ID of setup creator
- `memberIds`: Array of approved family members
- `approved`: Approval status from child app
- `connectionCode`: Public lookup identifier

**Collection Access:**
- `connection_codes`: Public read-only (lookup only)
- `families`: Member-only read/write (via Firestore rules)
- `families/{id}/meals`: Member-only read (meals data)

---

## Throttling & Batching Strategy

### Activity Batching
- **First Activity:** Sent immediately
- **Long Inactivity Break:** Sent immediately (after 8+ hours of no updates)
- **2-Hour Interval:** Sent immediately
- **Between Updates:** Batched (not sent to Firebase)

### Location Throttling
- **LocationThrottler:** Prevents duplicate updates for same coordinates
- Calculates distance between consecutive updates
- Only sends if significant coordinate change detected

---

## User Flow Summary

```
1. USER SETUP COMPLETE ("설정 완료")
   ├── Generate unique connection code
   ├── Create connection_codes/{code} doc
   ├── Create families/{familyId} doc
   ├── Save settings to families/{familyId}
   ├── Listen for approval (real-time stream)
   └── If approved after 2 min: Proceed
       If rejected: Show error
       If timeout: Delete document

2. HOME PAGE LOADS
   ├── Force activity update to Firebase
   ├── Force GPS location update to Firebase
   └── Load today's meal count from Firebase

3. USER RECORDS MEAL
   ├── Force activity update (before meal)
   ├── Create/update families/{id}/meals/{date} doc
   ├── Get current meal count
   ├── Update families/{id}.lastMeal
   ├── Send FCM notification
   └── Force GPS update (after meal)

4. GPS LOCATION RECEIVED (Native)
   ├── Check throttling
   └── Update families/{id}.location

5. ACTIVITY MONITORING (Continuous)
   ├── Check batching logic
   └── Update families/{id}.lastPhoneActivity

6. CHILD APP JOINS
   ├── Read connection_codes/{code}
   ├── Get families/{id} info
   ├── User approves connection
   ├── Update families/{id}.approved
   └── Parent app detects approval via stream
```

---

## Key Methods by File

### firebase_service.dart (Main Service)
- `initialize()` - Initialize service
- `setupFamilyCode()` - Setup family on parent app
- `saveMealRecord()` - Record meal
- `updatePhoneActivity()` - Update activity timestamp
- `updateLocation()` - Update GPS location
- `forceActivityUpdate()` - Force immediate activity update
- `forceLocationUpdate()` - Force immediate GPS update
- `sendSurvivalAlert()` - Send survival alert
- `sendFoodAlert()` - Send food alert
- `clearSurvivalAlert()` - Clear survival alert
- `clearFoodAlert()` - Clear food alert
- `updateFamilySettings()` - Update settings
- `getFamilyInfo()` - Get family info by connection code
- `listenForApproval()` - Listen for approval changes (stream)

### family_data_manager.dart (Data Management)
- `getFamilyInfo()` - Get family document
- `getFamilyIdFromConnectionCode()` - Resolve familyId from code
- `getFamilyDataForChild()` - Get family data for child app
- `updateFamilySettings()` - Update settings
- `setApprovalStatus()` - Set approval status
- `listenForApproval()` - Listen for approval (async stream)

### location_service.dart (GPS Tracking)
- `initialize()` - Initialize location service
- `getCurrentLocation()` - Get current position
- `_handleLocationUpdate()` - Handle native location updates
- `updateLocation()` - Update location in Firebase

### home_page.dart (Main UI)
- `_recordMeal()` - Handle meal recording
- `_forceInitialUpdates()` - Force GPS and activity on startup
- `_forceLocationUpdateAfterMeal()` - Force GPS after meal

---

## Dependencies & Flow Summary

```
Parent App Setup:
  InitialSetupScreen → FirebaseService → FamilyDataManager → Firestore

Meal Recording:
  HomePage → FirebaseService → LocationService → Firestore
                            → FCMv1Service → Firebase Cloud Messaging

Activity Monitoring:
  ActivityBatcher → FirebaseService → Firestore

Location Tracking:
  LocationService (Native) → FirebaseService → Firestore

Child App Integration:
  ChildAppService → FamilyDataManager → Firestore
```

