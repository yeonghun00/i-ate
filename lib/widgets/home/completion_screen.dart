import 'package:flutter/material.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

class CompletionScreen extends StatelessWidget {
  const CompletionScreen({super.key});

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
            _buildCelebrationTitle(),
            const SizedBox(height: UIConstants.paddingMedium),
            _buildCompletionMessage(),
            const SizedBox(height: UIConstants.paddingXLarge),
            _buildSuccessIcon(),
            const SizedBox(height: UIConstants.paddingXLarge),
            _buildEncouragementMessage(),
          ],
        ),
      ),
    );
  }

  Widget _buildCelebrationTitle() {
    return const Text(
      '🎉 축하합니다! 🎉',
      style: TextStyle(
        fontSize: UIConstants.textHeader,
        fontWeight: FontWeight.bold,
        color: AppTheme.celebrationColor,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildCompletionMessage() {
    return const Text(
      '오늘의 식사\n3번을 모두 완료하셨습니다!',
      style: TextStyle(
        fontSize: UIConstants.textTitle,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
        height: 1.4,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSuccessIcon() {
    return Container(
      width: UIConstants.completionIconSize,
      height: UIConstants.completionIconSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.successGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withValues(alpha: 0.3),
            blurRadius: UIConstants.shadowBlur * 2,
            offset: const Offset(0, UIConstants.shadowOffset + 3),
          ),
        ],
      ),
      child: const Icon(
        Icons.check_circle_rounded,
        size: UIConstants.iconLarge,
        color: Colors.white,
      ),
    );
  }

  Widget _buildEncouragementMessage() {
    return Container(
      padding: const EdgeInsets.all(UIConstants.radiusXLarge),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(UIConstants.radiusLarge),
      ),
      child: const Column(
        children: [
          Text(
            '정말 잘하셨어요!',
            style: TextStyle(
              fontSize: UIConstants.textLarge + 2,
              fontWeight: FontWeight.bold,
              color: AppTheme.progressColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}