# Production Security Checklist for MVP Launch

**App:** Thanks Everyday (Parent App)
**Last Updated:** 2025-10-20
**Status:** Ready for MVP with recommended changes

---

## 🔴 CRITICAL - Must Fix Before Production

### 1. Update Firestore Security Rules

**Current Risk:** ANY authenticated user can read/write ANY family's data

**Action Required:**
1. Replace current `firestore.rules` with `firestore_rules_PRODUCTION_READY.rules`
2. Deploy to Firebase Console
3. Test with multiple test accounts

**How to Deploy:**
```bash
# Copy production-ready rules
cp firestore_rules_PRODUCTION_READY.rules firestore.rules

# Deploy to Firebase
firebase deploy --only firestore:rules

# Or manually copy to Firebase Console:
# Firebase Console → Firestore Database → Rules → Copy/Paste
```

**Testing:**
- ✅ User A cannot read User B's family data
- ✅ User A cannot update User B's location
- ✅ User A cannot access User B's meal records
- ✅ Child app can still join via connection code

**Impact if not fixed:**
- Privacy breach: Anyone can see all families' encrypted location data
- Data integrity: Anyone can fake GPS, meals, survival signals
- Risk Level: **HIGH**

---

### 2. Secure the Secret Salt

**Current Risk:** Secret salt is hardcoded in source code

**Current Salt Location:**
```dart
// lib/services/encryption_service.dart:14
static const String _keySalt = 'thanks_everyday_secure_salt_v1_2025';
```

**Action Required:**

**Option 1: Change the Salt to Something Unique (MINIMUM)**
```dart
// Generate a random salt at: https://www.random.org/strings/
static const String _keySalt = 'XK9m2Pq7Zn4Lw8Rt5Yh3Vb6Nf1Gj0Sd';
```

**Option 2: Use Environment Variables (RECOMMENDED)**
```dart
// .env file (NOT committed to Git)
ENCRYPTION_SALT=your_super_secret_salt_here_xyz123

// lib/services/encryption_service.dart
static final String _keySalt = const String.fromEnvironment('ENCRYPTION_SALT');
```

**Option 3: Use Firebase Remote Config (BEST for Enterprise)**
- Store salt in Firebase Remote Config
- Use Firebase App Check to verify app authenticity
- Rotate salt periodically

**Testing:**
- ✅ Same salt in both parent and child apps
- ✅ Encryption/decryption works
- ✅ Salt is NOT in public GitHub repository

**Impact if not fixed:**
- If app is decompiled + Firestore rules are weak → All locations can be decrypted
- Risk Level: **MEDIUM** (mitigated by encryption + rules, but still important)

---

### 3. Enable ProGuard/R8 Obfuscation (Android)

**Current Risk:** Anyone can decompile APK and find secret salt

**Action Required:**

Edit `android/app/build.gradle`:
```gradle
android {
    buildTypes {
        release {
            // Enable code shrinking and obfuscation
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

Create `android/app/proguard-rules.pro`:
```
# Keep encryption service but obfuscate internals
-keep class com.example.thanks_everyday.services.EncryptionService { *; }
-keepclassmembers class com.example.thanks_everyday.services.EncryptionService {
    <methods>;
}

# Obfuscate all string constants (including salt)
-obfuscatecode

# Remove logging in production
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
```

**Testing:**
- ✅ Build release APK
- ✅ Decompile with jadx-gui (https://github.com/skylot/jadx)
- ✅ Verify salt is obfuscated (looks like gibberish)

**Impact if not fixed:**
- Secret salt can be easily found by anyone with APK
- Risk Level: **MEDIUM**

---

## 🟡 RECOMMENDED - Should Fix Before Launch

### 4. Rate Limiting for Connection Codes

**Current Risk:** Attacker can brute-force 4-digit connection codes

**Math:**
- 4-digit codes: 10,000 possible combinations (0000-9999)
- Without rate limiting: Attacker can try all codes in minutes

**Action Required:**

**Option 1: Add Expiration to Connection Codes (IMPLEMENTED)**
Already done in your code (2-minute timeout), but verify in Firestore rules:

```javascript
// Add to connection_codes rules
allow read: if request.auth != null &&
            // Only allow reading codes created in last 10 minutes
            request.time < resource.data.createdAt + duration.value(10, 'm');
