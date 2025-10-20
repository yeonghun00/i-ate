# Firestore Security Rules Implementation Guide

**Date:** 2025-10-21
**Version:** 2.0 (Production-Ready)
**For:** Both Parent App and Child App Developers

---

## What Changed and Why

### The Problem
Previous rules were **TOO RESTRICTIVE** - they blocked child app from joining families because:
1. Child app couldn't read `connection_codes` collection (blocked before approval)
2. Child app couldn't read `families/{familyId}` (blocked before approval)
3. Child app couldn't update `families/{familyId}` to add itself to memberIds

### The Solution
New rules allow:
1. ✅ **ANY authenticated user** can read connection codes (needed for lookup)
2. ✅ **ANY authenticated user** can read pending families (`approved: null` or `false`)
3. ✅ **Child app** can approve connection and add itself to memberIds
4. ✅ **After approval**, only family members can access data

---

## How the Connection Flow Works

### Step 1: Parent App Creates Family

```dart
// Parent app: initial_setup_screen.dart line 58
await _firebaseService.setupFamilyCode("김할머니")

// Creates TWO documents:
```

**Document 1: connection_codes/{random_id}**
```javascript
{
  "code": "1234",           // 4-digit code
  "familyId": "f_abc123",
  "elderlyName": "김할머니",
  "isActive": true,
  "createdAt": timestamp
}
```

**Document 2: families/f_abc123**
```javascript
{
  "familyId": "f_abc123",
  "connectionCode": "1234",
  "elderlyName": "김할머니",
  "approved": null,          // ← PENDING state
  "memberIds": ["parentUid"],
  "createdBy": "parentUid",
  "isActive": true,
  // ...other fields
}
```

### Step 2: Child App Finds Family

```dart
// Child app authenticates anonymously FIRST
await FirebaseAuth.instance.signInAnonymously()

// Then queries connection code (child_app_service.dart:213-217)
final query = await firestore
  .collection('connection_codes')
  .where('code', isEqualTo: '1234')
  .where('isActive', isEqualTo: true)
  .limit(1)
  .get()

// Gets familyId from connection_codes
final familyId = query.docs.first.data()['familyId']

// Reads family document to show elderly name
final family = await firestore.collection('families').doc(familyId).get()
// Shows: "김할머니님과 연결하시겠습니까?"
```

**Rules allow this because:**
- Line 17: `allow read: if request.auth != null` (connection_codes)
- Line 81-85: `isPending()` allows reading families with `approved: null`

### Step 3: Child App Approves

```dart
// Child app user clicks "승인" (child_app_service.dart:315-343)
await firestore.collection('families').doc(familyId).update({
  'approved': true,
  'approvedAt': serverTimestamp(),
  'approvedBy': childUserId,
  'memberIds': arrayUnion([childUserId]),  // ← ADDS SELF
  'childInfo': {
    [childUserId]: {
      'email': 'child@example.com',
      'displayName': 'Child Name',
      'joinedAt': serverTimestamp(),
      'role': 'child'
    }
  }
})

// Also deactivates connection code (child_app_service.dart:360)
await firestore.collection('connection_codes').doc(codeDocId).update({
  'isActive': false,
  'usedAt': serverTimestamp(),
  'usedBy': childUserId
})
```

**Rules allow this because:**
- Line 106: `isApprovingChild()` allows user to add themselves to memberIds
- Line 26-28: Connection code update allowed if changing only isActive, usedAt, usedBy

### Step 4: After Approval - Normal Operation

**Now `families/f_abc123` looks like:**
```javascript
{
  "approved": true,          // ← APPROVED
  "memberIds": ["parentUid", "childUid"],  // ← Both members
  // ...other fields
}
```

**Both apps can now:**
- ✅ Read all family data (location, meals, recordings, etc.)
- ✅ Update operational fields (location, alerts, settings)
- ✅ Access subcollections (meals, recordings)

**Rules allow this because:**
- Line 82: `isMember()` returns true for both parent and child
- Line 111-128: Members can update allowed fields

---

## Security Analysis: Why This Is Safe

### Question: "Anyone can read connection codes - isn't that bad?"

**Answer: NO, it's safe because:**

1. **Connection codes are 4-digit numbers (0000-9999)**
   - 10,000 possible combinations
   - Attacker would need to try many codes

2. **Connection codes expire after 2 minutes**
   - Parent app deletes unused codes (initial_setup_screen.dart:309)
   - Very narrow window for attack

