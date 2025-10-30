import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

/// Service to monitor internet connectivity and notify users when offline
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isConnected = true;
  final List<Function(bool)> _listeners = [];

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    try {
      // Check initial connectivity status
      final result = await _connectivity.checkConnectivity();
      _isConnected = !result.contains(ConnectivityResult.none);

      AppLogger.info('Initial connectivity status: ${_isConnected ? "Connected" : "Disconnected"}', tag: 'ConnectivityService');

      // Listen to connectivity changes
      _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> result) {
        final wasConnected = _isConnected;
        _isConnected = !result.contains(ConnectivityResult.none);

        AppLogger.info('Connectivity changed: ${_isConnected ? "Connected" : "Disconnected"}', tag: 'ConnectivityService');

        // Notify listeners if status changed
        if (wasConnected != _isConnected) {
          for (var listener in _listeners) {
            listener(_isConnected);
          }
        }
      });
    } catch (e) {
      AppLogger.error('Failed to initialize connectivity service: $e', tag: 'ConnectivityService');
    }
  }

  /// Check if currently connected to internet
  bool get isConnected => _isConnected;

  /// Add a listener for connectivity changes
  void addListener(Function(bool isConnected) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(Function(bool isConnected) listener) {
    _listeners.remove(listener);
  }

  /// Show a warning banner about no internet connection
  static void showNoConnectionWarning(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '⚠️ 인터넷 연결이 끊어졌습니다\n데이터가 전송되지 않습니다',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Show a confirmation banner when internet is restored
  static void showConnectionRestoredMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '✅ 인터넷 연결이 복구되었습니다',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Dispose of the service
  void dispose() {
    _subscription?.cancel();
    _listeners.clear();
  }
}
