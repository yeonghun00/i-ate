# Child App Firestore Behavior - Complete Analysis

**Date:** 2025-10-21
**Purpose:** Comprehensive documentation of how the child app interacts with Firestore
**For:** Parent app developer to create proper Firestore security rules

---

## Question 1: How does child app find the family using 4-digit code?

### A) How does child app query the connection code?

**Answer: Option 1 (with fallback to old structure)**

```dart
// PRIMARY METHOD (Lines 213-217 in child_app_service.dart)
db.collection('connection_codes')
  .where('code', isEqualTo: '1234')
  .where('isActive', isEqualTo: true)
  .limit(1)
  .get()

// FALLBACK METHOD (Lines 224-227 - backward compatibility)
db.collection('families')
  .where('connectionCode', isEqualTo: '1234')
  .limit(1)
  .get()
```

**Key Details:**
- Child app uses `.where('code', isEqualTo: connectionCode)` - NOT document ID
- **IMPORTANT:** Also filters by `isActive: true`
- Has fallback to old `families` collection for backward compatibility

### B) What fields does child app read from connection_codes?

**From connection_codes document (Line 242-243):**
```dart
final codeData = codeQuery.docs.first.data();
final familyId = codeData['familyId'] as String?;
```

**Fields read:**
- ✅ `code` (used in query)
- ✅ `familyId` (CRITICAL - used to look up family document)
- ✅ `isActive` (used in query)
- ❌ NOT reading: `elderlyName`, `createdAt` (these come from families doc)

**Then reads from families/{familyId} (Lines 253-262):**
```dart
final familyDoc = await _firestore.collection('families').doc(familyId).get();
final familyData = familyDoc.data()!;
familyData['familyId'] = familyId;
familyData['connectionCode'] = connectionCode;
```

**All fields from families document:**
- `elderlyName`
- `approved`
- `memberIds` (array)
- `createdAt`
- (All other family fields)

---

## Question 2: How does child app approve the connection?

### A) What does child app UPDATE when user approves?

**Answer: Complex transaction (Lines 302-347)**

```dart
// TRANSACTION updates families/{familyId}
db.collection('families').doc(familyId).update({
  approved: true,                          // Or false if rejected
  approvedAt: serverTimestamp(),
  approvedBy: childUserId,
  memberIds: arrayUnion(childUserId),      // ← ADDS CHILD USER ID
  childInfo: {
    [childUserId]: {
      email: childUser.email,
      displayName: childUser.displayName ?? 'Child User',
      joinedAt: serverTimestamp(),
      role: 'child'
    }
  }
})

// ALSO updates connection_codes (Lines 352-364)
db.collection('connection_codes').doc(codeDocId).update({
  isActive: false,
  usedAt: serverTimestamp(),
  usedBy: childUserId
})
```

**Full transaction flow:**
1. Re-reads family document inside transaction (for atomicity)
2. Gets current `memberIds` array
3. Adds child user ID to `memberIds` if not present
4. Updates `approved`, `approvedAt`, `approvedBy`
5. Adds child info to `childInfo` map
6. **Deactivates connection code** to prevent reuse

### B) Is child app user ID added to memberIds array?

**Answer: YES - child app adds their user ID to memberIds (Line 324-327)**

```dart
if (!currentMemberIds.contains(currentUser.uid)) {
  currentMemberIds.add(currentUser.uid);
  updateData['memberIds'] = currentMemberIds;
  secureLog.security('Adding current user to family memberIds');
}
```

**CRITICAL:** This happens in a transaction to ensure atomicity!

### C) At what point is child app user authenticated?

**Answer: BEFORE entering connection code**

Evidence (Lines 24-48 in child_app_service.dart):
```dart
Future<bool> _ensureAuthenticated() async {
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser != null) {
    return true; // Already authenticated
  }

  // If no user, try to authenticate anonymously
  final userCredential = await FirebaseAuth.instance.signInAnonymously();
  return userCredential.user != null;
}
```

**Authentication flow:**
1. Child app authenticates anonymously BEFORE any Firestore operations
2. All queries require authentication (enforced by `_ensureAuthenticated()`)
3. During approval, child uses `currentUser.uid` to add to memberIds

---

## Question 3: How does child app read family data after joining?

### A) What does child app need to READ continuously?

**ALL of the following from families/{familyId}:**

✅ **location** (GPS data) - Lines 473, 538, 550-551, 617-619
```dart
final rawLocationData = data['location'] as Map<String, dynamic>?;
final decryptedLocation = _decryptLocationData(rawLocationData, familyId);
```

✅ **lastMeal** (meal tracking) - Lines 444-456, 508-520
```dart
final mealData = data['lastMeal'] as Map<String, dynamic>?;
final todayMealCount = mealData?['count'] as int? ?? 0;
final mealTimestamp = mealData?['timestamp'];
```

