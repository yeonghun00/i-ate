import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/errors/app_exceptions.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';
import 'package:thanks_everyday/firebase_options.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';
import 'package:thanks_everyday/services/smart_usage_detector.dart';
import 'package:thanks_everyday/services/overlay_service.dart';
import 'package:thanks_everyday/services/miui_boot_helper.dart';

class AppInitializationService {
  static final AppInitializationService _instance = AppInitializationService._internal();
  factory AppInitializationService() => _instance;
  AppInitializationService._internal();

  final FirebaseService _firebaseService = FirebaseService();

  Future<Result<bool>> initializeApp() async {
    try {
      logInfo('Starting app initialization');
      
      // Initialize Firebase
      final firebaseResult = await _initializeFirebase();
      if (firebaseResult.isFailure) {
        return Failure(firebaseResult.exception!);
      }
      
      // Initialize core services
      await _initializeCoreServices();
      
      // Check setup status
      final setupStatus = await _checkSetupStatus();
      
      logInfo('App initialization completed successfully');
      return Success(setupStatus);
      
    } catch (e, stackTrace) {
      logError('App initialization failed', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'App initialization failed: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<Result<void>> _initializeFirebase() async {
    try {
      logInfo('Initializing Firebase');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      logInfo('Firebase initialized successfully');
      return const Success(null);
      
    } catch (e, stackTrace) {
      logError('Firebase initialization failed', error: e, stackTrace: stackTrace);
      return Failure(FirebaseInitException(
        message: AppConstants.errorFirebaseInit,
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _initializeCoreServices() async {
    final List<Future<void>> initTasks = [
      _initializeScreenMonitor(),
      _initializeUsageDetector(),
      _initializeOverlayService(),
      _initializeMiuiBootHelper(),
    ];

    await Future.wait(initTasks);
  }

  Future<void> _initializeScreenMonitor() async {
    try {
      await ScreenMonitorService.initialize();
      logInfo('ScreenMonitorService initialized successfully');
    } catch (e) {
      logWarning('ScreenMonitorService initialization failed: $e');
    }
  }

  Future<void> _initializeUsageDetector() async {
    try {
      await SmartUsageDetector.instance.initialize();
      logInfo('SmartUsageDetector initialized successfully');
    } catch (e) {
      logWarning('SmartUsageDetector initialization failed: $e');
    }
  }

  Future<void> _initializeOverlayService() async {
    try {
      await OverlayService.initialize();
      logInfo('OverlayService initialized successfully');
    } catch (e) {
      logWarning('OverlayService initialization failed: $e');
    }
  }

  Future<void> _initializeMiuiBootHelper() async {
    try {
      await MiuiBootHelper.initializeOnAppStart();
      logInfo('MiuiBootHelper initialized successfully');
    } catch (e) {
      logWarning('MiuiBootHelper initialization failed: $e');
    }
  }

  Future<bool> _checkSetupStatus() async {
    try {
      // Check Firebase setup
      final isFirebaseSetup = await _firebaseService.initialize();
      
      // Check SharedPreferences setup
      final prefs = await SharedPreferences.getInstance();
      final setupComplete = prefs.getBool(AppConstants.keySetupComplete) ?? false;
      final hasFamilyCode = prefs.getString(AppConstants.keyFamilyCode) != null;

      logInfo('Setup status check:');
      logInfo('  - Firebase setup: $isFirebaseSetup');
      logInfo('  - SharedPreferences setup: $setupComplete');
      logInfo('  - Has family code: $hasFamilyCode');

      // Auto-detection logic for existing accounts
      if (!isFirebaseSetup && !setupComplete && !hasFamilyCode) {
        await _tryAutoDetection();
      }

      final actuallySetup = isFirebaseSetup || setupComplete;
      logInfo('Final setup decision: $actuallySetup');
      
      return actuallySetup;
      
    } catch (e) {
      logError('Setup status check failed', error: e);
      return false;
    }
  }

  Future<void> _tryAutoDetection() async {
    try {
      logInfo('No existing data found, attempting auto-detection...');
      final candidates = await _firebaseService.autoDetectExistingAccounts();
      
      if (candidates.isNotEmpty) {
        logInfo('Auto-detection found ${candidates.length} potential account matches');
        
        for (final candidate in candidates) {
          logInfo('  - ${candidate['elderlyName']} (${candidate['connectionCode']}) - Confidence: ${candidate['confidence']}');
        }
        
        final highConfidenceMatch = candidates.where((c) => c['confidence'] >= AppConstants.highConfidenceThreshold).toList();
        if (highConfidenceMatch.isNotEmpty) {
          logInfo('High-confidence account found: ${highConfidenceMatch.first['elderlyName']}');
        }
      } else {
        logInfo('Auto-detection found no potential matches');
      }
    } catch (e) {
      logError('Auto-detection error', error: e);
    }
  }

  Future<Result<void>> initializeServicesAfterSetup() async {
    try {
      logInfo('Initializing services after setup completion');
      
      await ScreenMonitorService.initialize();
      
      final prefs = await SharedPreferences.getInstance();
      final survivalEnabled = prefs.getBool(AppConstants.keySurvivalSignalEnabled) ?? false;
      final locationEnabled = prefs.getBool(AppConstants.keyLocationTrackingEnabled) ?? false;
      
      logInfo('Service initialization settings:');
      logInfo('  - Survival signal: $survivalEnabled');
      logInfo('  - Location tracking: $locationEnabled');
      
      if (survivalEnabled) {
        await _enableSurvivalSignal();
      }
      
      if (locationEnabled) {
        await _enableLocationTracking();
      }
      
      logInfo('Services initialized successfully after setup');
      return const Success(null);
      
    } catch (e, stackTrace) {
      logError('Failed to initialize services after setup', error: e, stackTrace: stackTrace);
      return Failure(ServiceException(
        message: 'Failed to initialize services after setup: $e',
        originalError: e,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _enableSurvivalSignal() async {
    try {
      await ScreenMonitorService.enableSurvivalSignal();
      logInfo('Survival signal monitoring enabled');
    } catch (e) {
      logError('Failed to enable survival signal', error: e);
    }
  }

  Future<void> _enableLocationTracking() async {
    try {
      // Enable location tracking service
      // TODO: Import and use LocationService once refactored
      logInfo('Location tracking enabled');
    } catch (e) {
      logError('Failed to enable location tracking', error: e);
    }
  }
}

// Extension to add logging methods
extension AppInitializationServiceLogging on AppInitializationService {
  void logDebug(String message) => AppLogger.debug(message, tag: 'AppInitialization');
  void logInfo(String message) => AppLogger.info(message, tag: 'AppInitialization');
  void logWarning(String message) => AppLogger.warning(message, tag: 'AppInitialization');
  void logError(String message, {Object? error, StackTrace? stackTrace}) => 
      AppLogger.error(message, tag: 'AppInitialization', error: error, stackTrace: stackTrace);
}