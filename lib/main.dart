import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thanks_everyday/services/location_service.dart';
import 'package:thanks_everyday/services/food_tracking_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization failed: $e');
    // Don't continue if Firebase fails - this will cause issues throughout the app
    throw Exception('Firebase initialization failed: $e');
  }


  try {
    await ScreenMonitorService.initialize();
    print('ScreenMonitorService initialized successfully');
  } catch (e) {
    print('ScreenMonitorService initialization failed: $e');
  }

  try {
    await SmartUsageDetector.instance.initialize();
    print('SmartUsageDetector initialized successfully');
  } catch (e) {
    print('SmartUsageDetector initialization failed: $e');
  }

  try {
    await OverlayService.initialize();
    print('OverlayService initialized successfully');
  } catch (e) {
    print('OverlayService initialization failed: $e');
  }

  try {
    await MiuiBootHelper.initializeOnAppStart();
    print('MiuiBootHelper initialized successfully');
  } catch (e) {
    print('MiuiBootHelper initialization failed: $e');
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

      print(
        'Firebase setup: $isSetup, SharedPreferences setup: $setupComplete',
      );
      print('Has family code: $hasFamilyCode');

      // Auto-recovery with 8-digit codes removed - using name + connection code only

      // NEW: Auto-detection of existing accounts
      if (!isSetup && !setupComplete && !hasFamilyCode) {
        print('No existing data found, attempting auto-detection of existing accounts...');
        try {
          final candidates = await _firebaseService.autoDetectExistingAccounts();
          
          if (candidates.isNotEmpty) {
            print('Auto-detection found ${candidates.length} potential account matches');
            
            // Show auto-detection results to user for selection
            // This could be implemented as a dialog or dedicated screen
            // For now, we'll log the results and continue with normal setup
            for (final candidate in candidates) {
              print('  - ${candidate['elderlyName']} (${candidate['connectionCode']}) - Confidence: ${candidate['confidence']}');
            }
            
            // Optional: If there's a high-confidence match (>80%), we could prompt the user
            final highConfidenceMatch = candidates.where((c) => c['confidence'] >= 0.8).toList();
            if (highConfidenceMatch.isNotEmpty) {
              print('High-confidence account found: ${highConfidenceMatch.first['elderlyName']}');
              // Could show a dialog here asking user if this is their account
            }
          } else {
            print('Auto-detection found no potential matches');
          }
        } catch (e) {
          print('Auto-detection error: $e');
        }
      }

      // Be more lenient - if either Firebase OR SharedPreferences indicates setup is complete
      final actuallySetup = isSetup || setupComplete;
      
      print('  - Firebase service setup: $isSetup');
      print('  - SharedPreferences setup_complete: $setupComplete');
      print('  - Final decision: $actuallySetup');
      
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
      print('App initialization failed: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSetupComplete() async {
    print('🎉 _onSetupComplete called, navigating to main page');

    // Store completion state in SharedPreferences as backup
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      // Set default alert threshold
      await prefs.setInt('alert_hours', 12); // Default 12 hours
      
      // Update Firebase alert threshold
      try {
        await _firebaseService.updateAlertSettings(alertMinutes: 12 * 60); // 12 hours in minutes
      } catch (e) {
        print('Failed to update Firebase alert settings: $e');
      }
      
      
      // Initialize services based on user settings from initial setup
      await _initializeServicesAfterSetup();
      
    } catch (e) {
      print('Failed to store setup completion: $e');
    }
  }
  
  Future<void> _checkMiuiGuidance() async {
    try {
      print('🔍 Checking if MIUI guidance should be shown...');
      
      // Check for post-boot activation first
      final needsPostBoot = await MiuiBootHelper.needsPostBootActivation();
      if (needsPostBoot && mounted) {
        print('📱 Post-boot activation needed');
        await MiuiBootHelper.showPostBootActivationDialog(context);
        return;
      }
      
      // Check if MIUI setup guidance should be shown
      final shouldShow = await MiuiBootHelper.shouldShowMiuiGuidance();
      if (shouldShow && mounted) {
        print('🚨 MIUI setup guidance required');
        
        // Delay slightly to ensure the UI is ready
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          await MiuiBootHelper.showMiuiSetupDialog(context);
        }
      } else {
        print('✅ No MIUI guidance required');
      }
      
    } catch (e) {
      print('❌ Error checking MIUI guidance: $e');
    }
  }
  
  Future<void> _initializeServicesAfterSetup() async {
    try {
      await ScreenMonitorService.initialize();
      await LocationService.initialize();
      
      final prefs = await SharedPreferences.getInstance();
      final survivalEnabled = prefs.getBool('flutter.survival_signal_enabled') ?? false;
      final locationEnabled = prefs.getBool('flutter.location_tracking_enabled') ?? false;
      
      print('🔧 Initializing services after setup completion:');
      print('  - Survival signal: $survivalEnabled');
      print('  - Location tracking: $locationEnabled');
      
      if (survivalEnabled) {
        await ScreenMonitorService.enableSurvivalSignal();
        print('✅ Survival signal monitoring enabled');
        
        // Survival signal monitoring enabled - native service will handle background updates
        print('✅ Survival signal monitoring enabled after setup');
      }
      
      if (locationEnabled) {
        await LocationService.setLocationTrackingEnabled(true);
        print('✅ Location tracking enabled');
        
        // Force immediate location update after setup
        print('📍 Getting initial location after setup...');
        final position = await LocationService.getCurrentLocation();
        if (position != null) {
          print('✅ Initial location obtained: ${position.latitude}, ${position.longitude}');
        } else {
          print('❌ Failed to get initial location');
        }
      }
    } catch (e) {
      print('❌ Failed to initialize services after setup: $e');
    }
    
    // Check for MIUI guidance after setup completion
    await _checkMiuiGuidance();

    // Use a more robust approach to ensure state update happens
    if (mounted) {
      setState(() {
        _isSetup = true;
      });
      print('State updated: _isSetup = true');
    } else {
      print('Widget not mounted, scheduling state update for next frame');
      // Schedule the state update for the next frame when widget might be mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isSetup = true;
          });
          print('State updated via post-frame callback: _isSetup = true');
        } else {
          print('Widget still not mounted after post-frame callback');
          // Force rebuild the entire widget tree
          scheduleMicrotask(() {
            if (mounted) {
              setState(() {
                _isSetup = true;
              });
              print('State updated via microtask: _isSetup = true');
            }
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
      'AppWrapper build called - isLoading: $_isLoading, isSetup: $_isSetup',
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
      print('Returning InitialSetupScreen');
      return InitialSetupScreen(onSetupComplete: _onSetupComplete);
    }

    print('Returning HomePage');
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
  DateTime? _lastMealTime;
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
      await _firebaseService.updatePhoneActivity();
      print('App is active - phone activity updated in Firebase');
    } catch (e) {
      print('Failed to update phone activity: $e');
    }
  }

  Future<void> _loadTodayMealCount() async {
    try {
      final count = await _firebaseService.getTodayMealCount();
      setState(() {
        _todayMealCount = count;
      });
    } catch (e) {
      print('Failed to load todays meal count: $e');
    }
  }

  Future<void> _loadMealData() async {
    try {
      _lastMealTime = await FoodTrackingService.getLastFoodIntake();
      setState(() {});
    } catch (e) {
      print('식사 데이터 로드 실패: $e');
    }
  }

  Future<void> _initializeServices() async {
    try {
      print('🔧 Starting service initialization...');
      
      final prefs = await SharedPreferences.getInstance();
      final survivalEnabled = prefs.getBool('flutter.survival_signal_enabled') ?? false;
      final locationEnabled = prefs.getBool('flutter.location_tracking_enabled') ?? false;
      
      print('🔧 Initializing ScreenMonitorService...');
      await ScreenMonitorService.initialize();
      print('✅ ScreenMonitorService.initialize() completed');
      
      await LocationService.initialize();
      await FoodTrackingService.initialize();
      
      if (survivalEnabled) {
        print('🔧 Enabling survival signal...');
        await ScreenMonitorService.enableSurvivalSignal();
        print('✅ Survival signal enabled');
        
        print('🔄 Starting WorkManager for background updates...');
        await ScreenMonitorService.startMonitoring();
        print('✅ WorkManager scheduled for 15-minute updates');
        
        print('✅ Background phone activity monitoring started');
      } else {
        print('❌ Survival signal is disabled in preferences');
      }
      
      if (locationEnabled) {
        await LocationService.setLocationTrackingEnabled(true);
        print('✅ Location tracking started');
        
        print('📍 Getting immediate location...');
        final position = await LocationService.getCurrentLocation();
        if (position != null) {
          print('✅ Location updated: ${position.latitude}, ${position.longitude}');
        } else {
          print('❌ Failed to get location');
        }
      }
    } catch (e) {
      print('❌ Service initialization failed: $e');
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
      print('🔥 Testing Firebase Auth: ${FirebaseAuth.instance.currentUser?.uid}');
      print('🔥 Testing Firestore connection...');
      
      await FirebaseFirestore.instance.collection('test').doc('connectivity').set({
        'timestamp': FieldValue.serverTimestamp(),
        'test': true,
      });
      print('🔥 Firebase connection OK!');
      
      print('🍽️ Starting meal recording...');
      final success = await FoodTrackingService.recordFoodIntake();
      print('📱 Local food service result: $success');
      
      final firebaseSuccess = await _firebaseService.saveMealRecord(
        timestamp: DateTime.now(),
        mealNumber: _todayMealCount + 1,
      );
      print('🔥 Firebase service result: $firebaseSuccess');

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
      print('식사 기록 실패: $e');
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
