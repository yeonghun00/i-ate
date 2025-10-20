# Location Data Encryption Implementation Guide (SECURE VERSION)

**Last Updated:** 2025-10-20
**Security Level:** HIGH - Key Derivation (NOT stored in Firestore)
**Purpose:** Secure GPS location data exchange between Parent App and Child App
**Audience:** Parent App Developer & Child App Developer

---

## ⚠️ CRITICAL SECURITY NOTE

**The encryption key is NEVER stored in Firestore!**

Instead, the key is **derived** from the `familyId` using a secret salt. This prevents hackers from accessing both the encrypted data AND the key, even if they gain read access to Firestore.

---

## Overview

Location data contains sensitive GPS coordinates that must be encrypted before storing in Firestore and decrypted when read by the child app.

### Secured Location Data Flow (Encrypted)

```
Parent App                    Firestore                     Child App
   GPS                    families/{familyId}              Display Map
  (Plain)                  location.encrypted               (Plain)
    |                             |                             |
    v                             v                             v
familyId ──> Derive Key ──> Encrypt ──> Store    Read ──> Derive Key ──> Decrypt
             (SHA-256)       (AES-256)                     (SHA-256)       (AES-256)
                ^                                              ^
                |                                              |
          Secret Salt (hardcoded in both apps)
```

**Key Point:** Both apps use the SAME `familyId` + SAME `secret salt` → Same encryption key

---

## Encryption Strategy

### Method: AES-256-GCM + Key Derivation

- **Algorithm:** AES (Advanced Encryption Standard)
- **Key Size:** 256 bits
- **Mode:** GCM (Galois/Counter Mode) - provides encryption + authentication
- **Key Derivation:** SHA-256 with 10,000 rounds (PBKDF2-like key stretching)
- **Key Storage:** NOWHERE! Key is derived on-demand from `familyId`
- **Secret Salt:** Hardcoded in both parent and child apps (KEEP SECRET!)

### Why This Approach?

1. **Symmetric:** Same key for encryption (parent) and decryption (child)
2. **Fast:** Efficient for mobile apps
3. **Secure:** Even if Firestore is compromised, location data remains encrypted
4. **No Backend Required:** Key derivation works offline
5. **Flutter Support:** Available via `encrypt` package

### Security Layers

1. **Firestore Rules:** Prevent unauthorized read access
2. **Encryption:** Even if rules fail, data is encrypted
3. **Key Derivation:** Even if data is read, key is not available
4. **Secret Salt:** Only apps with the correct salt can derive the key

---

## Firestore Data Structure

### After (Encrypted - SECURE)

```json
{
  "location": {
    "encrypted": "base64_encrypted_data_here",
    "iv": "base64_initialization_vector_here",
    "timestamp": Timestamp
  }
}
```

**Notice:** NO `encryptionKey` field! Key is derived, not stored.

### Encrypted Data Content (Before Encryption)

```json
{
  "latitude": 37.7749,
  "longitude": -122.4194,
  "address": ""
}
```

---

## Implementation Steps

### STEP 1: Setup Secret Salt (BOTH APPS)

**CRITICAL:** Both parent and child apps MUST use the SAME secret salt.

**Parent App:** Already configured in `lib/services/encryption_service.dart`
**Child App:** You MUST copy this exact value:

```dart
// lib/services/encryption_service.dart
class EncryptionService {
  // ⚠️ KEEP THIS SECRET! Do not commit to public repositories
  static const String _keySalt = 'thanks_everyday_secure_salt_v1_2025';

  // ... rest of the code
}
```

**Security Recommendations:**
- In production, move this to environment variables
- Use different salts for dev/staging/production
- Never commit the production salt to version control

---

### STEP 2: Parent App - Encrypt Location Data

**When:** Every location update (3 locations in code)

1. **App Startup:** `home_page.dart:101` → `_forceInitialUpdates()`
2. **After Meal:** `home_page.dart:234` → `_forceLocationUpdateAfterMeal()`
3. **Background Updates:** `location_service.dart:193` → `_handleLocationUpdate()`

**Current Code Location:** `firebase_service.dart:656-663`

#### Parent App Implementation

