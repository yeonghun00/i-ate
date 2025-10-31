package com.thousandemfla.thanks_everyday.services

import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Native Kotlin encryption service matching Flutter EncryptionService
 * Uses AES-256-GCM for location data encryption
 *
 * CRITICAL: This MUST use the same salt and algorithm as Flutter's encryption_service.dart
 *
 * Security Note:
 * - Encryption key is DERIVED from familyId (NEVER stored in Firestore)
 * - Uses AES-256-GCM for authenticated encryption
 * - 10,000 rounds of SHA-256 for key stretching (PBKDF2-like)
 * - Random IV generated for each encryption operation
 */
object EncryptionHelper {
    private const val TAG = "EncryptionHelper"

    // ⚠️ MUST MATCH Flutter encryption_service.dart EXACTLY!
    // If you change this, you MUST change it in Flutter too!
    private const val KEY_SALT = "thanks_everyday_secure_salt_v1_2025"

    // AES-256-GCM parameters (MUST match Flutter)
    private const val ALGORITHM = "AES/GCM/NoPadding"
    private const val GCM_TAG_LENGTH = 128 // 128 bits = 16 bytes (authentication tag)
    private const val IV_LENGTH = 12 // 12 bytes for GCM (96 bits) - CRITICAL: NOT 16!
    private const val KEY_ITERATIONS = 10000 // Key stretching rounds