✅ **lastPhoneActivity** (survival signal) - Lines 470, 534
```dart
data['blastPhoneActivity'] ?? data['lastPhoneActivity']
```

✅ **lastActive** (app usage) - Lines 471, 535
```dart
data['lastActive']
```

✅ **alerts** (alert status) - Lines 459-464, 522-528
```dart
final alerts = data['alerts'] as Map<String, dynamic>?;
final survivalAlert = {
  'isActive': alerts?['survival'] != null,
  'timestamp': alerts?['survival'],
  'message': alerts?['survival'] != null ? '장시간 활동 없음' : null,
};
```

✅ **settings** (family settings) - Line 537, 629
```dart
data['settings']
```

✅ **elderlyName** - Lines 264, 472, 536, 559, 627

✅ **memberIds** - Lines 264, 312, 671-672, 744
```dart
final memberIds = List<String>.from(familyData['memberIds'] ?? []);
if (!memberIds.contains(currentUser.uid)) {
  // User was removed from family
}
```

✅ **approved** - Line 264
```dart
familyData['approved']
```

✅ **childInfo** - Line 341
```dart
currentFamilyData['childInfo'] ?? {}
```

✅ **Subcollection: recordings/{date}** - Lines 345-374, 396-423
```dart
db.collection('families')
  .doc(familyId)
  .collection('recordings')
  .orderBy(FieldPath.documentId, descending: true)
  .get()
```

**From recordings subcollection, reads:**
```dart
{
  'recordings': [
    {
      'audioUrl': '...',
      'photoUrl': '...',
      'timestamp': '...',
      'elderlyName': '...'
    }
  ]
}
```

❌ **NOT reading:** `meals/{date}` subcollection

### B) Does child app use real-time listeners or one-time reads?

**Answer: BOTH**

**Real-time listeners (snapshots):**
```dart
// Line 464: Listen to new recordings
Stream<List<Map<String, dynamic>>> listenToNewRecordings(String connectionCode)
  await for (final snapshot in _firestore
    .collection('families')
    .doc(familyId)
    .collection('recordings')
    .snapshots())

// Line 567: Listen to survival status
Stream<Map<String, dynamic>> listenToSurvivalStatus(String connectionCode)
  await for (final snapshot in _firestore
    .collection('families')
    .doc(familyId)
    .snapshots())

// Line 789: Listen to family existence
Stream<bool> listenToFamilyExistence(String connectionCode)
  await for (final snapshot in _firestore
    .collection('families')
    .doc(familyId)
    .snapshots(includeMetadataChanges: true))
```

**One-time reads (get):**
```dart
// Line 213: Get connection code
.collection('connection_codes')
  .where('code', isEqualTo: connectionCode)
  .get()

// Line 253: Get family document
.collection('families').doc(familyId).get()

// Line 345: Get all recordings
.collection('families')
  .doc(familyId)
  .collection('recordings')
  .get()

// Line 439: Get survival status (one-time)
await _firestore.collection('families').doc(familyId).get()
```

---

## Question 4: What does child app WRITE to Firestore?

### A) Does child app send any data back to parent?

**YES - Multiple types:**

✅ **Alert acknowledgments** (Lines 657-663)
```dart
await _firestore.collection('families').doc(familyId).update({
  'alerts.survival': null,
  'alertsCleared.survival': FieldValue.serverTimestamp(),
  'alertsClearedBy.survival': currentUser?.uid ?? 'Child App',
  'lastPhoneActivity': FieldValue.serverTimestamp(),
  'blastPhoneActivity': FieldValue.serverTimestamp(),
});
```

✅ **Settings changes** (Lines 687-691)
```dart
await _firestore.collection('families').doc(familyId).update({
  'settings.alertHours': value,
  'settings.survivalSignalEnabled': value,
  'settings.voiceRecordingEnabled': value,
});
```

✅ **Approval status** (Lines 315-343)
```dart
{
  'approved': true,
  'approvedAt': FieldValue.serverTimestamp(),
  'approvedBy': currentUser.uid,
  'memberIds': [currentUser.uid],
  'childInfo': {
    [currentUser.uid]: {
      'email': '...',
      'displayName': '...',
      'joinedAt': FieldValue.serverTimestamp(),
      'role': 'child'
    }
  }
}
```

✅ **Connection code deactivation** (Lines 360-364)
```dart
db.collection('connection_codes').doc(codeDocId).update({
  'isActive': false,
  'usedAt': FieldValue.serverTimestamp(),
  'usedBy': currentUser.uid
})
```

❌ **NOT writing:** FCM tokens, Read receipts (not implemented)

### B) Fields child app updates:

