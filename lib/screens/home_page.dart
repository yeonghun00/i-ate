import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/state/app_state.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/screens/settings_screen.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/food_tracking_service.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/widgets/home/app_header.dart';
import 'package:thanks_everyday/widgets/home/completion_screen.dart';
import 'package:thanks_everyday/widgets/home/meal_tracking_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AppLogger {
  final FirebaseService _firebaseService = FirebaseService();

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
    ]);
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
      
      // Initialize other services based on settings
      // TODO: Add service initialization logic
      
      AppLogger.info('Home page services initialized successfully');
    } catch (e) {
      AppLogger.error('Service initialization failed', error: e);
    }
  }

  Future<void> _updateActivityInFirebase() async {
    try {
      await _firebaseService.updatePhoneActivity();
      AppLogger.info('Phone activity updated in Firebase');
    } catch (e) {
      AppLogger.error('Failed to update phone activity', error: e);
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