import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thanks_everyday/services/location_service.dart';
import 'package:thanks_everyday/services/food_tracking_service.dart';
import 'package:firebase_core/firebase_core.dart';
// Firebase imports removed - now handled via AppLogger and services
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';
import 'package:thanks_everyday/services/smart_usage_detector.dart';
import 'package:thanks_everyday/services/overlay_service.dart';
import 'package:thanks_everyday/services/miui_boot_helper.dart';
import 'package:thanks_everyday/screens/initial_setup_screen.dart';
import 'package:thanks_everyday/screens/settings_screen.dart';
import 'package:thanks_everyday/firebase_options.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/core/errors/app_exceptions.dart';
import 'package:thanks_everyday/core/services/app_initialization_service.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppLogger.info('Firebase initialized successfully', tag: 'Main');
  } catch (e) {
    AppLogger.error('Firebase initialization failed: $e', tag: 'Main');
    // Don't continue if Firebase fails - this will cause issues throughout the app
    throw Exception('Firebase initialization failed: $e');
  }


  try {
    await ScreenMonitorService.initialize();
    AppLogger.info('ScreenMonitorService initialized successfully', tag: 'Main');
  } catch (e) {
    AppLogger.warning('ScreenMonitorService initialization failed: $e', tag: 'Main');
  }

  try {
    await SmartUsageDetector.instance.initialize();
    AppLogger.info('SmartUsageDetector initialized successfully', tag: 'Main');
  } catch (e) {
    AppLogger.warning('SmartUsageDetector initialization failed: $e', tag: 'Main');
  }

  try {
    await OverlayService.initialize();
    AppLogger.info('OverlayService initialized successfully', tag: 'Main');
  } catch (e) {
    AppLogger.warning('OverlayService initialization failed: $e', tag: 'Main');
  }

  try {
    await MiuiBootHelper.initializeOnAppStart();
    AppLogger.info('MiuiBootHelper initialized successfully', tag: 'Main');
  } catch (e) {
    AppLogger.warning('MiuiBootHelper initialization failed: $e', tag: 'Main');
  }

  runApp(const ThanksEverydayApp());
}

class ThanksEverydayApp extends StatelessWidget {
  const ThanksEverydayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '식사하셨어요?',
      theme: AppTheme.appTheme,
      home: const AppWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  final FirebaseService _firebaseService = FirebaseService();
  final AppInitializationService _initService = AppInitializationService();
  bool _isLoading = true;
  bool _isSetup = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final isSetup = await _firebaseService.initialize();

      // Also check SharedPreferences for setup completion
      final prefs = await SharedPreferences.getInstance();
      final setupComplete = prefs.getBool('setup_complete') ?? false;
      
      // Check if we have family code stored locally
      final hasFamilyCode = prefs.getString('family_code') != null;

      AppLogger.info(
        'Firebase setup: $isSetup, SharedPreferences setup: $setupComplete',
        tag: 'AppWrapper',
      );
      AppLogger.info('Has family code: $hasFamilyCode', tag: 'AppWrapper');

      // Auto-recovery with 8-digit codes removed - using name + connection code only

      // NEW: Auto-detection of existing accounts
      if (!isSetup && !setupComplete && !hasFamilyCode) {
        AppLogger.info('No existing data found, attempting auto-detection of existing accounts...', tag: 'AppWrapper');
        try {
          final candidates = await _firebaseService.autoDetectExistingAccounts();
          
          if (candidates.isNotEmpty) {
            AppLogger.info('Auto-detection found ${candidates.length} potential account matches', tag: 'AppWrapper');
            
            // Show auto-detection results to user for selection
            // This could be implemented as a dialog or dedicated screen
            // For now, we'll log the results and continue with normal setup
            for (final candidate in candidates) {
              AppLogger.debug('  - ${candidate['elderlyName']} (${candidate['connectionCode']}) - Confidence: ${candidate['confidence']}', tag: 'AppWrapper');
            }
            
            // Optional: If there's a high-confidence match (>80%), we could prompt the user
            final highConfidenceMatch = candidates.where((c) => c['confidence'] >= 0.8).toList();
            if (highConfidenceMatch.isNotEmpty) {
              AppLogger.info('High-confidence account found: ${highConfidenceMatch.first['elderlyName']}', tag: 'AppWrapper');
              // Could show a dialog here asking user if this is their account
            }
          } else {
            AppLogger.info('Auto-detection found no potential matches', tag: 'AppWrapper');
          }
        } catch (e) {
          AppLogger.warning('Auto-detection error: $e', tag: 'AppWrapper');
        }
      }