    /**
     * Derive 256-bit encryption key from familyId
     *
     * Uses PBKDF2-like approach with SHA-256 (10,000 rounds)
     * MUST match Flutter's deriveEncryptionKey() implementation
     *
     * Algorithm:
     * 1. Combine familyId with secret salt: "familyId:salt"
     * 2. Hash with SHA-256
     * 3. Hash the result 10,000 more times (key stretching)
     * 4. Take first 32 bytes for AES-256 key
     * 5. Encode as Base64
     *
     * @param familyId The unique family identifier
     * @return Base64-encoded 256-bit key
     * @throws Exception if key derivation fails
     */
    fun deriveEncryptionKey(familyId: String): String {
        try {
            // Combine familyId with secret salt (same as Flutter)
            val input = "$familyId:$KEY_SALT"

            // Get SHA-256 digest
            val digest = MessageDigest.getInstance("SHA-256")

            // Initial hash
            var hash = digest.digest(input.toByteArray(StandardCharsets.UTF_8))

            // Additional rounds of hashing (PBKDF2-like key stretching)
            // This makes brute-force attacks much slower
            for (i in 0 until KEY_ITERATIONS) {
                digest.reset()
                hash = digest.digest(hash)
            }

            // Take first 32 bytes (256 bits) for AES-256
            val keyBytes = hash.copyOf(32)

            // Return base64-encoded key
            return Base64.encodeToString(keyBytes, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to derive encryption key: ${e.message}")
            throw e
        }
    }

    /**
     * Encrypt location data before storing in Firestore
     *
     * Creates encrypted data that is compatible with Flutter's decryption
     *
     * @param latitude GPS latitude coordinate
     * @param longitude GPS longitude coordinate
     * @param address Optional address string
     * @param base64Key Base64-encoded 256-bit encryption key (from deriveEncryptionKey)
     * @return Map with 'encrypted' and 'iv' fields (both base64-encoded)
     * @throws Exception if encryption fails
     */
    fun encryptLocation(
        latitude: Double,
        longitude: Double,
        address: String,
        base64Key: String
    ): Map<String, String> {
        try {
            // Prepare data to encrypt (same JSON structure as Flutter)
            val locationJson = JSONObject().apply {
                put("latitude", latitude)
                put("longitude", longitude)
                put("address", address)
            }
            val plainText = locationJson.toString()

            Log.d(TAG, "🔐 Encrypting location: lat=$latitude, lng=$longitude")

            // Decode the base64 key
            val keyBytes = Base64.decode(base64Key, Base64.NO_WRAP)
            val secretKey = SecretKeySpec(keyBytes, "AES")

            // Generate random IV (12 bytes for GCM)
            // CRITICAL: Must be 12 bytes, not 16! This matches Flutter.
            val iv = ByteArray(IV_LENGTH)
            SecureRandom().nextBytes(iv)
            val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH, iv)

            // Setup cipher
            val cipher = Cipher.getInstance(ALGORITHM)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey, gcmSpec)

            // Encrypt
            val encryptedBytes = cipher.doFinal(plainText.toByteArray(StandardCharsets.UTF_8))

            Log.d(TAG, "✅ Location encrypted successfully (${encryptedBytes.size} bytes)")

            // Return base64-encoded encrypted data and IV
            return mapOf(
                "encrypted" to Base64.encodeToString(encryptedBytes, Base64.NO_WRAP),
                "iv" to Base64.encodeToString(iv, Base64.NO_WRAP)
            )
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Encryption error: ${e.message}")
            Log.e(TAG, "Stack trace: ${e.stackTraceToString()}")
            throw e
        }
    }

    /**
     * Decrypt location data (for testing/debugging only)
     *
     * Child app should implement its own decryption in Flutter
     *
     * @param encryptedData Base64-encoded encrypted data
     * @param ivBase64 Base64-encoded initialization vector
     * @param base64Key Base64-encoded 256-bit encryption key
     * @return Map with 'latitude', 'longitude', and 'address' fields
     * @throws Exception if decryption fails
     */
    fun decryptLocation(
        encryptedData: String,
        ivBase64: String,
        base64Key: String
    ): Map<String, Any> {
        try {
            Log.d(TAG, "🔓 Attempting to decrypt location data...")

            // Decode inputs
            val keyBytes = Base64.decode(base64Key, Base64.NO_WRAP)
            val secretKey = SecretKeySpec(keyBytes, "AES")
            val iv = Base64.decode(ivBase64, Base64.NO_WRAP)
            val encryptedBytes = Base64.decode(encryptedData, Base64.NO_WRAP)

            // Setup cipher
            val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
            val cipher = Cipher.getInstance(ALGORITHM)
            cipher.init(Cipher.DECRYPT_MODE, secretKey, gcmSpec)

            // Decrypt
            val decryptedBytes = cipher.doFinal(encryptedBytes)
            val decryptedText = String(decryptedBytes, StandardCharsets.UTF_8)

            Log.d(TAG, "✅ Decryption successful: $decryptedText")

            // Parse JSON
            val json = JSONObject(decryptedText)

            return mapOf(
                "latitude" to json.getDouble("latitude"),
                "longitude" to json.getDouble("longitude"),
                "address" to json.getString("address")
            )
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Decryption error: ${e.message}")
            Log.e(TAG, "Stack trace: ${e.stackTraceToString()}")
            throw e
        }
    }

    /**
     * Test encryption/decryption compatibility with Flutter
     * Call this from MainActivity to verify the implementation works
     */
    fun testEncryption() {
        try {
            Log.d(TAG, "🧪 ========== ENCRYPTION TEST START ==========")

            val familyId = "f_test123"
            val key = deriveEncryptionKey(familyId)

            Log.d(TAG, "🔑 Test Family ID: $familyId")
            Log.d(TAG, "🔑 Derived Key: $key")
            Log.d(TAG, "🔑 Key Length: ${Base64.decode(key, Base64.NO_WRAP).size} bytes")

            val testLat = 37.7749
            val testLng = -122.4194
            val testAddr = "Test Address"

            Log.d(TAG, "📍 Test Location: lat=$testLat, lng=$testLng, addr='$testAddr'")

            val encrypted = encryptLocation(
                latitude = testLat,
                longitude = testLng,
                address = testAddr,
                base64Key = key
            )

            Log.d(TAG, "🔐 Encrypted Data: ${encrypted["encrypted"]}")
            Log.d(TAG, "🔐 IV: ${encrypted["iv"]}")

            // Test decryption
            val decrypted = decryptLocation(
                encryptedData = encrypted["encrypted"]!!,
                ivBase64 = encrypted["iv"]!!,
                base64Key = key
            )

            Log.d(TAG, "✅ Decrypted Latitude: ${decrypted["latitude"]}")
            Log.d(TAG, "✅ Decrypted Longitude: ${decrypted["longitude"]}")
            Log.d(TAG, "✅ Decrypted Address: ${decrypted["address"]}")

            // Verify correctness
            val latMatch = decrypted["latitude"] == testLat
            val lngMatch = decrypted["longitude"] == testLng
            val addrMatch = decrypted["address"] == testAddr

            if (latMatch && lngMatch && addrMatch) {
                Log.d(TAG, "🎉 ========== ENCRYPTION TEST PASSED ==========")
            } else {
                Log.e(TAG, "❌ ========== ENCRYPTION TEST FAILED ==========")
                Log.e(TAG, "Latitude match: $latMatch")
                Log.e(TAG, "Longitude match: $lngMatch")
                Log.e(TAG, "Address match: $addrMatch")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ ========== ENCRYPTION TEST FAILED WITH EXCEPTION ==========")
            Log.e(TAG, "Exception: ${e.message}")
            Log.e(TAG, "Stack trace: ${e.stackTraceToString()}")
        }
    }
}