**In families/{familyId}:**
```javascript
{
  // Approval fields
  "approved": true,
  "approvedAt": serverTimestamp(),
  "approvedBy": "childUserId",
  "memberIds": ["childUserId"],
  "childInfo": {
    "childUserId": {
      "email": "child@example.com",
      "displayName": "Child Name",
      "joinedAt": serverTimestamp(),
      "role": "child"
    }
  },

  // Alert clearing
  "alerts.survival": null,
  "alertsCleared.survival": serverTimestamp(),
  "alertsClearedBy.survival": "childUserId",
  "lastPhoneActivity": serverTimestamp(),
  "blastPhoneActivity": serverTimestamp(),

  // Settings updates
  "settings.alertHours": 12,
  "settings.survivalSignalEnabled": true,
  "settings.voiceRecordingEnabled": true
}
```

**In connection_codes/{docId}:**
```javascript
{
  "isActive": false,
  "usedAt": serverTimestamp(),
  "usedBy": "childUserId"
}
```

---

## Question 5: Connection Code Collection Structure

### A) Is the 4-digit code stored as:

**Answer: Field value (using .add() which creates random ID)**

**Current parent app behavior:**
```dart
await _firestore.collection('connection_codes').add({
  'code': connectionCode,        // 4-digit code as FIELD
  'familyId': familyId,
  'elderlyName': elderlyName,
  'isActive': true,
  'createdAt': FieldValue.serverTimestamp(),
});
```

**This creates:**
```
connection_codes/
  ├── random_id_123abc/      ← Auto-generated document ID
  │   ├── code: "1234"       ← 4-digit code as field
  │   ├── familyId: "f_xyz"
  │   ├── elderlyName: "김할머니"
  │   ├── isActive: true
  │   └── createdAt: timestamp
```

**Child app queries by field:**
```dart
.where('code', isEqualTo: '1234')  // Searches the 'code' field
```

### B) Should you change parent app to use 4-digit code as document ID?

**Recommendation: YES, change it for better performance**

**Benefits:**
1. **Faster lookup** - Direct document read instead of query
2. **Simpler rules** - Can check `request.resource.id` instead of querying
3. **No index needed** - Document ID reads don't require indexes
4. **Clearer structure** - Code is the natural document identifier

**Change to:**
```dart
// Parent app - instead of .add()
await _firestore.collection('connection_codes').doc(connectionCode).set({
  'familyId': familyId,
  'elderlyName': elderlyName,
  'isActive': true,
  'createdAt': FieldValue.serverTimestamp(),
});
```

**Child app - change query to:**
```dart
// Instead of .where() query
final codeDoc = await _firestore
  .collection('connection_codes')
  .doc(connectionCode)  // Direct document read
  .get();

if (codeDoc.exists && codeDoc.data()?['isActive'] == true) {
  final familyId = codeDoc.data()!['familyId'];
  // Continue...
}
```

**This creates:**
```
connection_codes/
  ├── 1234/                  ← 4-digit code as document ID
  │   ├── familyId: "f_xyz"
  │   ├── elderlyName: "김할머니"
  │   ├── isActive: true
  │   └── createdAt: timestamp
```

**⚠️ REQUIRES CODE CHANGE IN BOTH APPS**

---

## Question 6: Multiple Family Members

### A) Can multiple child app users join the same family?

**Answer: YES - designed for multiple children monitoring one parent**

**Evidence:**
```dart
// Line 312: Gets existing memberIds array
final currentMemberIds = List<String>.from(currentFamilyData['memberIds'] ?? []);

// Line 324: Adds new child if not already present
if (!currentMemberIds.contains(currentUser.uid)) {
  currentMemberIds.add(currentUser.uid);
}

// Line 340: Merges child info (preserves existing children)
updateData['childInfo'] = {
  ...Map<String, dynamic>.from(currentFamilyData['childInfo'] ?? {}),
  ...childInfo,  // Add new child
};
```

**Result:**
```javascript
{
  "memberIds": ["child1_uid", "child2_uid", "child3_uid"],
  "childInfo": {
    "child1_uid": { "email": "...", "displayName": "Son" },
    "child2_uid": { "email": "...", "displayName": "Daughter" },
    "child3_uid": { "email": "...", "displayName": "Grandson" }
  }
}
```

### B) Should all members see the same data?

**Answer: YES - all family members see everything**

**Evidence:**
- All read operations check `request.auth.uid in resource.data.memberIds`
- No role-based filtering (all children have `role: 'child'`)
- No per-member permissions
- All children can:
  - View location
  - View recordings
  - Clear alerts
  - Update settings

---

## Question 7: Current Errors You're Seeing

### Error Context

**Based on code analysis, expected errors:**

