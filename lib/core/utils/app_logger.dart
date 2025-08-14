import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

class AppLogger {
  static const String _tag = 'ThanksEveryday';
  
  static void debug(String message, {String? tag}) {
    _log(LogLevel.debug, message, tag: tag);
  }
  
  static void info(String message, {String? tag}) {
    _log(LogLevel.info, message, tag: tag);
  }
  
  static void warning(String message, {String? tag}) {
    _log(LogLevel.warning, message, tag: tag);
  }
  
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);
  }
  
  static void _log(
    LogLevel level, 
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final String logTag = tag ?? _tag;
    final String prefix = _getLevelPrefix(level);
    final String formattedMessage = '$prefix [$logTag] $message';
    
    developer.log(
      formattedMessage,
      name: logTag,
      error: error,
      stackTrace: stackTrace,
      level: _getLogLevel(level),
    );
    
    // Also print for development
    print(formattedMessage);
    if (error != null) {
      print('Error: $error');
    }
    if (stackTrace != null) {
      print('StackTrace: $stackTrace');
    }
  }
  
  static String _getLevelPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return '📱';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }
  
  static int _getLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500; // FINE
      case LogLevel.info:
        return 800; // INFO
      case LogLevel.warning:
        return 900; // WARNING
      case LogLevel.error:
        return 1000; // SEVERE
    }
  }
}

// Convenience extensions for commonly used log patterns
extension LoggerExtensions on Object {
  void logDebug(String message) => AppLogger.debug(message, tag: runtimeType.toString());
  void logInfo(String message) => AppLogger.info(message, tag: runtimeType.toString());
  void logWarning(String message) => AppLogger.warning(message, tag: runtimeType.toString());
  void logError(String message, {Object? error, StackTrace? stackTrace}) => 
      AppLogger.error(message, tag: runtimeType.toString(), error: error, stackTrace: stackTrace);
}