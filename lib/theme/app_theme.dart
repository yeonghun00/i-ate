import 'package:flutter/material.dart';

/// App theme with consistent colors used throughout the application
/// Features the current green theme with proper color organization
class AppTheme {
  // ==========================================================================
  // PRIMARY COLORS - Main Green Theme
  // ==========================================================================

  /// Primary green color - main brand color
  static const Color primaryGreen = Color(0xFF10B981);

  /// Dark green - for gradients and darker variants
  static const Color darkGreen = Color(0xFF059669);

  // ==========================================================================
  // ACCENT COLORS - For Visual Variety
  // ==========================================================================

  /// Blue accent - for secondary elements
  static const Color accentBlue = Color(0xFF3B82F6);

  /// Pink accent - for highlights
  static const Color accentPink = Color(0xFFEC4899);

  /// Purple accent - for special elements
  static const Color accentPurple = Color(0xFF8B5CF6);

  /// Orange accent - for warnings and alerts
  static const Color accentOrange = Color(0xFFF59E0B);

  // ==========================================================================
  // TEXT COLORS - For Content and UI Text
  // ==========================================================================

  /// Primary text color - darkest, highest contrast
  static const Color textPrimary = Color(0xFF1F2937);

  /// Secondary text color - slightly lighter
  static const Color textSecondary = Color(0xFF2E3440);

  /// Medium text color - for descriptions
  static const Color textMedium = Color(0xFF374151);

  /// Light text color - for subtle content
  static const Color textLight = Color(0xFF6B7280);

  /// Disabled text color - for inactive elements
  static const Color textDisabled = Color(0xFF9CA3AF);

  /// White text - for use on dark backgrounds
  static const Color textWhite = Colors.white;

  // ==========================================================================
  // BACKGROUND COLORS - For Layouts and Containers
  // ==========================================================================

  /// Main background color - light gray
  static const Color backgroundLight = Color(0xFFF8F9FA);

  /// Secondary background color - for gradients
  static const Color backgroundSecondary = Color(0xFFE9ECEF);

  /// Card background - very light gray
  static const Color backgroundCard = Color(0xFFF3F4F6);

  /// Pure white background
  static const Color backgroundWhite = Colors.white;

  // ==========================================================================
  // UI COLORS - For Borders, States, and Feedback
  // ==========================================================================

  /// Border color - light gray for dividers
  static const Color borderLight = Color(0xFFE5E7EB);

  /// Error/Warning color - red for alerts
  static const Color errorRed = Color(0xFFEF4444);

  /// Success color - same as primary green
  static const Color successGreen = primaryGreen;

  // ==========================================================================
  // GRADIENTS - For Visual Appeal
  // ==========================================================================

  /// Primary gradient - green theme
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, darkGreen],
  );

  /// Background gradient - light theme
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundLight, backgroundSecondary],
  );

  /// Success gradient - for completion states
  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, darkGreen],
  );

  // ==========================================================================
  // SEMANTIC COLORS - Context-Specific Usage
  // ==========================================================================

  /// Meal button color - primary green
  static const Color mealButtonColor = primaryGreen;

  /// Progress indicator color - primary green
  static const Color progressColor = primaryGreen;

  /// Settings icon color - light gray
  static const Color settingsIconColor = textLight;

  /// Completion celebration color - primary green
  static const Color celebrationColor = primaryGreen;

  // ==========================================================================
  // UTILITY METHODS
  // ==========================================================================

  /// Get meal progress color based on completion
  static Color getMealProgressColor(bool isCompleted) {
    return isCompleted ? primaryGreen : borderLight;
  }

  /// Get text color based on content type
  static Color getTextColor(String type) {
    switch (type) {
      case 'title':
        return textPrimary;
      case 'subtitle':
        return textSecondary;
      case 'body':
        return textMedium;
      case 'caption':
        return textLight;
      case 'disabled':
        return textDisabled;
      default:
        return textMedium;
    }
  }

  /// Create shadow with primary color
  static List<BoxShadow> get primaryShadow => [
    BoxShadow(
      color: primaryGreen.withOpacity(0.3),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  /// Create soft shadow for cards
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  /// Create subtle shadow for buttons
  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  // ==========================================================================
  // THEME DATA - Flutter Theme Configuration
  // ==========================================================================

  /// Main app theme with consistent colors
  static ThemeData get appTheme {
    return ThemeData(
      useMaterial3: true,
      primarySwatch: Colors.green,
      scaffoldBackgroundColor: backgroundLight,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'NotoSans',

      // Color scheme
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        brightness: Brightness.light,
        primary: primaryGreen,
        secondary: accentBlue,
        tertiary: accentPurple,
        error: errorRed,
        background: backgroundLight,
        surface: backgroundWhite,
        onPrimary: textWhite,
        onSecondary: textWhite,
        onSurface: textPrimary,
        onBackground: textPrimary,
      ),

      // App bar theme
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundLight,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: textWhite,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Card theme
      cardTheme: CardThemeData(
        color: backgroundWhite,
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryGreen, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

/// Extension for easy access to theme colors in widgets
extension AppThemeExtension on BuildContext {
  /// Quick access to primary color
  Color get primaryColor => AppTheme.primaryGreen;

  /// Quick access to background color
  Color get backgroundColor => AppTheme.backgroundLight;

  /// Quick access to text colors
  Color get textPrimary => AppTheme.textPrimary;
  Color get textSecondary => AppTheme.textSecondary;
  Color get textLight => AppTheme.textLight;

  /// Quick access to gradients
  LinearGradient get primaryGradient => AppTheme.primaryGradient;
  LinearGradient get backgroundGradient => AppTheme.backgroundGradient;
}
