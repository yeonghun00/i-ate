import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class NameMatchingService with AppLogger {
  double calculateNameMatchScore(String inputName, String storedName) {
    if (inputName.isEmpty || storedName.isEmpty) return 0.0;
    
    final normalizedInput = _normalizeName(inputName);
    final normalizedStored = _normalizeName(storedName);
    
    // Exact match
    if (normalizedInput == normalizedStored) return 1.0;
    
    // Check if one contains the other
    final containsScore = _calculateContainsScore(normalizedInput, normalizedStored);
    if (containsScore > 0) return containsScore;
    
    // Korean name pattern matching
    final koreanScore = _calculateKoreanPatternScore(normalizedInput, normalizedStored);
    if (koreanScore > 0.5) return koreanScore;
    
    // Fallback to Levenshtein distance
    return _calculateLevenshteinSimilarity(normalizedInput, normalizedStored);
  }

  String _normalizeName(String name) {
    return name.replaceAll(' ', '').toLowerCase();
  }

  double _calculateContainsScore(String input, String stored) {
    if (stored.contains(input) || input.contains(stored)) {
      final minLength = [input.length, stored.length].reduce((a, b) => a < b ? a : b);
      final maxLength = [input.length, stored.length].reduce((a, b) => a > b ? a : b);
      return minLength / maxLength;
    }
    return 0.0;
  }

  double _calculateKoreanPatternScore(String input, String stored) {
    final patterns = [
      _handleKoreanSurnamePatterns(input, stored),
      _handleHonorificPatterns(input, stored),
      _handleMiddleCharacterPatterns(input, stored),
    ];
    
    return patterns.reduce((a, b) => a > b ? a : b);
  }

  double _handleKoreanSurnamePatterns(String input, String stored) {
    final koreanSurnamePattern = RegExp(r'^[가-힣]');
    
    if (!koreanSurnamePattern.hasMatch(input) || !koreanSurnamePattern.hasMatch(stored)) {
      return 0.0;
    }
    
    // Extract first character (surname)
    final inputSurname = input.substring(0, 1);
    final storedSurname = stored.substring(0, 1);
    
    if (inputSurname != storedSurname) return 0.0;
    
    // Handle patterns with wildcards
    if (_containsWildcards(stored) || _containsWildcards(input)) {
      return 0.8;
    }
    
    return 0.0;
  }

  bool _containsWildcards(String name) {
    return AppConstants.koreanWildcards.any((wildcard) => name.contains(wildcard));
  }

  double _handleHonorificPatterns(String input, String stored) {
    String inputBase = input;
    String storedBase = stored;
    bool foundHonorific = false;
    
    // Remove honorifics to get base names
    for (final honorific in AppConstants.koreanHonorifics) {
      if (input.endsWith(honorific)) {
        inputBase = input.substring(0, input.length - honorific.length);
        foundHonorific = true;
      }
      if (stored.endsWith(honorific)) {
        storedBase = stored.substring(0, stored.length - honorific.length);
        foundHonorific = true;
      }
    }
    
    if (!foundHonorific) return 0.0;
    
    // Compare base names
    if (inputBase == storedBase) return 0.9;
    if (inputBase.isNotEmpty && storedBase.isNotEmpty) {
      return _calculateLevenshteinSimilarity(inputBase, storedBase) * 0.8;
    }
    
    return 0.0;
  }

  double _handleMiddleCharacterPatterns(String input, String stored) {
    if (input.length != stored.length || input.length < 2) return 0.0;
    
    int matchCount = 0;
    final totalChars = input.length;
    
    for (int i = 0; i < totalChars; i++) {
      final inputChar = input[i];
      final storedChar = stored[i];
      
      if (inputChar == storedChar) {
        matchCount++;
      } else if (_isWildcardCharacter(storedChar) || _isWildcardCharacter(inputChar)) {
        matchCount++;
      }
    }
    
    return matchCount / totalChars;
  }

  bool _isWildcardCharacter(String char) {
    return AppConstants.koreanWildcards.contains(char);
  }

  double _calculateLevenshteinSimilarity(String s1, String s2) {
    if (s1.isEmpty) return s2.isEmpty ? 1.0 : 0.0;
    if (s2.isEmpty) return 0.0;
    
    final matrix = List.generate(
      s1.length + 1,
      (_) => List.filled(s2.length + 1, 0),
    );
    
    // Initialize first row and column
    for (int i = 0; i <= s1.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= s2.length; j++) matrix[0][j] = j;
    
    // Fill matrix
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,      // deletion
          matrix[i][j - 1] + 1,      // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    
    final maxLength = [s1.length, s2.length].reduce((a, b) => a > b ? a : b);
    return 1.0 - (matrix[s1.length][s2.length] / maxLength);
  }
}