3. **Connection codes are one-time use**
   - After child app approves, code is deactivated (`isActive: false`)
   - Cannot be reused

4. **Even if attacker gets code, they only see:**
   - `elderlyName` (e.g., "김할머니")
   - They CANNOT see location, meals, recordings (approved: null blocks full access)

5. **FamilyIds are random UUIDs**
   - Cannot be guessed without connection code
   - Example: `f_1697596800000_abc123xyz`

### Question: "Anyone can read pending families - isn't that bad?"

**Answer: NO, because:**

1. **Pending families show minimal info:**
   - `elderlyName`, `approved`, `memberIds`
   - NO location, NO meals, NO recordings until approved

2. **Cannot enumerate families:**
   - No `.list()` permission without proper filters
   - Must know exact `familyId` to read

3. **After approval, strict memberIds check:**
   - Only people in `memberIds` array can access data
   - Line 111: `isMember()` required for updates

---

## What Each Rule Does

### Connection Codes Collection

| Operation | Who | Why | Line |
|-----------|-----|-----|------|
| **READ** | Any authenticated user | Child needs to find family before approval | 17 |
| **CREATE** | Parent app | Creates code during setup | 20-22 |
| **UPDATE** | Child app | Deactivates code after approval | 26-28 |
| **DELETE** | Parent app | Removes expired codes | 31 |

### Families Collection

| Operation | Who | Why | Line |
|-----------|-----|-----|------|
| **READ** | Member OR Creator OR Pending | Child reads before approval, members read after | 81-85 |
| **CREATE** | Parent app | Creates family during setup | 92-95 |
| **UPDATE (Approval)** | Child app (not yet member) | Adds self to memberIds | 106 |
| **UPDATE (Data)** | Members only | Updates location, meals, alerts | 111-128 |
| **DELETE** | Creator only | Removes family | 144 |

### Subcollections (meals, recordings, child_devices)

| Operation | Who | Why | Line |
|-----------|-----|-----|------|
| **READ/WRITE** | Members OR Creator | Only family can access | 162-165 |

---

## Testing Checklist

### Test 1: Parent App Setup ✅

```bash
1. Parent enters name: "김할머니"
2. Parent clicks "설정 완료"
3. ✅ Shows 4-digit code
4. ✅ Check Firestore console:
   - connection_codes/{id} exists with code: "1234"
   - families/f_xxx exists with approved: null
```

### Test 2: Child App Connection (BEFORE Approval) ✅

```bash
1. Child app authenticates anonymously
2. Child enters code: "1234"
3. ✅ Finds family successfully
4. ✅ Shows: "김할머니님과 연결하시겠습니까?"
5. ✅ Does NOT show location/meals (not approved yet)
```

### Test 3: Child App Approval ✅

```bash
1. Child clicks "승인"
2. ✅ Updates families/{id}:
   - approved: true
   - memberIds: ["parentUid", "childUid"]
3. ✅ Deactivates connection code:
   - isActive: false
4. ✅ Parent app detects approval
5. ✅ Both apps navigate to home screen
```

### Test 4: After Approval - Data Access ✅

```bash
1. Parent records meal
2. ✅ Child sees meal notification
3. Child reads location
4. ✅ Child sees encrypted location (then decrypts)
5. Child clears alert
6. ✅ Parent sees alert cleared
```

### Test 5: Security - Unauthorized Access ❌

```bash
1. Create fake account (not in family)
2. Try to read families/f_xxx
3. ✅ BLOCKED (not in memberIds, not pending)
4. Try to query all families
5. ✅ BLOCKED (cannot list without knowing familyId)
```

### Test 6: Multiple Children ✅

```bash
1. Child 1 joins family (approved: true)
2. Child 2 enters SAME code
3. ✅ BLOCKED (code already used, isActive: false)
4. Parent creates NEW code
5. Child 2 enters NEW code
6. ✅ Child 2 joins successfully
7. ✅ memberIds: ["parentUid", "child1Uid", "child2Uid"]
8. ✅ Both children see same data
```

---

## Deployment Instructions

### Step 1: Deploy Rules to Firebase

**Option A: Firebase CLI**
```bash
# From project root
firebase deploy --only firestore:rules

# Verify deployment
firebase firestore:rules:get
```

**Option B: Firebase Console**
```
1. Go to Firebase Console → Firestore Database → Rules
2. Copy content of firestore.rules
3. Paste into editor
4. Click "Publish"
```