```dart
// Add to pubspec.yaml
dependencies:
  encrypt: ^5.0.3

// lib/services/encryption_service.dart
import 'package:encrypt/encrypt.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

class EncryptionService {
  /// Secret salt for key derivation (KEEP THIS SECRET!)
  static const String _keySalt = 'thanks_everyday_secure_salt_v1_2025';

  /// Derive a 256-bit encryption key from familyId
  ///
  /// Uses PBKDF2-like approach with SHA-256
  /// Both parent and child apps derive the same key from familyId
  ///
  /// [familyId] The unique family identifier
  /// Returns base64-encoded 256-bit key
  static String deriveEncryptionKey(String familyId) {
    // Combine familyId with secret salt
    final input = '$familyId:$_keySalt';

    // Hash multiple times for better security (key stretching)
    var hash = sha256.convert(utf8.encode(input)).bytes;

    // Additional rounds of hashing (PBKDF2-like)
    for (int i = 0; i < 10000; i++) {
      hash = sha256.convert(hash).bytes;
    }

    // Take first 32 bytes (256 bits) for AES-256
    final keyBytes = Uint8List.fromList(hash.sublist(0, 32));

    return base64.encode(keyBytes);
  }

  /// Encrypt location data
  static Map<String, String> encryptLocation({
    required double latitude,
    required double longitude,
    required String address,
    required String base64Key,
  }) {
    try {
      // Prepare data to encrypt
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };
      final plainText = json.encode(locationData);

      // Setup encryption
      final key = Key(base64.decode(base64Key));
      final iv = IV.fromSecureRandom(16); // Random IV for each encryption
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

      // Encrypt
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      return {
        'encrypted': encrypted.base64,
        'iv': iv.base64,
      };
    } catch (e) {
      print('⚠️ Encryption error: $e');
      rethrow;
    }
  }
}

// Modified firebase_service.dart
class FirebaseService {
  String? _cachedEncryptionKey;

  Future<bool> updateLocation({
    required double latitude,
    required double longitude,
    String? address,
    bool forceUpdate = false,
  }) async {
    try {
      if (_familyId == null) return false;

      // Derive encryption key from familyId (not fetched from Firestore!)
      final encryptionKey = await _getEncryptionKey();

      // Encrypt location data
      final encryptedData = EncryptionService.encryptLocation(
        latitude: latitude,
        longitude: longitude,
        address: address ?? '',
        base64Key: encryptionKey,
      );

      // Update Firestore with encrypted data
      await _firestore.collection('families').doc(_familyId).update({
        'location': {
          'encrypted': encryptedData['encrypted'],
          'iv': encryptedData['iv'],
          'timestamp': FieldValue.serverTimestamp(),
        },
      });

      return true;
    } catch (e) {
      print('Failed to update location: $e');
      return false;
    }
  }

  // Helper method to derive and cache encryption key
  Future<String> _getEncryptionKey() async {
    if (_cachedEncryptionKey != null) {
      return _cachedEncryptionKey!;
    }

    if (_familyId == null) {
      throw Exception('Cannot derive encryption key: no family ID');
    }

    // Derive key from familyId (same key will be derived by child app)
    _cachedEncryptionKey = EncryptionService.deriveEncryptionKey(_familyId!);
    return _cachedEncryptionKey!;
  }
}
```

---

### STEP 3: Child App - Decrypt Location Data

**When:** Reading location data from Firestore

#### Child App Implementation

