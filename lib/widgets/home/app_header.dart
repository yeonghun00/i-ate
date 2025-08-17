import 'package:flutter/material.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  final int todayMealCount;
  final VoidCallback onSettingsTap;
  const AppHeader({
    super.key,
    required this.todayMealCount,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildButtonRow(),
        const SizedBox(height: UIConstants.paddingLarge),
        _buildTitle(),
        const SizedBox(height: UIConstants.paddingMedium),
        _buildProgressIndicator(),
      ],
    );
  }

  Widget _buildButtonRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: UIConstants.paddingMedium,
        right: UIConstants.paddingMedium,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildSettingsButton(),
        ],
      ),
    );
  }


  Widget _buildSettingsButton() {
    return GestureDetector(
      onTap: onSettingsTap,
      child: Container(
        width: UIConstants.buttonHeight,
        height: UIConstants.buttonHeight,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(UIConstants.radiusCircular),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: UIConstants.shadowOpacity),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.settings,
          size: UIConstants.iconMedium,
          color: AppTheme.settingsIconColor,
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const SizedBox(height: UIConstants.paddingMedium),
        Text(
          AppConstants.appTitle,
          style: const TextStyle(
            fontSize: UIConstants.textDisplay,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(AppConstants.maxMealsPerDay, (index) {
        return Container(
          width: UIConstants.iconMedium,
          height: UIConstants.iconMedium,
          margin: const EdgeInsets.symmetric(horizontal: UIConstants.paddingSmall),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index < todayMealCount
                ? AppTheme.progressColor
                : AppTheme.borderLight,
          ),
          child: index < todayMealCount
              ? const Icon(
                  Icons.check,
                  size: UIConstants.paddingMedium,
                  color: Colors.white,
                )
              : null,
        );
      }),
    );
  }
}