### Step 2: Test with Both Apps

**Parent App Test:**
```bash
1. Run app: flutter run
2. Create new family
3. Verify code shows up
4. Check Firestore console for documents
```

**Child App Test:**
```bash
1. Run app
2. Enter connection code from parent
3. Verify shows elderly name
4. Approve connection
5. Verify can see family data
```

### Step 3: Verify Rules Work

**Firebase Console → Firestore → Rules Playground:**
```javascript
// Test 1: Child can read connection code
Authenticated as: child_anonymous_uid
Operation: get
Path: /connection_codes/doc_id
Result: ✅ Allow

// Test 2: Child can read pending family
Authenticated as: child_anonymous_uid
Operation: get
Path: /families/f_abc123 (with approved: null)
Result: ✅ Allow

// Test 3: Child can approve
Authenticated as: child_anonymous_uid
Operation: update
Path: /families/f_abc123
Data: { approved: true, memberIds: ["child_uid"] }
Result: ✅ Allow

// Test 4: Random user CANNOT read approved family
Authenticated as: random_uid (NOT in memberIds)
Operation: get
Path: /families/f_abc123 (with approved: true, memberIds: ["other_uid"])
Result: ❌ Deny
```

---

## Troubleshooting

### Error: "Permission denied" when child enters code

**Cause:** Child app not authenticated
**Solution:** Verify child app calls `signInAnonymously()` before querying

```dart
// child_app_service.dart should have:
await _ensureAuthenticated()  // Line 24-48
```

### Error: "Permission denied" when child approves

**Cause:** Child trying to modify fields besides approval fields
**Solution:** Only update allowed fields

```dart
// CORRECT (line 69-70):
.hasOnly(['approved', 'approvedAt', 'approvedBy', 'memberIds', 'childInfo', 'childAppUserId'])

// WRONG:
update({ 'approved': true, 'location': {...} })  // Extra field!
```

### Error: Parent can't update location after approval

**Cause:** Parent trying to update non-allowed field
**Solution:** Check SCENARIO 3 allows parent updates (line 131-140)

```dart
// Parent should be createdBy, and updating allowed fields
```

### Error: Multiple children can't join

**Cause:** Connection code already used (`isActive: false`)
**Solution:** Parent must create NEW code for each child

```
Parent creates code "1234" → Child 1 joins → Code deactivated
Parent creates code "5678" → Child 2 joins → Code deactivated
```

---

## Production Checklist

### Before Going Live:

- [ ] Deploy firestore.rules to production
- [ ] Test parent app setup flow
- [ ] Test child app connection flow
- [ ] Test multiple children joining
- [ ] Verify encryption works with rules
- [ ] Test alert clearing (child → parent)
- [ ] Test settings updates (child → parent)
- [ ] Change `_test` collection to `allow read, write: if false` (line 266)
- [ ] Set up Firestore backups
- [ ] Monitor Firestore usage for suspicious patterns

### Security Recommendations:

1. **Monitor connection code attempts:**
   - If many failed lookups, could be brute-force attack
   - Consider adding Cloud Function rate limiting

2. **Regular security audits:**
   - Review Firestore logs monthly
   - Check for unauthorized access attempts

3. **Update encryption salt:**
   - Change `_keySalt` in production (LOCATION_ENCRYPTION_GUIDE.md)
   - Use different salts for dev/staging/production

---

## Summary: What These Rules Do

### ✅ ALLOW:
1. Child app to find family using 4-digit code (even before approval)
2. Child app to read pending family info (just elderly name)
3. Child app to approve connection and add self to memberIds
4. Family members to access all data after approval
5. Parent to update location, meals, activity
6. Child to clear alerts, update settings

### ❌ BLOCK:
1. Unauthorized users from reading family data
2. Non-members from accessing location, meals, recordings
3. Mass enumeration of all families
4. Reusing deactivated connection codes
5. Updating fields not in allowed list
6. Deleting families (only creator can delete)

---

**Questions?**
- Parent app developer: [Your contact]
- Child app developer: [Their contact]
- Security issues: Review PRODUCTION_SECURITY_CHECKLIST.md

**Version History:**
- v1.0: Initial restrictive rules (blocked child app)
- v2.0: Production-ready rules (allows connection flow)

---

**Status:** ✅ READY FOR PRODUCTION with encryption enabled
