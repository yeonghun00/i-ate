import 'package:flutter/material.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

class MealTrackingCard extends StatelessWidget {
  final int todayMealCount;
  final bool isSaving;
  final VoidCallback onRecordMeal;

  const MealTrackingCard({
    super.key,
    required this.todayMealCount,
    required this.isSaving,
    required this.onRecordMeal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UIConstants.radiusXLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: UIConstants.shadowOpacity),
            blurRadius: UIConstants.shadowBlur * 2,
            offset: const Offset(0, UIConstants.shadowOffset + 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.paddingXLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTitle(),
            const SizedBox(height: UIConstants.paddingXLarge),
            _buildCurrentStatus(),
            const SizedBox(height: UIConstants.paddingXLarge + UIConstants.paddingSmall),
            _buildMealButton(),
            const SizedBox(height: UIConstants.radiusXLarge),
            _buildButtonText(),
            const SizedBox(height: UIConstants.paddingLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return const Text(
      '오늘 식사를 하셨나요?',
      style: TextStyle(
        fontSize: UIConstants.textHeader,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
        height: 1.3,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildCurrentStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UIConstants.radiusXLarge,
        vertical: UIConstants.paddingMedium,
      ),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(UIConstants.radiusLarge),
      ),
      child: Text(
        todayMealCount == 0
            ? '아직 오늘 식사 기록이 없어요'
            : '오늘 $todayMealCount번 식사하셨어요',
        style: const TextStyle(
          fontSize: UIConstants.textLarge + 2,
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMealButton() {
    final bool canRecord = todayMealCount < AppConstants.maxMealsPerDay;
    
    return Semantics(
      label: '식사 기록하기',
      button: true,
      child: GestureDetector(
        onTap: canRecord && !isSaving ? onRecordMeal : null,
        child: Container(
          width: UIConstants.mealButtonSize,
          height: UIConstants.mealButtonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _getButtonGradient(canRecord),
            boxShadow: _getButtonShadow(canRecord),
          ),
          child: _getButtonChild(canRecord),
        ),
      ),
    );
  }

  Widget _buildButtonText() {
    String text;
    Color color;
    
    if (isSaving) {
      text = '기록 중...';
      color = AppTheme.textLight;
    } else if (todayMealCount >= AppConstants.maxMealsPerDay) {
      text = '오늘 기록 완료';
      color = AppTheme.textDisabled;
    } else {
      text = '식사 했어요!';
      color = AppTheme.darkGreen;
    }
    
    return Text(
      text,
      style: TextStyle(
        fontSize: UIConstants.textLarge + 2,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      textAlign: TextAlign.center,
    );
  }

  LinearGradient _getButtonGradient(bool canRecord) {
    if (isSaving) {
      return const LinearGradient(
        colors: [AppTheme.textDisabled, AppTheme.textLight],
      );
    } else if (!canRecord) {
      return const LinearGradient(
        colors: [AppTheme.borderLight, Color(0xFFD1D5DB)],
      );
    } else {
      return AppTheme.successGradient;
    }
  }

  List<BoxShadow> _getButtonShadow(bool canRecord) {
    if (!isSaving && canRecord) {
      return [
        BoxShadow(
          color: AppTheme.primaryGreen.withValues(alpha: 0.3),
          blurRadius: UIConstants.shadowBlur * 2,
          offset: const Offset(0, UIConstants.shadowOffset + 3),
        ),
      ];
    }
    return [];
  }

  Widget _getButtonChild(bool canRecord) {
    if (isSaving) {
      return const SizedBox(
        width: UIConstants.paddingXLarge + UIConstants.paddingSmall,
        height: UIConstants.paddingXLarge + UIConstants.paddingSmall,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          strokeWidth: 4,
        ),
      );
    } else {
      return Icon(
        Icons.restaurant_rounded,
        size: UIConstants.iconLarge,
        color: canRecord ? Colors.white : AppTheme.textDisabled,
      );
    }
  }
}