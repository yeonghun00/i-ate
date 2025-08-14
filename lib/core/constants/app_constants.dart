class AppConstants {
  // App Information
  static const String appTitle = '식사하셨어요?';
  static const String appVersion = 'v1.0.0';
  static const String appDescription = '가족과 함께하는 식사 관리';

  // Meal Configuration
  static const int maxMealsPerDay = 3;
  static const int defaultAlertHours = 12;
  static const int defaultFoodAlertHours = 8;

  // Connection Code Configuration
  static const int connectionCodeLength = 4;
  static const int connectionCodeMin = 1000;
  static const int connectionCodeMax = 9999;

  // Retry Configuration
  static const int maxRetries = 3;
  static const int maxAuthRetries = 3;
  static const Duration retryDelay = Duration(milliseconds: 500);
  static const Duration authRetryDelay = Duration(seconds: 1);

  // Recovery Configuration
  static const double nameMatchThreshold = 0.7;
  static const double highConfidenceThreshold = 0.8;
  static const double autoDetectionThreshold = 0.3;
  static const int maxAutoDetectionCandidates = 5;
  static const int maxFamilySearchLimit = 50;
  static const int maxRecoveryDisplayLimit = 20;

  // Service Configuration
  static const Duration miuiDialogDelay = Duration(milliseconds: 500);
  static const Duration serviceInitializationDelay = Duration(seconds: 1);
  static const Duration settingsUpdateDelay = Duration(milliseconds: 300);

  // SharedPreferences Keys
  static const String keyFamilyId = 'family_id';
  static const String keyFamilyCode = 'family_code';
  static const String keyElderlyName = 'elderly_name';
  static const String keySetupComplete = 'setup_complete';
  static const String keySurvivalSignalEnabled = 'flutter.survival_signal_enabled';
  static const String keyLocationTrackingEnabled = 'flutter.location_tracking_enabled';
  static const String keyAlertHours = 'alert_hours';
  static const String keyFamilyContact = 'family_contact';
  static const String keyFoodAlertThreshold = 'food_alert_threshold';

  // Firebase Collections
  static const String collectionFamilies = 'families';
  static const String collectionMeals = 'meals';
  static const String collectionTest = 'test';

  // Korean Honorifics for Name Matching
  static const List<String> koreanHonorifics = [
    '할머니', '할아버지', '어머니', '아버지', '엄마', '아빠', '부모님'
  ];

  // Korean Name Wildcards
  static const List<String> koreanWildcards = ['○', '*', '◯'];

  // Error Messages
  static const String errorFirebaseInit = 'Firebase 초기화 실패';
  static const String errorConnectionNotFound = '연결 코드를 찾을 수 없습니다';
  static const String errorNameNotMatch = '이름이 일치하지 않습니다';
  static const String errorMultipleMatches = '여러 개의 일치하는 계정이 발견되었습니다';
  static const String errorRecoveryFailed = '복구 중 오류가 발생했습니다';
  static const String errorMealRecordFailed = '식사 기록 실패';
  static const String errorDataDeleteFailed = '데이터 삭제 중 오류가 발생했습니다';
  static const String errorSettingsSaveFailed = '설정 저장 중 오류가 발생했습니다';
}

class UIConstants {
  // Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 20.0;
  static const double radiusXLarge = 24.0;
  static const double radiusCircular = 22.0;

  // Icon Sizes
  static const double iconSmall = 16.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 60.0;

  // Button Sizes
  static const double buttonHeight = 44.0;
  static const double mealButtonSize = 160.0;
  static const double completionIconSize = 120.0;

  // Animation Durations
  static const Duration snackBarDuration = Duration(seconds: 3);
  static const Duration shortAnimation = Duration(milliseconds: 300);
  static const Duration mediumAnimation = Duration(seconds: 2);

  // Text Sizes
  static const double textSmall = 12.0;
  static const double textMedium = 14.0;
  static const double textLarge = 16.0;
  static const double textTitle = 20.0;
  static const double textHeader = 28.0;
  static const double textDisplay = 32.0;

  // Shadows
  static const double shadowBlur = 10.0;
  static const double shadowOffset = 5.0;
  static const double shadowOpacity = 0.1;
}