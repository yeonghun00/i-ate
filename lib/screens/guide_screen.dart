import 'package:flutter/material.dart';
import 'package:thanks_everyday/screens/permission_guide_screen.dart';
import 'package:thanks_everyday/screens/special_permission_guide_screen.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

class GuideScreen extends StatefulWidget {
  final VoidCallback onGuideComplete;

  const GuideScreen({super.key, required this.onGuideComplete});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<GuideStep> _steps = [
    GuideStep(
      title: '환영합니다!',
      description: '식사하셨어요? 앱 사용법을\n간단히 알려드릴게요',
      icon: Icons.waving_hand,
      color: AppTheme.primaryGreen,
    ),
    GuideStep(
      title: '식사 기록 버튼',
      description: '화면 가운데 큰 버튼을\n눌러서 식사를 기록하세요',
      icon: Icons.restaurant_rounded,
      color: AppTheme.primaryGreen,
    ),
    GuideStep(
      title: '위치도 함께',
      description: '원하시면 위치도\n함께 추가할 수 있어요',
      icon: Icons.gps_fixed_outlined,
      color: AppTheme.accentBlue,
    ),
    GuideStep(
      title: '하루 3번까지',
      description: '하루에 3번까지\n식사를 기록할 수 있어요',
      icon: Icons.fastfood_rounded,
      color: AppTheme.accentPink,
    ),
    GuideStep(
      title: '가족과 공유',
      description: '가족들이 당신의 식사\n상황을 확인할 수 있어요',
      icon: Icons.family_restroom,
      color: AppTheme.accentPurple,
    ),
    GuideStep(
      title: '특별 권한 설정',
      description: '휴대폰 사용 모니터링을 위한\n특별 권한이 필요해요',
      icon: Icons.admin_panel_settings,
      color: AppTheme.accentPurple,
    ),
    GuideStep(
      title: '시작할 준비 완료!',
      description: '이제 식사를 기록하고\n건강을 관리해보세요',
      icon: Icons.celebration,
      color: AppTheme.accentOrange,
    ),
  ];

  @override
  void initState() {
    super.initState();
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      setState(() {
        _currentPage++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Navigate to basic permissions first, then special permissions
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PermissionGuideScreen(
            onPermissionsGranted: () {
              // After basic permissions, show special permissions
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => SpecialPermissionGuideScreen(
                    onPermissionsComplete: widget.onGuideComplete,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
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
              // Progress indicator
              Container(
                margin: const EdgeInsets.all(20),
                child: Row(
                  children: List.generate(_steps.length, (index) {
                    return Expanded(
                      child: Container(
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: index <= _currentPage
                              ? AppTheme.primaryGreen
                              : AppTheme.borderLight,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    return _buildGuideStep(_steps[index]);
                  },
                ),
              ),

              // Navigation buttons
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Previous button
                    if (_currentPage > 0)
                      GestureDetector(
                        onTap: _previousPage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back,
                                size: 20,
                                color: AppTheme.textLight,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '이전',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 80),

                    // Page indicator
                    Text(
                      '${_currentPage + 1}/${_steps.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textLight,
                      ),
                    ),

                    // Next button
                    GestureDetector(
                      onTap: _nextPage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentPage == _steps.length - 1 ? '시작하기' : '다음',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _currentPage == _steps.length - 1
                                  ? Icons.check
                                  : Icons.arrow_forward,
                              size: 20,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideStep(GuideStep step) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [step.color, step.color.withValues(alpha: 0.7)],
              ),
              boxShadow: [
                BoxShadow(
                  color: step.color.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(step.icon, size: 60, color: Colors.white),
          ),

          const SizedBox(height: 40),

          // Title
          Text(
            step.title,
            style: const TextStyle(
              fontSize: 32.0,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          // Description
          Text(
            step.description,
            style: const TextStyle(
              fontSize: 20.0,
              color: AppTheme.textLight,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class GuideStep {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  GuideStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