```

**Option 2: Use Firebase App Check**
- Prevents automated scripts from calling Firestore
- Only allows requests from legitimate apps
- Setup: https://firebase.google.com/docs/app-check

**Option 3: Cloud Function Rate Limiting**
Create Cloud Function to validate connection code with rate limiting:
```javascript
// Cloud Function
exports.validateConnectionCode = functions.https.onCall(async (data, context) => {
    // Check if user has tried too many times (store in Firestore)
    const attempts = await getAttempts(context.auth.uid);
    if (attempts > 5) {
        throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts');
    }
    // Validate code...
});
```

**Testing:**
- ✅ Try 10+ wrong codes → Should be blocked
- ✅ Valid code should still work

**Impact if not fixed:**
- Attacker could potentially join random families
- Risk Level: **MEDIUM** (mitigated by 2-minute expiration)

---

### 5. Add Data Validation in Firestore Rules

**Current Risk:** Malformed data could be written to Firestore

**Action Required:**

Add validation to `firestore_rules_PRODUCTION_READY.rules`:

```javascript
// In families update rules, add:
allow update: if (
    isFamilyMember() &&
    isAllowedUpdate() &&
    // Validate location data structure
    (!('location' in request.resource.data) ||
     (request.resource.data.location.encrypted is string &&
      request.resource.data.location.iv is string &&
      request.resource.data.location.timestamp is timestamp)) &&
    // Validate memberIds is always a list
    request.resource.data.memberIds is list &&
    request.resource.data.memberIds.size() > 0
);
```

**Testing:**
- ✅ Try to write invalid location format → Should fail
- ✅ Try to set memberIds to null → Should fail
- ✅ Valid updates should work

**Impact if not fixed:**
- Data corruption, app crashes from unexpected data formats
- Risk Level: **LOW**

---

### 6. Remove Debug Code and Logs

**Current Risk:** Debug logs may expose sensitive data

**Action Required:**

Search and remove:
```bash
# Find all print statements
grep -r "print(" lib/

# Find all debug logs
grep -r "AppLogger.debug" lib/
```

In production build, ensure logs are disabled:
```dart
// lib/core/utils/app_logger.dart
class AppLogger {
  static const bool _isProduction = true; // Set to true for release

  static void debug(String message, {String? tag}) {
    if (!_isProduction) {
      print('[$tag] $message');
    }
  }
}
```

**Testing:**
- ✅ Build release APK
- ✅ Run logcat → No sensitive data in logs

**Impact if not fixed:**
- Location data, user IDs, family IDs leaked in logs
- Risk Level: **LOW-MEDIUM**

---

### 7. Set Up Firestore Backup

**Current Risk:** Data loss if Firestore is corrupted

**Action Required:**

Enable automated backups:
```bash
# Via Firebase CLI
gcloud firestore databases backup schedules create \
    --database='(default)' \
    --recurrence=daily \
    --retention=7d
