import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thanks_everyday/core/services/app_initialization_service.dart';
import 'package:thanks_everyday/core/state/app_state.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/core/errors/app_exceptions.dart';
import 'package:thanks_everyday/screens/home_page.dart';
import 'package:thanks_everyday/screens/initial_setup_screen.dart';
import 'package:thanks_everyday/services/miui_boot_helper.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> with AppLogger {
  final AppInitializationService _initService = AppInitializationService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final appState = context.read<AppState>();
    appState.setLoading(true);
    appState.clearError();

    final result = await _initService.initializeApp();
    
    result.fold(
      onSuccess: (isSetup) {
        appState.setSetupComplete(isSetup);
        appState.setLoading(false);
        
        if (isSetup) {
          // Delay to allow UI to render first
          Future.delayed(const Duration(seconds: 1), () {
            _checkMiuiGuidance();
          });
        }
      },
      onFailure: (exception) {
        AppLogger.error('App initialization failed', error: exception);
        appState.setError(exception.message);
        appState.setLoading(false);
      },
    );
  }

  Future<void> _checkMiuiGuidance() async {
    if (!mounted) return;
    
    try {
      AppLogger.info('Checking if MIUI guidance should be shown');
      
      // Check for post-boot activation first
      final needsPostBoot = await MiuiBootHelper.needsPostBootActivation();
      if (needsPostBoot && mounted) {
        AppLogger.info('Post-boot activation needed');
        await MiuiBootHelper.showPostBootActivationDialog(context);
        return;
      }
      
      // Check if MIUI setup guidance should be shown
      final shouldShow = await MiuiBootHelper.shouldShowMiuiGuidance();
      if (shouldShow && mounted) {
        AppLogger.info('MIUI setup guidance required');
        
        // Delay slightly to ensure the UI is ready
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          await MiuiBootHelper.showMiuiSetupDialog(context);
        }
      } else {
        AppLogger.info('No MIUI guidance required');
      }
    } catch (e) {
      AppLogger.error('Error checking MIUI guidance', error: e);
    }
  }

  Future<void> _onSetupComplete() async {
    AppLogger.info('Setup completed, navigating to main page');
    
    try {
      final appState = context.read<AppState>();
      
      // Initialize services after setup
      final result = await _initService.initializeServicesAfterSetup();
      
      result.fold(
        onSuccess: (_) {
          appState.setSetupComplete(true);
          AppLogger.info('Services initialized successfully after setup');
        },
        onFailure: (exception) {
          AppLogger.error('Failed to initialize services after setup', error: exception);
          // Still proceed with setup completion, but log the error
          appState.setSetupComplete(true);
        },
      );
    } catch (e) {
      AppLogger.error('Error during setup completion', error: e);
      // Still proceed with setup completion
      context.read<AppState>().setSetupComplete(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        AppLogger.debug(
          'AppWrapper build - isLoading: ${appState.isLoading}, isSetup: ${appState.isSetup}',
        );

        if (appState.isLoading) {
          return _buildLoadingScreen();
        }

        if (appState.errorMessage != null) {
          return _buildErrorScreen(appState.errorMessage!);
        }

        if (!appState.isSetup) {
          AppLogger.debug('Showing InitialSetupScreen');
          return InitialSetupScreen(onSetupComplete: _onSetupComplete);
        }

        AppLogger.debug('Showing HomePage');
        return const HomePage();
      },
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String errorMessage) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppTheme.errorRed,
            ),
            const SizedBox(height: 16),
            Text(
              '앱 시작 중 오류가 발생했습니다',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _initializeApp(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}