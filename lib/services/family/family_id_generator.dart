import 'dart:math';
import 'dart:typed_data';

class FamilyIdGenerator {
  static String generateFamilyId() {
    final random = Random.secure();
    
    // Generate 16 random bytes for UUID
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    
    // Set version (4) and variant bits according to RFC 4122
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant bits
    
    // Convert to UUID string format
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final uuid = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
    
    return 'family_$uuid';
  }

  static String generateConnectionCode() {
    return (1000 + Random().nextInt(9000)).toString();
  }
}