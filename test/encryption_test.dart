import 'package:flutter_test/flutter_test.dart';
import 'package:thanks_everyday/services/encryption_service.dart';

void main() {
  group('EncryptionService Tests (SECURE - Key Derivation)', () {
    test('Derive encryption key from familyId returns consistent 256-bit key', () {
      final familyId = 'f_test123';
      final key1 = EncryptionService.deriveEncryptionKey(familyId);
      final key2 = EncryptionService.deriveEncryptionKey(familyId);

      // Base64-encoded 32 bytes (256 bits) should be 44 characters
      expect(key1.length, greaterThanOrEqualTo(40));
      expect(key1.isNotEmpty, true);

      // Same familyId should produce same key (consistency test)
      expect(key1, equals(key2));

      print('✓ Derived encryption key: ${key1.substring(0, 20)}...');
      print('✓ Key derivation is consistent (same familyId → same key)');
    });

    test('Different familyIds produce different keys', () {
      final key1 = EncryptionService.deriveEncryptionKey('f_family1');
      final key2 = EncryptionService.deriveEncryptionKey('f_family2');

      // Different familyIds must produce different keys
      expect(key1, isNot(equals(key2)));
      print('✓ Different familyIds produce different keys (good security)');
    });

    test('Encrypt and decrypt location data successfully', () {
      // Derive key from familyId
      final familyId = 'f_test123';
      final key = EncryptionService.deriveEncryptionKey(familyId);

      // Test data
      const testLatitude = 37.7749;
      const testLongitude = -122.4194;
      const testAddress = 'San Francisco, CA';

      // Encrypt
      final encrypted = EncryptionService.encryptLocation(
        latitude: testLatitude,
        longitude: testLongitude,
        address: testAddress,
        base64Key: key,
      );

      expect(encrypted.containsKey('encrypted'), true);
      expect(encrypted.containsKey('iv'), true);
      expect(encrypted['encrypted']!.isNotEmpty, true);
      expect(encrypted['iv']!.isNotEmpty, true);

      print('✓ Encrypted data: ${encrypted['encrypted']!.substring(0, 20)}...');
      print('✓ IV: ${encrypted['iv']!.substring(0, 20)}...');

      // Decrypt
      final decrypted = EncryptionService.decryptLocation(
        encryptedData: encrypted['encrypted']!,
        ivBase64: encrypted['iv']!,
        base64Key: key,
      );

      expect(decrypted['latitude'], testLatitude);
      expect(decrypted['longitude'], testLongitude);
      expect(decrypted['address'], testAddress);

      print('✓ Decrypted latitude: ${decrypted['latitude']}');
      print('✓ Decrypted longitude: ${decrypted['longitude']}');
      print('✓ Decrypted address: ${decrypted['address']}');
    });

    test('Different IVs produce different encrypted outputs', () {
      final key = EncryptionService.deriveEncryptionKey('f_test123');

      const latitude = 37.7749;
      const longitude = -122.4194;

      // Encrypt same data twice
      final encrypted1 = EncryptionService.encryptLocation(
        latitude: latitude,
        longitude: longitude,
        address: '',
        base64Key: key,
      );

      final encrypted2 = EncryptionService.encryptLocation(
        latitude: latitude,
        longitude: longitude,
        address: '',
        base64Key: key,
      );

      // Different IVs should produce different encrypted data
      expect(encrypted1['iv'], isNot(equals(encrypted2['iv'])));
      expect(encrypted1['encrypted'], isNot(equals(encrypted2['encrypted'])));

      print('✓ Different IVs produce different ciphertext (good security)');
    });

    test('Wrong key cannot decrypt data', () {
      final key1 = EncryptionService.deriveEncryptionKey('f_family1');
      final key2 = EncryptionService.deriveEncryptionKey('f_family2');

      // Encrypt with key1
      final encrypted = EncryptionService.encryptLocation(
        latitude: 37.7749,
        longitude: -122.4194,
        address: '',
        base64Key: key1,
      );

      // Try to decrypt with key2 (should fail)
      expect(
        () => EncryptionService.decryptLocation(
          encryptedData: encrypted['encrypted']!,
          ivBase64: encrypted['iv']!,
          base64Key: key2,
        ),
        throwsException,
      );

      print('✓ Wrong key cannot decrypt (good security)');
    });
  });
}
