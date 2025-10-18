# Firebase Firestore Data Guide - Thanks Everyday App

Simple guide showing how data is saved, updated, and deleted in Firestore.

---

## 1. User Clicks "설정 완료" (Setup Complete)

### What Happens:
Creates a new family and connection code

### Data Created:

**Collection: `connection_codes`**
- Document ID: `"8992"` (4-digit random code)
- Fields:
  ```
  familyId: "family_7fdb45e5-b4e2-45c2-9371-6e544770d935"
  elderlyName: "김할머니"
  createdAt: 2025-01-18 20:36:38
  ```

**Collection: `families`**
- Document ID: `"family_7fdb45e5-b4e2-45c2-9371-6e544770d935"`
- Fields:
  ```
  familyId: "family_7fdb45e5..."
  connectionCode: "8992"
  elderlyName: "김할머니"
  createdBy: "IlkRjY5o5oUQauPetckS1Oq3jk92"
  memberIds: ["IlkRjY5o5oUQauPetckS1Oq3jk92"]
  approved: null
  isActive: true
  createdAt: 2025-01-18 20:36:38
  settings: {survivalSignalEnabled: false, familyContact: "", alertHours: 12}
  alerts: {survival: null, food: null}
  lastMeal: {timestamp: null, count: 0, number: null}
  location: {latitude: null, longitude: null, timestamp: null, address: ""}
  lastPhoneActivity: null
  ```

**Result**: User sees 4-digit code "8992" on screen, waits for child app approval

---

## 2. User Records a Meal (Clicks "식사했어요")

### What Happens:
Saves meal record and updates activity

### Data Created:

**Collection: `families/{familyId}/meals`**
- Document ID: `"2025-01-18"` (today's date)
- Fields:
  ```
  meals: [
    {
      mealId: "1737195398953_1"
      timestamp: "2025-01-18T20:36:38.953"
      mealNumber: 1
      elderlyName: "김할머니"
      createdAt: "2025-01-18T20:36:38.953"
    }
  ]
  date: "2025-01-18"
  elderlyName: "김할머니"
  ```

### Data Updated:

**Collection: `families/{familyId}`**
- Updated fields:
  ```
  lastPhoneActivity: 2025-01-18 20:36:38  (updated)
  lastActivityType: "batched_activity"     (updated)
  updateTimestamp: 2025-01-18 20:36:38     (updated)
  lastMeal: {
    timestamp: 2025-01-18 20:36:38         (updated)
    count: 1                                (updated)
    number: 1                               (updated)
  }
  ```

**Result**: Child app sees meal count update in real-time

---

## 3. GPS Location Updates (Every 2 Minutes When Enabled)

### What Happens:
Location service updates GPS coordinates

### Data Updated:

**Collection: `families/{familyId}`**
- Updated fields:
  ```
  location: {
    latitude: 37.5665          (updated)
    longitude: 126.9780        (updated)
    timestamp: 2025-01-18...   (updated)
    address: "서울시 중구..."     (updated)
  }
  ```

**Throttling**: Only updates if location changed significantly or 2 minutes passed

**Result**: Child app sees updated location on map

---

## 4. Survival Signal Updates (Screen On/Off Detection)

### What Happens:
Phone screen activity is detected every 2 minutes

### Data Updated:

**Collection: `families/{familyId}`**
- Updated fields:
  ```
  lastPhoneActivity: 2025-01-18 20:23:02  (updated)
  lastActivityType: "batched_activity"     (updated)
  updateTimestamp: 2025-01-18 20:23:02     (updated)
  ```

**Batching**: Activity is batched and sent every 2 minutes (not every screen touch)

**Result**: Child app knows parent is using phone

---

## 5. Alert Settings Changed (User Changes Alert Hours)

### What Happens:
User changes "12시간" to "24시간"

### Data Updated:

**Collection: `families/{familyId}`**
- Updated fields:
  ```
  settings: {
    alertHours: 24.0           (updated from 12.0)
    survivalSignalEnabled: true
    familyContact: ""
  }
  ```

**Result**: Child app gets alert after 24 hours instead of 12

---

## 6. Child App Joins (Enters Connection Code)

### What Happens:
Child app enters "8992" and approves

### Data Read:

**Collection: `connection_codes/8992`**
- Gets:
  ```
  familyId: "family_7fdb45e5..."
  elderlyName: "김할머니"
  ```

**Collection: `families/{familyId}`**
- Gets all family data to show for approval

### Data Updated:

**Collection: `families/{familyId}`**
- Updated fields:
  ```
  memberIds: ["parent_uid", "child_uid"]   (child added)
  approved: true                            (updated from null)
  ```

**Result**: Parent app proceeds to guide screen, both apps connected

---

## 7. User Deletes Family Data (Settings → Delete)

### What Happens:
User wants to reset and delete all data

### Data Deleted:

**Collection: `families/{familyId}`**
- Entire document deleted

**Data Read Then Deleted:**

**Collection: `connection_codes`**
- Queries: `where connectionCode == "8992"`
- Deletes matching document

**Result**: All family data removed, app returns to setup screen

---

## 8. Account Recovery (App Reinstalled)

### What Happens:
User reinstalls app, enters name + connection code

### Data Read:

**Collection: `families`**
- Queries: `where connectionCode == "8992"`
- Gets family document
- Checks if `elderlyName` matches entered name

### Data Updated:

**Local Storage Only** (SharedPreferences):
- Restores:
  ```
  family_id: "family_7fdb45e5..."
  family_code: "8992"
  elderly_name: "김할머니"
  setup_complete: true
  ```

**No Firestore changes** - just reconnects to existing data

**Result**: User regains access to their family data

---

## Data Structure Summary

### Collections:

```
firestore
│
├── connection_codes/
│   └── {4-digit-code}/
│       ├── familyId
│       ├── elderlyName
│       └── createdAt
│
├── families/
│   └── {familyId}/
│       ├── familyId
│       ├── connectionCode
│       ├── elderlyName
│       ├── createdBy
│       ├── memberIds[]
│       ├── approved
│       ├── isActive
│       ├── settings{}
│       ├── alerts{}
│       ├── lastMeal{}
│       ├── location{}
│       ├── lastPhoneActivity
│       │
│       └── meals/
│           └── {YYYY-MM-DD}/
│               ├── meals[]
│               ├── date
│               └── elderlyName
│
└── fcmTokens/
    └── {tokenId}/
        ├── token
        ├── userId
        └── lastUpdated
```

---

## When Data is Updated (Frequency)

| Data | Frequency | Trigger |
|------|-----------|---------|
| **Meal records** | 1-3 times/day | User clicks "식사했어요" |
| **GPS location** | Every 2 minutes | When GPS enabled + location changed |
| **Survival signal** | Every 2 minutes | Phone screen on/off detected |
| **Alert settings** | Rarely | User changes settings |
| **Connection code** | Once | Family creation |
| **Member join** | Once | Child app approval |

---

## Real-time Updates (What Child App Sees Immediately)

- ✅ New meals recorded
- ✅ GPS location changes
- ✅ Survival signal updates
- ✅ Alert status changes
- ✅ Family approval status

All use Firestore `.snapshots()` for real-time sync.

---

**Note**: Data is only deleted when user explicitly clicks "Delete" in settings. Everything else is CREATE or UPDATE operations.