      // Be more lenient - if either Firebase OR SharedPreferences indicates setup is complete
      final actuallySetup = isSetup || setupComplete;
      
      AppLogger.debug('  - Firebase service setup: $isSetup', tag: 'AppWrapper');
      AppLogger.debug('  - SharedPreferences setup_complete: $setupComplete', tag: 'AppWrapper');
      AppLogger.info('  - Final decision: $actuallySetup', tag: 'AppWrapper');
      
      setState(() {
        _isSetup = actuallySetup;
        _isLoading = false;
      });
      
      // Check for MIUI guidance even for existing users
      if (actuallySetup) {
        // Delay to allow UI to render first
        Future.delayed(const Duration(seconds: 1), () {
          _checkMiuiGuidance();
        });
      }
    } catch (e) {
      AppLogger.error('App initialization failed: $e', tag: 'AppWrapper');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSetupComplete() async {
    AppLogger.info('🎉 _onSetupComplete called, navigating to main page', tag: 'AppWrapper');

    // Store completion state in SharedPreferences as backup
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      // Note: alert_hours is now stored in Firebase only, not SharedPreferences
      
      
      // CRITICAL FIX: Use AppInitializationService to properly reload family data
      AppLogger.info('Calling AppInitializationService.initializeServicesAfterSetup() to reload family data', tag: 'AppWrapper');
      final result = await _initService.initializeServicesAfterSetup();
      
      result.fold(
        onSuccess: (_) {
          AppLogger.info('AppInitializationService completed successfully - family data reloaded', tag: 'AppWrapper');
          _completeSetupWithStateUpdate();
        },
        onFailure: (error) {
          AppLogger.error('AppInitializationService failed: ${error.message}', tag: 'AppWrapper');
          // Still proceed with state update even if service init failed
          _completeSetupWithStateUpdate();
        },
      );
      
    } catch (e) {
      AppLogger.error('Failed to store setup completion: $e', tag: 'AppWrapper');
    }
  }
  
  Future<void> _checkMiuiGuidance() async {
    try {
      AppLogger.info('🔍 Checking if MIUI guidance should be shown...', tag: 'AppWrapper');
      
      // Check for post-boot activation first
      final needsPostBoot = await MiuiBootHelper.needsPostBootActivation();
      if (needsPostBoot && mounted) {
        AppLogger.info('📱 Post-boot activation needed', tag: 'AppWrapper');
        await MiuiBootHelper.showPostBootActivationDialog(context);
        return;
      }
      
      // Check if MIUI setup guidance should be shown
      final shouldShow = await MiuiBootHelper.shouldShowMiuiGuidance();
      if (shouldShow && mounted) {
        AppLogger.info('🚨 MIUI setup guidance required', tag: 'AppWrapper');
        
        // Delay slightly to ensure the UI is ready
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          await MiuiBootHelper.showMiuiSetupDialog(context);
        }
      } else {
        AppLogger.info('✅ No MIUI guidance required', tag: 'AppWrapper');
      }
      
    } catch (e) {
      AppLogger.error('❌ Error checking MIUI guidance: $e', tag: 'AppWrapper');
    }
  }

  void _completeSetupWithStateUpdate() {
    // Handle MIUI guidance and state update after proper service initialization
    Future.delayed(const Duration(milliseconds: 100), () async {
      await _checkMiuiGuidance();

      // Use a more robust approach to ensure state update happens
      if (mounted) {
        setState(() {
          _isSetup = true;
        });
        AppLogger.info('State updated: _isSetup = true', tag: 'AppWrapper');
      } else {
        AppLogger.warning('Widget not mounted, scheduling state update for next frame', tag: 'AppWrapper');
        // Schedule the state update for the next frame when widget might be mounted
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isSetup = true;
            });
            AppLogger.info('State updated via post-frame callback: _isSetup = true', tag: 'AppWrapper');
          } else {
            AppLogger.warning('Widget still not mounted after post-frame callback', tag: 'AppWrapper');
            // Force rebuild the entire widget tree
            scheduleMicrotask(() {
              if (mounted) {
                setState(() {
                  _isSetup = true;
                });
                AppLogger.info('State updated via microtask: _isSetup = true', tag: 'AppWrapper');
              }
            });
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug(
      'AppWrapper build called - isLoading: $_isLoading, isSetup: $_isSetup',
      tag: 'AppWrapper',
    );

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
          ),
        ),
      );
    }

    if (!_isSetup) {
      AppLogger.debug('Returning InitialSetupScreen', tag: 'AppWrapper');
      return InitialSetupScreen(onSetupComplete: _onSetupComplete);
    }

    AppLogger.debug('Returning HomePage', tag: 'AppWrapper');
    return const HomePage();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseService _firebaseService = FirebaseService();
  int _todayMealCount = 0;
  // _lastMealTime removed - not used in current implementation
  final int _maxMealsPerDay = 3;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTodayMealCount();
    _loadMealData();
    _initializeServices();
    _updateActivityInFirebase();
  }

  Future<void> _updateActivityInFirebase() async {
    try {
      // CRITICAL FIX: Force immediate activity update when app opens
      await _firebaseService.updatePhoneActivity(forceImmediate: true);
      AppLogger.info('App is active - phone activity FORCE updated in Firebase', tag: 'HomePage');
    } catch (e) {
      AppLogger.warning('Failed to update phone activity: $e', tag: 'HomePage');
    }
  }

  Future<void> _loadTodayMealCount() async {
    try {
      final count = await _firebaseService.getTodayMealCount();
      setState(() {
        _todayMealCount = count;
      });
    } catch (e) {
      AppLogger.warning('Failed to load todays meal count: $e', tag: 'HomePage');
    }
  }

  Future<void> _loadMealData() async {
    // Meal timing data is now handled directly in the UI components
  }

  Future<void> _initializeServices() async {
    try {
      AppLogger.info('🔧 HomePage service initialization - family data already loaded by AppInitializationService', tag: 'HomePage');
      
      // Family data should already be loaded by AppInitializationService.initializeServicesAfterSetup()
      // This method now just handles immediate updates and service checks
      
      if (!_firebaseService.isSetup) {
        AppLogger.error('❌ CRITICAL: FirebaseService family data not loaded in HomePage', tag: 'HomePage');
        AppLogger.error('  - Family ID: ${_firebaseService.familyId}', tag: 'HomePage');
        AppLogger.error('  - Family Code: ${_firebaseService.familyCode}', tag: 'HomePage');
        
        // Try to reload family data as fallback
        AppLogger.info('🔄 Attempting to reload family data as fallback...', tag: 'HomePage');
        final reloadSuccess = await _firebaseService.reloadFamilyData();
        
        if (!reloadSuccess) {
          AppLogger.error('❌ Failed to reload family data in HomePage - services will not work', tag: 'HomePage');
          return;
        }
      }
      
      AppLogger.info('✅ Firebase family data verified in HomePage:', tag: 'HomePage');
      AppLogger.info('  - Family ID: ${_firebaseService.familyId}', tag: 'HomePage');
      AppLogger.info('  - Family Code: ${_firebaseService.familyCode}', tag: 'HomePage');
      AppLogger.info('  - Elderly Name: ${_firebaseService.elderlyName}', tag: 'HomePage');
      
      // Services should already be initialized by AppInitializationService
      // Just force immediate updates for current session
      
      // CRITICAL FIX: Force immediate Firebase activity sync
      AppLogger.info('📱 Forcing immediate Firebase activity sync...', tag: 'HomePage');
      await _firebaseService.updatePhoneActivity(forceImmediate: true);
      AppLogger.info('✅ Immediate Firebase activity sync completed', tag: 'HomePage');
      
      // Try to update location if location service was enabled
      final prefs = await SharedPreferences.getInstance();
      final locationEnabled = prefs.getBool('flutter.location_tracking_enabled') ?? false;
      
      if (locationEnabled) {
        AppLogger.info('📍 Getting immediate location and syncing to Firebase...', tag: 'HomePage');
        final position = await LocationService.getCurrentLocation();
        if (position != null) {
          AppLogger.info('✅ Location obtained: ${position.latitude}, ${position.longitude}', tag: 'HomePage');
          
          try {
            await _firebaseService.updateLocation(
              latitude: position.latitude,
              longitude: position.longitude,
              forceUpdate: true,
            );
            AppLogger.info('✅ Location synced to Firebase immediately', tag: 'HomePage');
          } catch (e) {
            AppLogger.error('❌ Failed to sync location to Firebase: $e', tag: 'HomePage');
          }
        } else {
          AppLogger.warning('❌ Failed to get location', tag: 'HomePage');
        }
      }
      
    } catch (e) {
      AppLogger.error('❌ HomePage service initialization failed: $e', tag: 'HomePage');
    }
  }

  Future<void> _recordMeal() async {
    if (_todayMealCount >= _maxMealsPerDay) {
      _showMessage('오늘은 이미 3번의 식사를 모두 기록하셨습니다!');
      return;
    }

    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    HapticFeedback.mediumImpact();

    try {
      // Firebase connection is already established and verified during app initialization
      
      AppLogger.info('🍽️ Starting meal recording...', tag: 'HomePage');
      final success = await FoodTrackingService.recordFoodIntake();
      AppLogger.info('📱 Local food service result: $success', tag: 'HomePage');
      
      final firebaseSuccess = await _firebaseService.saveMealRecord(
        timestamp: DateTime.now(),
        mealNumber: _todayMealCount + 1,
      );
      AppLogger.info('🔥 Firebase service result: $firebaseSuccess', tag: 'HomePage');

      if (success && firebaseSuccess) {
        await _loadTodayMealCount();
        await _loadMealData();

        if (_todayMealCount == _maxMealsPerDay) {
          _showMessage('🎉 축하합니다! 오늘 3번의 식사를 모두 완료하셨습니다!');
        } else {
          _showMessage('식사 기록 완료! ($_todayMealCount/$_maxMealsPerDay)');
        }
      } else {
        _showMessage('기록 실패. 다시 시도해주세요.');
      }
    } catch (e) {
      AppLogger.error('식사 기록 실패: $e', tag: 'HomePage');
      _showMessage('기록 중 오류가 발생했습니다.');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          backgroundColor: message.contains('실패') || message.contains('오류')
              ? AppTheme.errorRed
              : AppTheme.primaryGreen,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: Column(
            children: [
              // Settings button row
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 16, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Settings Button
                    GestureDetector(
                      onTap: () => _navigateToSettings(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.settings,
                          size: 24,
                          color: AppTheme.settingsIconColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      Expanded(
                        child: _todayMealCount == _maxMealsPerDay
                            ? _buildCompletionScreen()
                            : _buildMainContent(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          onDataDeleted: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const AppWrapper()),
              (route) => false,
            );
          },
          onReset: () {},
        ),
      ),
    );
  }

  Widget _buildCompletionScreen() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '🎉 축하합니다! 🎉',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.celebrationColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '오늘의 식사\n3번을 모두 완료하셨습니다!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.successGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '정말 잘하셨어요!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.progressColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 16),
        const Text(
          '식사하셨어요?',
          style: TextStyle(
            fontSize: 32.0,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index < _todayMealCount
                    ? AppTheme.progressColor
                    : AppTheme.borderLight,
              ),
              child: index < _todayMealCount
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return _buildMealCard();
  }

  Widget _buildMealCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '오늘 식사를 하셨나요?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _todayMealCount == 0
                    ? '아직 오늘 식사 기록이 없어요'
                    : '오늘 $_todayMealCount번 식사하셨어요',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            Semantics(
              label: '식사 기록하기',
              button: true,
              child: GestureDetector(
                onTap: _recordMeal,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _isSaving
                        ? const LinearGradient(
                            colors: [AppTheme.textDisabled, AppTheme.textLight],
                          )
                        : _todayMealCount >= _maxMealsPerDay
                        ? const LinearGradient(
                            colors: [AppTheme.borderLight, Color(0xFFD1D5DB)],
                          )
                        : AppTheme.successGradient,
                    boxShadow: [
                      if (!_isSaving && _todayMealCount < _maxMealsPerDay)
                        BoxShadow(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                    ],
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            strokeWidth: 4,
                          ),
                        )
                      : Icon(
                          Icons.restaurant_rounded,
                          size: 60,
                          color: _todayMealCount >= _maxMealsPerDay
                              ? AppTheme.textDisabled
                              : Colors.white,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isSaving
                  ? '기록 중...'
                  : _todayMealCount >= _maxMealsPerDay
                  ? '오늘 기록 완료'
                  : '식사 했어요!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _isSaving
                    ? AppTheme.textLight
                    : _todayMealCount >= _maxMealsPerDay
                    ? AppTheme.textDisabled
                    : AppTheme.darkGreen,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