**Error 1 - When parent clicks "설정 완료":**
```
No error expected - parent app creates documents successfully
Document created in connection_codes with random ID
Document created in families/{familyId}
```

**Error 2 - When child app tries to read connection code:**

**BEFORE approval (anonymous user):**
```
FirebaseException: permission-denied

Reason: Anonymous user trying to query connection_codes collection
Security rules likely block: .where('code', isEqualTo: '1234')

Child app error handling (Line 96-97):
"Family info access denied - user may not be in memberIds array"
```

**Error 3 - When child app tries to read family data:**

**BEFORE approval:**
```
FirebaseException: permission-denied

Reason: User not in memberIds array yet
Security rules block: request.auth.uid in resource.data.memberIds

Child app error handling (Line 98-99):
"Family data access denied - user may have been removed from family"
```

**AFTER approval:**
```
No error - user is in memberIds and can read all family data
```

---

## Test Cases - Current Behavior

### Test Case 1: Parent App Creates Family

**Steps:**
1. Parent enters name: "김할머니"
2. Parent clicks "설정 완료"

**Expected behavior:**
✅ Shows 4-digit code successfully
✅ Firestore documents created:
```
connection_codes/random_id_abc/
  code: "1234"
  familyId: "f_xyz"
  elderlyName: "김할머니"
  isActive: true
  createdAt: timestamp

families/f_xyz/
  connectionCode: "1234"
  elderlyName: "김할머니"
  approved: false
  memberIds: ["parentUserId"]
  isActive: true
  createdAt: timestamp
```

### Test Case 2: Child App Enters Code

**Steps:**
1. Child app user authenticates anonymously
2. Child app user enters: "1234"
3. Child app searches for code

**Current behavior with restrictive rules:**
❌ Error: "Permission denied" on connection_codes query

**Expected with proper rules:**
✅ Finds family successfully
✅ Shows confirmation dialog: "김할머니님과 연결하시겠습니까?"

### Test Case 3: After Approval

**Steps:**
1. Child app approves connection
2. Transaction updates families/{familyId}
3. Parent app detects approval (via listener)

**Expected behavior:**
✅ Child app: Navigates to home screen
✅ Child app: Can read all family data (location, meals, recordings)
✅ Parent app: Detects `approved: true` and proceeds
✅ Both apps work normally

**Potential errors if rules are wrong:**
❌ Child can't add self to memberIds (permission denied on write)
❌ Child can't deactivate connection code (permission denied)
❌ Parent can't see approval change (listener blocked)

---

## Summary - Required Firestore Rules

### What child app needs permission to do:

**BEFORE approval (anonymous user):**
1. ✅ READ `connection_codes` collection (query by code)
2. ✅ READ `families/{familyId}` document (to show elderly name)
3. ✅ WRITE to `families/{familyId}` (to approve and add self to memberIds)
4. ✅ WRITE to `connection_codes/{docId}` (to deactivate after approval)

**AFTER approval (user in memberIds):**
1. ✅ READ `families/{familyId}` (all fields)
2. ✅ READ `families/{familyId}/recordings/{date}` (subcollection)
3. ✅ WRITE to `families/{familyId}` (update alerts, settings, lastPhoneActivity)
4. ✅ LISTEN to `families/{familyId}` (real-time updates)

---

## Recommended Rule Structure

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Connection codes - allow anonymous read for code lookup
    match /connection_codes/{codeId} {
      // Anyone authenticated can read to look up family
      allow read: if request.auth != null;

      // Parent app can create
      allow create: if request.auth != null;

      // Child app can update to deactivate after approval
      allow update: if request.auth != null &&
                       request.resource.data.isActive == false;
    }

    // Family documents
    match /families/{familyId} {
      // Allow read if:
      // 1. User is in memberIds (approved child)
      // 2. OR document not approved yet (for initial lookup)
      allow read: if request.auth != null && (
        request.auth.uid in resource.data.memberIds ||
        resource.data.approved == false
      );

      // Allow write if:
      // 1. User is in memberIds (approved child can update)
      // 2. OR approving connection (child adding self to memberIds)
      allow write: if request.auth != null && (
        request.auth.uid in resource.data.memberIds ||
        (
          // Approval operation
          request.resource.data.approved == true &&
          request.auth.uid in request.resource.data.memberIds
        )
      );

      // Recordings subcollection
      match /recordings/{recordingId} {
        allow read: if request.auth != null &&
                       request.auth.uid in get(/databases/$(database)/documents/families/$(familyId)).data.memberIds;
        allow write: if request.auth != null &&
                        request.auth.uid in get(/databases/$(database)/documents/families/$(familyId)).data.memberIds;
      }
    }
  }
}
```

---

**Document prepared by:** Claude Code (based on child_app_service.dart analysis)
**Date:** 2025-10-21
**Version:** 1.0
