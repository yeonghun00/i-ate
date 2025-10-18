# Firebase Firestore Data Flow Analysis - Complete Documentation

## Quick Navigation

This analysis provides comprehensive documentation of all Firebase Firestore operations in the Thanks Everyday app.

### Three Document Files:

#### 1. **FIREBASE_FLOW_SUMMARY.txt** (START HERE)
Quick reference summary with key findings, statistics, and breakdown of all operations.
- Best for: Quick overview, finding specific operation locations
- Contains: Operation counts, critical field names, exact user action flows
- Length: 1 page quick reference

#### 2. **COMPLETE_FIREBASE_DATA_FLOW.md** (DETAILED REFERENCE)
Comprehensive technical documentation with code snippets and line-by-line explanations.
- Best for: Understanding complete flows, implementation details
- Contains: 
  - 5 user action flows with exact Dart code (lines referenced)
  - All field names and data structures in JSON format
  - Complete CREATE/UPDATE/READ/DELETE/LISTEN operation tables
  - Security field references
- Length: 866 lines (24KB)

#### 3. **FIREBASE_DATA_FLOW_DIAGRAM.md** (VISUAL REFERENCE)
ASCII diagrams showing data flow and dependencies between operations.
- Best for: Visual learners, understanding operation sequences
- Contains:
  - 10 ASCII flow diagrams for different scenarios
  - Data dependency tree
  - Real-time sync points
  - Operation type summaries
- Length: 443 lines (15KB)

---

## Reading Guide By Use Case

### "I need a quick overview"
1. Read: FIREBASE_FLOW_SUMMARY.txt (3 min)
2. Skim: COMPLETE_FIREBASE_DATA_FLOW.md sections (10 min)

### "I need to understand setup flow"
1. Read: FIREBASE_DATA_FLOW_DIAGRAM.md → "1. Setup Complete Flow"
2. Read: COMPLETE_FIREBASE_DATA_FLOW.md → "1. USER CLICKS 설정 완료"
3. Reference: firebase_service.dart lines 74-195 + initial_setup_screen.dart lines 44-129

### "I need to understand meal recording"
1. Read: FIREBASE_DATA_FLOW_DIAGRAM.md → "2. Meal Recording Flow"
2. Read: COMPLETE_FIREBASE_DATA_FLOW.md → "2. USER RECORDS A MEAL"
3. Reference: firebase_service.dart lines 209-301 + home_page.dart lines 208-257

### "I need to understand GPS updates"
1. Read: FIREBASE_DATA_FLOW_DIAGRAM.md → "3. GPS Location Update Flow"
2. Read: COMPLETE_FIREBASE_DATA_FLOW.md → "3. GPS LOCATION UPDATES"
3. Reference: location_service.dart lines 193-239

### "I need to understand survival signal"
1. Read: FIREBASE_DATA_FLOW_DIAGRAM.md → "4. Survival Signal Flow"
2. Read: COMPLETE_FIREBASE_DATA_FLOW.md → "4. SURVIVAL SIGNAL UPDATES"
3. Reference: firebase_service.dart lines 607-636 + activity_batcher.dart

### "I need to understand child app joining"
1. Read: FIREBASE_DATA_FLOW_DIAGRAM.md → "5. Child App Joins Flow"
2. Read: COMPLETE_FIREBASE_DATA_FLOW.md → "5. CHILD APP JOINS"
3. Reference: family_data_manager.dart lines 10-168

### "I need all Firestore operations list"
1. Read: FIREBASE_FLOW_SUMMARY.txt → "FIRESTORE OPERATIONS BREAKDOWN"
2. Read: COMPLETE_FIREBASE_DATA_FLOW.md → "CREATE, UPDATE, READ, DELETE OPERATIONS SUMMARY"

### "I need data structure reference"
1. Read: COMPLETE_FIREBASE_DATA_FLOW.md → "Field Names and Data Structure Reference"
2. Reference: families/{familyId}, connection_codes/{code}, meals/{date} JSON structures

---

## Key Statistics

- **Total Firestore Operations:** 19 unique operations
  - .set() CREATE: 3 locations
  - .update() UPDATE: 7 patterns
  - .get() READ: 6 locations
  - .snapshots() LISTEN: 2 streams
  - .delete() DELETE: 1 location

- **Collections:** 4 collections
  - connection_codes (public lookup)
  - families (main document)
  - families/{id}/meals (meal history)
  - families/{id}/recordings (audio/photo records)

- **Firebase Files:** 11 Dart files contain Firebase operations
  - firebase_service.dart (1126 lines, main service)
  - family_data_manager.dart (169 lines)
  - location_service.dart (316 lines)
  - home_page.dart (423 lines)
  - initial_setup_screen.dart (1443 lines)
  - Plus 6 other supporting services

---

## Critical Field Names Quick Reference

