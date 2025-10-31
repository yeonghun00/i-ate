import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/state/app_state.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/screens/settings_screen.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/food_tracking_service.dart';
import 'package:thanks_everyday/services/location_service.dart';
import 'package:thanks_everyday/services/permission_manager_service.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/widgets/home/app_header.dart';
import 'package:thanks_everyday/widgets/home/completion_screen.dart';
import 'package:thanks_everyday/widgets/home/meal_tracking_card.dart';
import 'package:thanks_everyday/widgets/permission_guide_widget.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AppLogger {
  final FirebaseService _firebaseService = FirebaseService();
  bool _shouldShowPermissionGuide = false;
  static bool _hasInitialUpdatesRun = false; // Session-based tracking

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    await Future.wait([
      _loadMealData(),
      _initializeServices(),
      _updateActivityInFirebase(),
      _checkPermissions(),
    ]);
    
    // Force immediate survival signal and GPS updates after initialization
    await _forceInitialUpdates();
  }

  Future<void> _checkPermissions() async {
    try {
      // Check if permission guide should be shown
      final shouldShow = await PermissionManagerService.shouldShowPermissionGuide();
      
      if (mounted) {
        setState(() {
          _shouldShowPermissionGuide = shouldShow;
        });
        
        if (shouldShow) {
          AppLogger.info('Permission guide will be shown due to missing permissions');
        }
      }
    } catch (e) {
      AppLogger.error('Failed to check permissions on home page load', error: e);
    }
  }

  Future<void> _loadMealData() async {
    try {
      final mealState = context.read<MealState>();
      
      // Load today's meal count from Firebase
      final count = await _firebaseService.getTodayMealCount();
      mealState.updateMealCount(count);
      
      // Load last meal time from local storage
      final lastMealTime = await FoodTrackingService.getLastFoodIntake();
      mealState.updateLastMealTime(lastMealTime);
      
      AppLogger.info('Meal data loaded - count: $count');
    } catch (e) {
      AppLogger.error('Failed to load meal data', error: e);
    }
  }

  Future<void> _initializeServices() async {
    try {
      AppLogger.info('Initializing home page services');
      
      await FoodTrackingService.initialize();
      
      // Other services are initialized in main.dart during app startup
      
      AppLogger.info('Home page services initialized successfully');
    } catch (e) {
      AppLogger.error('Service initialization failed', error: e);
    }
  }

  Future<void> _updateActivityInFirebase() async {
    try {
      // SECURITY FIX: Only update activity if survival signal is enabled
      final prefs = await SharedPreferences.getInstance();
      final survivalEnabled = prefs.getBool('survival_signal_enabled') ?? false;

      if (survivalEnabled) {
        await _firebaseService.updatePhoneActivity(forceImmediate: true);
        AppLogger.info('Phone activity updated in Firebase (survival signal enabled)');
      } else {
        AppLogger.info('Skipping phone activity update - survival signal is disabled');
      }
    } catch (e) {
      AppLogger.error('Failed to update phone activity', error: e);
    }
  }
  
  /// Force immediate survival signal and GPS updates when home page loads
  Future<void> _forceInitialUpdates() async {
    try {
      // Only run once per app session to avoid spam
      if (_hasInitialUpdatesRun) {
        AppLogger.info('Initial updates already completed this session - skipping');
        return;
      }

      AppLogger.info('🚀 STARTUP: Starting immediate GPS and survival signal updates');
      
      // Mark as started immediately to prevent multiple attempts
      _hasInitialUpdatesRun = true;
      
      // Run updates in parallel for faster completion
      final List<Future> updateFutures = [
        _forceImmediateSurvivalSignalUpdate(),
        _forceImmediateGPSUpdate(),
      ];
      
      // Wait for all updates to complete
      await Future.wait(updateFutures);
      
      // Brief user feedback that monitoring is active
      if (mounted) {
        _showMessage('모니터링이 활성화되었습니다');
      }
      
      AppLogger.info('🎯 STARTUP: All initial updates completed successfully');
      
    } catch (e) {
      AppLogger.error('❌ STARTUP: Failed to complete initial updates', error: e);
      // Reset flag on error so user can try again
      _hasInitialUpdatesRun = false;
      // Don't show error to user - this is background functionality
    }
  }

  /// Force immediate survival signal update with error handling
  Future<void> _forceImmediateSurvivalSignalUpdate() async {
    try {
      AppLogger.info('🔄 STARTUP: Forcing survival signal update...');
      
      // Force immediate activity update to establish baseline
      final success = await _firebaseService.forceActivityUpdate();
      
      if (success) {
        AppLogger.info('✅ STARTUP: Survival signal baseline established');
      } else {
        AppLogger.warning('⚠️ STARTUP: Survival signal update returned false');
      }
      
    } catch (e) {
      AppLogger.error('❌ STARTUP: Survival signal update failed', error: e);
      rethrow; // Let parent handle the error
    }
  }

  /// Force immediate GPS location update with enhanced error handling
  Future<void> _forceImmediateGPSUpdate() async {
    try {
      AppLogger.info('🔄 STARTUP: Forcing GPS location update...');
      
      // Step 1: Get fresh current location
      final position = await LocationService.getCurrentLocation();
      
      if (position != null) {
        AppLogger.info('📍 STARTUP: Got fresh GPS coordinates: ${position.latitude}, ${position.longitude}');
        
        // Step 2: Force immediate update to Firebase (bypass all throttling)
        final success = await _firebaseService.forceLocationUpdate(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        
        if (success) {
          AppLogger.info('✅ STARTUP: GPS location baseline established in Firebase');
        } else {
          AppLogger.warning('⚠️ STARTUP: GPS location update to Firebase returned false');
        }
      } else {
        AppLogger.warning('⚠️ STARTUP: Could not get current GPS location - may lack permissions');
        
        // Fallback: Try to use last known location if available
        final lastLocation = LocationService.getLastKnownLocation();
        if (lastLocation != null) {
          AppLogger.info('📍 STARTUP: Using last known location as fallback');
          await _firebaseService.forceLocationUpdate(
            latitude: lastLocation.latitude,
            longitude: lastLocation.longitude,
          );
        }
      }
      
    } catch (e) {
      AppLogger.error('❌ STARTUP: GPS location update failed', error: e);
      rethrow; // Let parent handle the error
    }
  }

  Future<void> _recordMeal() async {
    final mealState = context.read<MealState>();
    
    if (!mealState.canRecordMeal) {
      if (mealState.todayMealCount >= AppConstants.maxMealsPerDay) {
        _showMessage('오늘은 이미 3번의 식사를 모두 기록하셨습니다!');
      }
      return;
    }

    mealState.setSaving(true);
    HapticFeedback.mediumImpact();

    try {
      AppLogger.info('Starting meal recording');
      
      // Record meal locally and in Firebase
      final localSuccess = await FoodTrackingService.recordFoodIntake();
      final firebaseSuccess = await _firebaseService.saveMealRecord(
        timestamp: DateTime.now(),
        mealNumber: mealState.todayMealCount + 1,
      );

      if (localSuccess && firebaseSuccess) {
        // CRITICAL FIX: Force location update after meal recording to prevent GPS disappearing
        AppLogger.info('Forcing location update after meal recording');
        await _forceLocationUpdateAfterMeal();
        
        // Reload meal data after successful recording
        await _loadMealData();
        
        final newCount = context.read<MealState>().todayMealCount;
        if (newCount == AppConstants.maxMealsPerDay) {
          _showMessage('🎉 축하합니다! 오늘 3번의 식사를 모두 완료하셨습니다!');
        } else {
          _showMessage('식사 기록 완료! ($newCount/${AppConstants.maxMealsPerDay})');
        }
        
        AppLogger.info('Meal recorded successfully - total count: $newCount');
      } else {
        _showMessage('기록 실패. 다시 시도해주세요.');
        AppLogger.warning('Meal recording failed - local: $localSuccess, firebase: $firebaseSuccess');
      }
    } catch (e) {
      AppLogger.error('Meal recording failed', error: e);
      _showMessage('기록 중 오류가 발생했습니다.');
    } finally {
      mealState.setSaving(false);
    }
  }

  Future<void> _forceLocationUpdateAfterMeal() async {
    try {
      AppLogger.info('🔄 MEAL: Forcing GPS location update after meal recording...');
      
      // Get fresh current location
      final position = await LocationService.getCurrentLocation();
      
      if (position != null) {
        AppLogger.info('📍 MEAL: Got fresh GPS coordinates: ${position.latitude}, ${position.longitude}');
        
        // Force immediate location update to Firebase (bypass all throttling)
        final success = await _firebaseService.forceLocationUpdate(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        
        if (success) {
          AppLogger.info('✅ MEAL: GPS location updated in Firebase after meal recording');
        } else {
          AppLogger.warning('⚠️ MEAL: GPS location update to Firebase returned false');
        }
      } else {
        AppLogger.warning('⚠️ MEAL: Could not get current GPS location after meal recording');
        
        // Fallback: Try to use last known location if available
        final lastLocation = LocationService.getLastKnownLocation();
        if (lastLocation != null) {
          AppLogger.info('📍 MEAL: Using last known location as fallback after meal');
          await _firebaseService.forceLocationUpdate(
            latitude: lastLocation.latitude,
            longitude: lastLocation.longitude,
          );
        }
      }
    } catch (e) {
      AppLogger.error('❌ MEAL: Failed to force location update after meal', error: e);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: UIConstants.paddingMedium,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: message.contains('실패') || message.contains('오류')
            ? AppTheme.errorRed
            : AppTheme.primaryGreen,
        duration: UIConstants.snackBarDuration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UIConstants.radiusMedium),
        ),
      ),
    );
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          onDataDeleted: _onDataDeleted,
          onReset: () {},
        ),
      ),
    );
  }


  void _onDataDeleted() {
    // Navigate back to setup after data deletion
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomePage()),
      (route) => false,
    );
  }

  /// Test method to manually trigger immediate updates (for debugging)
  Future<void> _testImmediateUpdates() async {
    try {
      AppLogger.info('🧪 TEST: Manually triggering immediate updates...');
      
      // Reset session flag to allow testing
      _hasInitialUpdatesRun = false;
      
      // Trigger the updates
      await _forceInitialUpdates();
      
      AppLogger.info('🧪 TEST: Manual immediate updates completed');
      if (mounted) {
        _showMessage('테스트 업데이트 완료');
      }
    } catch (e) {
      AppLogger.error('🧪 TEST: Manual immediate updates failed', error: e);
      if (mounted) {
        _showMessage('테스트 업데이트 실패');
      }
    }
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
              Consumer<MealState>(
                builder: (context, mealState, child) {
                  return AppHeader(
                    todayMealCount: mealState.todayMealCount,
                    onSettingsTap: _navigateToSettings,
                  );
                },
              ),
              
              // Permission guide widget - shown at top when needed
              if (_shouldShowPermissionGuide)
                PermissionGuideWidget(
                  compactMode: true,
                  onAllPermissionsGranted: () async {
                    setState(() {
                      _shouldShowPermissionGuide = false;
                    });
                    _showMessage('모든 권한이 설정되었습니다! 안전 확인 기능이 활성화되었습니다.');

                    // Immediately update Firebase with current status
                    await _forceInitialUpdates();
                  },
                ),
              
              const SizedBox(height: UIConstants.paddingLarge),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(UIConstants.paddingLarge),
                  child: Consumer<MealState>(
                    builder: (context, mealState, child) {
                      if (mealState.todayMealCount == AppConstants.maxMealsPerDay) {
                        return const CompletionScreen();
                      } else {
                        return MealTrackingCard(
                          todayMealCount: mealState.todayMealCount,
                          isSaving: mealState.isSaving,
                          onRecordMeal: _recordMeal,
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}