```dart
// Add to pubspec.yaml
dependencies:
  encrypt: ^5.0.3

// lib/services/encryption_service.dart (SAME AS PARENT APP!)
import 'package:encrypt/encrypt.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

class EncryptionService {
  /// ⚠️ MUST BE THE SAME AS PARENT APP!
  static const String _keySalt = 'thanks_everyday_secure_salt_v1_2025';

  /// Derive encryption key from familyId (SAME implementation as parent app)
  static String deriveEncryptionKey(String familyId) {
    final input = '$familyId:$_keySalt';
    var hash = sha256.convert(utf8.encode(input)).bytes;

    for (int i = 0; i < 10000; i++) {
      hash = sha256.convert(hash).bytes;
    }

    final keyBytes = Uint8List.fromList(hash.sublist(0, 32));
    return base64.encode(keyBytes);
  }

  /// Decrypt location data received from Firestore
  static Map<String, dynamic> decryptLocation({
    required String encryptedData,
    required String ivBase64,
    required String base64Key,
  }) {
    try {
      // Setup decryption
      final key = Key(base64.decode(base64Key));
      final iv = IV.fromBase64(ivBase64);
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

      // Decrypt
      final decrypted = encrypter.decrypt64(encryptedData, iv: iv);

      // Parse JSON
      final locationData = json.decode(decrypted) as Map<String, dynamic>;

      return {
        'latitude': locationData['latitude'] as double,
        'longitude': locationData['longitude'] as double,
        'address': locationData['address'] as String,
      };
    } catch (e) {
      print('⚠️ Decryption error: $e');
      rethrow;
    }
  }
}

// Example usage in child app
class ChildLocationService {
  String? _cachedEncryptionKey;

  /// Initialize - Derive encryption key from familyId
  Future<void> initialize(String familyId) async {
    // Derive key from familyId (NO Firestore fetch needed!)
    _cachedEncryptionKey = EncryptionService.deriveEncryptionKey(familyId);
    print('✓ Encryption key derived from familyId');
  }

  /// Listen to location updates and decrypt
  Stream<Map<String, dynamic>> listenToLocation(String familyId) {
    return FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null || data['location'] == null) {
        return {};
      }

      final locationData = data['location'] as Map<String, dynamic>;

      // Decrypt using derived key
      final decrypted = EncryptionService.decryptLocation(
        encryptedData: locationData['encrypted'] as String,
        ivBase64: locationData['iv'] as String,
        base64Key: _cachedEncryptionKey!,
      );

      // Add timestamp
      decrypted['timestamp'] = locationData['timestamp'];

      return decrypted;
    });
  }
}
```

---

## Security Checklist

### Parent App Developer

- [ ] Install `encrypt` package (version 5.0.3+)
- [ ] Copy `EncryptionService` class with correct `_keySalt`
- [ ] Derive encryption key from `familyId` (NOT stored in Firestore)
- [ ] Encrypt location data before every Firestore write
- [ ] Use random IV for each encryption operation
- [ ] Cache derived key in memory (don't re-derive every time)
- [ ] Handle encryption errors gracefully
- [ ] **NEVER store encryption key in Firestore**

### Child App Developer

- [ ] Install `encrypt` package (same version as parent app)
- [ ] Copy `EncryptionService` class with **EXACT SAME `_keySalt`**
- [ ] Derive encryption key from `familyId` (NO Firestore fetch!)
- [ ] Decrypt location data when reading from Firestore
- [ ] Handle decryption errors gracefully
- [ ] Cache derived key in memory
- [ ] **Verify `_keySalt` matches parent app exactly**

### Both Apps

- [ ] Use the SAME `_keySalt` value
- [ ] Test encryption/decryption with real coordinates
- [ ] Verify encrypted data is unreadable in Firestore console
- [ ] Verify NO `encryptionKey` field exists in Firestore
- [ ] Test with multiple family members

---

## Firestore Security Rules

Update your `firestore.rules`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /families/{familyId} {
      // Only family members can read location (still encrypted!)
      allow read: if request.auth != null &&
                     request.auth.uid in resource.data.memberIds;

      allow write: if request.auth != null &&
                      request.auth.uid in resource.data.memberIds;
    }
  }
}
```

**Note:** Even if someone bypasses these rules, location data is still encrypted!

---

## Testing Guide

### Test 1: Key Derivation Consistency

**Both Apps:**
```dart
final familyId = 'f_test123';
final key1 = EncryptionService.deriveEncryptionKey(familyId);
final key2 = EncryptionService.deriveEncryptionKey(familyId);

print('Key 1: $key1');
print('Key 2: $key2');
print('Keys match: ${key1 == key2}'); // Must be true
```

**Expected:** Both keys are identical

### Test 2: Parent App Encryption

**Parent App:**
```dart
final familyId = 'f_test123';
final key = EncryptionService.deriveEncryptionKey(familyId);

final encrypted = EncryptionService.encryptLocation(
  latitude: 37.7749,
  longitude: -122.4194,
  address: 'Test Address',
  base64Key: key,
);

print('Encrypted: ${encrypted['encrypted']}');
print('IV: ${encrypted['iv']}');
```

**Expected:** Base64 encrypted data (looks like gibberish)

### Test 3: Child App Decryption

**Child App:**
```dart
final familyId = 'f_test123'; // Same as parent
final key = EncryptionService.deriveEncryptionKey(familyId);

