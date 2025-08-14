abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const AppException({
    required this.message,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'AppException: $message';
}

class FirebaseInitException extends AppException {
  const FirebaseInitException({
    required String message,
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    code: code,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

class AccountRecoveryException extends AppException {
  final AccountRecoveryErrorType errorType;

  const AccountRecoveryException({
    required String message,
    required this.errorType,
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    code: code,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

enum AccountRecoveryErrorType {
  connectionCodeNotFound,
  nameNotMatch,
  multipleMatches,
  recoveryFailed,
}

class MealRecordException extends AppException {
  const MealRecordException({
    required String message,
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    code: code,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

class PermissionException extends AppException {
  final PermissionType permissionType;

  const PermissionException({
    required String message,
    required this.permissionType,
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    code: code,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

enum PermissionType {
  location,
  batteryOptimization,
  usageStats,
  notification,
  exactAlarm,
}

class ServiceException extends AppException {
  const ServiceException({
    required String message,
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message: message,
    code: code,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

// Result wrapper for better error handling
sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final AppException exception;
  const Failure(this.exception);
}

// Extensions for Result handling
extension ResultExtensions<T> on Result<T> {
  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;
  
  T? get data => switch (this) {
    Success<T>(data: final data) => data,
    Failure<T>() => null,
  };
  
  AppException? get exception => switch (this) {
    Success<T>() => null,
    Failure<T>(exception: final exception) => exception,
  };
  
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(AppException exception) onFailure,
  }) {
    return switch (this) {
      Success<T>(data: final data) => onSuccess(data),
      Failure<T>(exception: final exception) => onFailure(exception),
    };
  }
}