### families/{familyId} Root Document
```
settings.survivalSignalEnabled        [Boolean] Enable monitoring
settings.alertHours                   [Number] Hours before alert (default 12)
lastPhoneActivity                     [Timestamp] For survival signal detection
lastMeal.count                        [Number] 0-3 meals today
lastMeal.number                       [Number] Which meal (1/2/3)
location.latitude / longitude         [Number] GPS coordinates
location.timestamp                    [Timestamp] When location was updated
approved                              [Boolean|null] Child app approval status
alerts.survival / alerts.food         [Timestamp|null] Alert status
```

### connection_codes/{code}
```
familyId                              [String] Foreign key to families
elderlyName                           [String] Elderly person's name
```

### families/{familyId}/meals/{YYYY-MM-DD}
```
meals                                 [Array] Daily meal records
meals[].mealNumber                    [Number] 1/2/3
meals[].timestamp                     [String ISO8601] When meal was recorded
```

---

## User Actions to Firebase Operations Mapping

| User Action | Primary File | Firebase Operation | Path | Type |
|-------------|--------------|-------------------|------|------|
| "설정 완료" | initial_setup_screen.dart:58 | setupFamilyCode() | connection_codes/{code} + families/{id} | CREATE x2 |
| "설정 완료" | initial_setup_screen.dart:66 | updateFamilySettings() | families/{id} | UPDATE |
| "설정 완료" | initial_setup_screen.dart:137 | listenForApproval() | families/{id}.snapshots() | LISTEN |
| "설정 완료" timeout | initial_setup_screen.dart:309 | deleteFamilyCode() | families/{id} | DELETE |
| Record Meal | home_page.dart:226-229 | saveMealRecord() | families/{id}/meals/{date} + families/{id} | CREATE + UPDATE x2 |
| Location Update | location_service.dart:225 | forceLocationUpdate() | families/{id} | UPDATE |
| App Startup | home_page.dart:152 | forceActivityUpdate() | families/{id} | UPDATE |
| Child Approves | family_data_manager.dart:120 | setApprovalStatus() | families/{id} | UPDATE |
| Child Joins | family_data_manager.dart:14 | getFamilyInfo() | connection_codes/{id} + families/{id} | READ x2 |

---

## Code Snippet Locations

### Setup Complete Flow
- Initial setup screen: `/lib/screens/initial_setup_screen.dart` lines 44-129
- Firebase setup: `/lib/services/firebase_service.dart` lines 74-195
- Family data manager: `/lib/services/family/family_data_manager.dart` lines 81-168

### Meal Recording Flow
- UI handling: `/lib/screens/home_page.dart` lines 208-296
- Firebase save: `/lib/services/firebase_service.dart` lines 209-301
- Location force: `/lib/services/firebase_service.dart` lines 674-685

### GPS Location Flow
- Native handler: `/lib/services/location_service.dart` lines 193-239
- Firebase update: `/lib/services/firebase_service.dart` lines 638-672

### Survival Signal Flow
- Activity update: `/lib/services/firebase_service.dart` lines 607-636
- Batching logic: `/lib/services/activity/activity_batcher.dart` lines 10-35
- Display widget: `/lib/widgets/survival_signal_widget.dart` lines 17-176

### Child App Join Flow
- Data manager: `/lib/services/family/family_data_manager.dart` lines 10-168
- Main service: `/lib/services/firebase_service.dart` lines 197-442

---

## How to Update This Analysis

When you modify Firebase operations:

1. **If adding a new operation:**
   - Update COMPLETE_FIREBASE_DATA_FLOW.md with exact lines and data structure
   - Add flow diagram to FIREBASE_DATA_FLOW_DIAGRAM.md
   - Update operation count in FIREBASE_FLOW_SUMMARY.txt

2. **If modifying collection structure:**
   - Update all three JSON/field name sections across documents
   - Update data dependencies tree in diagram file

3. **If changing field names:**
   - Search all three documents for field name
   - Update field reference table in summary
   - Update data structure examples

---

## Related Security Documents

- Firestore security rules: See `firestore_secure_corrected.rules` (in git status)
- Firebase setup: `lib/firebase_options.dart`
- Auth manager: `lib/services/auth/firebase_auth_manager.dart`

---

## For Questions About Specific Operations

**"Where is operation X implemented?"**
- See: FIREBASE_FLOW_SUMMARY.txt → "FIRESTORE OPERATIONS BREAKDOWN"

**"What happens when user does Y?"**
- See: COMPLETE_FIREBASE_DATA_FLOW.md → Find user action section

**"How is data synchronized between apps?"**
- See: FIREBASE_DATA_FLOW_DIAGRAM.md → "9. Real-time Sync Points"

**"What are all the fields in collection Z?"**
- See: COMPLETE_FIREBASE_DATA_FLOW.md → "Field Names and Data Structure Reference"

**"How does throttling/batching work?"**
- See: FIREBASE_FLOW_SUMMARY.txt → "THROTTLING & BATCHING BEHAVIOR"

---

**Analysis Date:** 2025-10-18  
**App Version:** Thanks Everyday (식사하셨어요? / 고마워요)  
**Focus:** Parent app - Elderly health monitoring via Firebase Firestore
