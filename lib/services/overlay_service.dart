import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

class OverlayService {
  static const MethodChannel _channel = MethodChannel('overlay_service');
  
  // Check if overlay permission is granted
  static Future<bool> hasOverlayPermission() async {
    final status = await Permission.systemAlertWindow.status;
    return status.isGranted;
  }
  
  // Request overlay permission
  static Future<bool> requestOverlayPermission() async {
    final status = await Permission.systemAlertWindow.request();
    return status.isGranted;
  }
  
  // Start invisible overlay for app persistence
  static Future<bool> startInvisibleOverlay() async {
    try {
      if (!await hasOverlayPermission()) {
        AppLogger.warning('Overlay permission not granted', tag: 'OverlayService');
        return false;
      }
      
      // Create invisible overlay that helps keep app alive
      final result = await _channel.invokeMethod('startInvisibleOverlay');
      
      // Mark overlay as enabled in preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('overlay_enabled', true);
      
      AppLogger.info('Invisible overlay started for app persistence', tag: 'OverlayService');
      return result ?? false;
    } catch (e) {
      AppLogger.error('Failed to start invisible overlay: $e', tag: 'OverlayService');
      return false;
    }
  }
  
  // Stop invisible overlay
  static Future<bool> stopInvisibleOverlay() async {
    try {
      final result = await _channel.invokeMethod('stopInvisibleOverlay');
      
      // Mark overlay as disabled in preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('overlay_enabled', false);
      
      AppLogger.info('Invisible overlay stopped', tag: 'OverlayService');
      return result ?? false;
    } catch (e) {
      AppLogger.error('Failed to stop invisible overlay: $e', tag: 'OverlayService');
      return false;
    }
  }
  
  // Check if overlay is currently enabled
  static Future<bool> isOverlayEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('overlay_enabled') ?? false;
  }
  
  // Initialize overlay service - start invisible overlay if permission granted
  static Future<void> initialize() async {
    if (await hasOverlayPermission()) {
      await startInvisibleOverlay();
      AppLogger.info('Overlay service initialized with invisible overlay', tag: 'OverlayService');
    } else {
      AppLogger.warning('Overlay service initialized without overlay (permission not granted)', tag: 'OverlayService');
    }
  }
}