```

Or via Firebase Console:
1. Firestore Database → Backups
2. Create Backup Schedule
3. Set to daily at 2 AM

**Testing:**
- ✅ Verify backup schedule is active
- ✅ Test restore from backup (use test project)

**Impact if not fixed:**
- Permanent data loss if Firestore fails
- Risk Level: **MEDIUM**

---

## ✅ ALREADY SECURE

### Good Security Practices Already Implemented:

1. ✅ **Location Encryption (AES-256-GCM)**
   - Even if Firestore is breached, location data is encrypted

2. ✅ **Key Derivation (not stored in Firestore)**
   - Prevents key exposure even with read access

3. ✅ **Firebase Authentication**
   - All requests require authenticated users

4. ✅ **Connection Code Timeout (2 minutes)**
   - Prevents stale codes from being used

5. ✅ **Member-based Access Control**
   - `memberIds` array tracks family members

6. ✅ **Separate Collections for Sensitive Data**
   - Users, families, subscriptions properly isolated

---

## 📊 Security Risk Assessment

### Current Risk Level: **MEDIUM-HIGH**

| Issue | Risk Level | Effort to Fix | Priority |
|-------|-----------|---------------|----------|
| Permissive Firestore Rules | 🔴 HIGH | Medium (2 hours) | **1 - CRITICAL** |
| Hardcoded Secret Salt | 🟡 MEDIUM | Low (30 min) | **2 - IMPORTANT** |
| No Code Obfuscation | 🟡 MEDIUM | Low (1 hour) | **3 - RECOMMENDED** |
| No Rate Limiting | 🟡 MEDIUM | High (4+ hours) | **4 - NICE TO HAVE** |
| No Data Validation | 🟢 LOW | Medium (2 hours) | **5 - OPTIONAL** |
| Debug Logs | 🟢 LOW | Low (30 min) | **6 - OPTIONAL** |
| No Backups | 🟡 MEDIUM | Low (30 min) | **7 - RECOMMENDED** |

### After Fixing Issues 1-3: **LOW RISK** ✅

---

## 🚀 MVP Launch Readiness

### Minimum Requirements for Production (1-2 days work):

✅ **YES - Can Launch After:**
1. Deploy `firestore_rules_PRODUCTION_READY.rules` (2 hours)
2. Change secret salt to unique value (30 minutes)
3. Enable ProGuard/R8 obfuscation (1 hour)
4. Remove debug logs from release builds (30 minutes)

**Total Time: ~4 hours of work**

### MVP Launch Security Checklist:

- [ ] Deploy production Firestore rules
- [ ] Change secret salt to unique value
- [ ] Copy same salt to child app
- [ ] Test encryption/decryption works
- [ ] Enable ProGuard/R8
- [ ] Build release APK and test
- [ ] Verify no sensitive logs in production
- [ ] Test with 2+ family members
- [ ] Test child app can join via connection code
- [ ] Test location updates are encrypted in Firestore console
- [ ] Set up Firestore backups

---

## 🔐 Additional Security Recommendations (Post-MVP)

### Phase 2 (After MVP Launch):

1. **Firebase App Check** (1 week)
   - Prevents API abuse from bots
   - Protects against scraping

2. **Rate Limiting with Cloud Functions** (1 week)
   - Limit connection code attempts
   - Limit location updates per minute

3. **Data Retention Policies** (3 days)
   - Auto-delete old location data (>30 days)
   - Reduce storage costs and privacy risk

4. **Anomaly Detection** (2 weeks)
   - Alert if unusual location patterns (teleportation)
   - Alert if excessive API calls

5. **Security Audit** (1 week)
   - Hire third-party security consultant
   - Penetration testing

---

## 📞 Emergency Response Plan

### If Security Breach Detected:

1. **Immediate Actions (within 1 hour):**
   - Disable Firestore write access (set all rules to `allow write: if false`)
   - Rotate secret salt (deploy new version)
   - Force all users to re-authenticate

2. **Investigation (within 24 hours):**
   - Check Firestore audit logs
   - Identify compromised accounts
   - Assess data exposure

3. **Remediation (within 72 hours):**
   - Reset affected family connections
   - Notify affected users
   - Deploy security patches

4. **Post-Mortem (within 1 week):**
   - Document breach details
   - Update security procedures
   - Implement additional safeguards

---

## ✅ Final Recommendation

### **YES - You Can Launch MVP** 🎉

**But MUST do first (4 hours):**
1. Deploy production Firestore rules
2. Change secret salt
3. Enable code obfuscation
4. Remove debug logs

**Current Security Status:**
- 🔴 Before fixes: **MEDIUM-HIGH RISK** (not ready)
- ✅ After fixes: **LOW RISK** (ready for MVP)

**Why it's safe to launch:**
1. ✅ Location data is encrypted (even if rules fail)
2. ✅ Encryption key not in Firestore (hacker can't decrypt)
3. ✅ After rule fixes, only family members can access data
4. ✅ Firebase Authentication prevents anonymous access
5. ✅ 2-minute connection code timeout prevents abuse

**MVP = Minimum Viable Product**
- Security is "good enough" for initial users
- You can improve incrementally
- Monitor for issues and respond quickly

---

**Document Version:** 1.0
**Last Review:** 2025-10-20
**Next Review:** After deploying production rules