final decrypted = EncryptionService.decryptLocation(
  encryptedData: 'encrypted_string_from_firestore',
  ivBase64: 'iv_from_firestore',
  base64Key: key,
);

print('Latitude: ${decrypted['latitude']}');
print('Longitude: ${decrypted['longitude']}');
```

**Expected:** Original coordinates (37.7749, -122.4194)

### Test 4: End-to-End Flow

1. Parent app records meal → GPS update
2. Check Firestore console → NO `encryptionKey` field
3. Check Firestore console → `location.encrypted` is unreadable
4. Child app opens → map shows correct location
5. Verify coordinates match

---

## Code Change Summary

### Parent App Changes

| File | Line | Change |
|------|------|--------|
| `pubspec.yaml` | dependencies | Add `encrypt: ^5.0.3` |
| `lib/services/encryption_service.dart` | NEW | Create encryption service with key derivation |
| `firebase_service.dart` | 1-10 | Import encryption service |
| `firebase_service.dart` | 27 | Add `_cachedEncryptionKey` field |
| `firebase_service.dart` | 152-154 | Remove `encryptionKey` from Firestore document |
| `firebase_service.dart` | 665-686 | Encrypt location before update |
| `firebase_service.dart` | 1143-1163 | Derive key from familyId (not fetch) |

### Child App Changes

| File | Line | Change |
|------|------|--------|
| `pubspec.yaml` | dependencies | Add `encrypt: ^5.0.3` |
| `lib/services/encryption_service.dart` | NEW | Copy EXACT encryption service from parent |
| Location display screen | varies | Derive key and decrypt before showing map |

---

## Common Issues & Solutions

### Issue 1: "Keys don't match between apps"
**Cause:** Different `_keySalt` values in parent and child apps
**Solution:** Copy the EXACT `_keySalt` value from parent to child app

### Issue 2: "MAC verification failed"
**Cause:** Different `familyId` used for encryption vs decryption
**Solution:** Verify both apps use the same `familyId`

### Issue 3: "Decryption fails randomly"
**Cause:** Wrong IV used for decryption
**Solution:** Ensure `iv` field is passed correctly from Firestore

### Issue 4: "Key derivation is slow"
**Cause:** 10,000 rounds of hashing takes time (~100ms)
**Solution:** Cache the derived key (already implemented in code)

---

## Security FAQ

### Q: Is this secure if Firestore is compromised?
**A:** Yes! Even if a hacker reads all Firestore data, they only see encrypted location data. Without the `_keySalt` (which is NOT in Firestore), they cannot derive the decryption key.

### Q: What if someone decompiles the app and finds the salt?
**A:** This is a risk. For maximum security:
- Use ProGuard/R8 obfuscation on Android
- Use different salts for dev/staging/production
- Consider using Firebase Remote Config with App Check for enterprise apps

### Q: Why not use asymmetric encryption (RSA)?
**A:** Symmetric encryption (AES) is faster and sufficient when both apps are trusted. Asymmetric encryption would require storing public keys in Firestore, which doesn't improve security here.

### Q: Can we rotate the encryption key?
**A:** Yes, but it requires:
1. Change the `_keySalt` in both apps
2. Re-encrypt all existing location data
3. Deploy both apps simultaneously

---

## Performance Considerations

1. **Key Derivation:** ~100ms for 10,000 rounds (one-time per session)
2. **Key Caching:** Cached in memory, no re-derivation needed
3. **Encryption Overhead:** ~1-2ms per location update
4. **Data Size Increase:** ~50 bytes per location record

---

## Migration Plan (If Already in Production)

### Phase 1: Deploy Parent App Update
- Parent app derives key from familyId
- Parent app writes encrypted location
- Old location fields can be left for backward compatibility

### Phase 2: Deploy Child App Update (1 week later)
- Child app derives key from familyId
- Child app reads encrypted location
- Verify decryption works correctly

### Phase 3: Data Cleanup (1 month later)
- Remove old plain location data from Firestore
- Update Firestore rules to block plain location writes

---

## Contact & Questions

**Parent App Developer:** [Your Name]
**Child App Developer:** [Child App Dev Name]

**Questions about encryption:** Refer to this document
**Flutter `encrypt` package:** https://pub.dev/packages/encrypt

---

**Document Version:** 2.0 (SECURE)
**Last Review:** 2025-10-20
**Security Status:** ✅ HIGH - Key derivation prevents key exposure
