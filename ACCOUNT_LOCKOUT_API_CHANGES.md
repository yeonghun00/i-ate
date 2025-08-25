# Account Lockout System - API Changes for Child App Developers

## Overview

We have implemented an account lockout system to enhance security for elderly user accounts. This system applies lockouts to the **target elderly account**, not the device, and prevents unauthorized access attempts.

## Lockout Rules

- **6 failed attempts** → 30-minute lockout
- **10 failed attempts** → 24-hour lockout
- Lockout applies to the target elderly account (connectionCode), not the child device
- Previously implemented 3-attempt/5-minute lockout has been **removed** for simplicity

## API Changes

### 1. Enhanced `getFamilyInfo` Response

The `getFamilyInfo` method now includes lockout detection and returns additional error information:

#### Success Response (No Changes)
```dart
{
  'familyId': 'family_uuid',
  'connectionCode': '1234',
  'elderlyName': '김할머니',
  'approved': true,
  // ... other family data
}
```

#### New Lockout Error Response
```dart
{
  'error': 'account_locked',
  'lockoutLevel': '30min' | '24hour',
  'remainingTime': Duration,
  'lockoutUntil': DateTime,
}
```

### 2. New Error Types

Add these error types to your error handling:

```dart
enum AccountRecoveryErrorType {
  connectionCodeNotFound,
  nameNotMatch,
  multipleMatches,
  recoveryFailed,
  accountLocked30Min,    // NEW
  accountLocked24Hour,   // NEW
}
```

### 3. Updated User Messages

#### Korean Messages
- 30분 잠금: `"30분 계정 잠금이 적용되었습니다. {remaining_time} 후 다시 시도해주세요."`
- 24시간 잠금: `"24시간 계정 잠금이 적용되었습니다. {remaining_time} 후 다시 시도해주세요."`

#### English Messages (if applicable)
- 30-min lockout: `"Account locked for 30 minutes. Please try again in {remaining_time}."`
- 24-hour lockout: `"Account locked for 24 hours. Please try again in {remaining_time}."`

## Implementation Guide

### 1. Update Connection Validation Logic

**Before:**
```dart
Future<void> connectToElderlyAccount(String connectionCode) async {
  final result = await childAppService.getFamilyInfo(connectionCode);
  if (result == null) {
    showError("연결 코드를 찾을 수 없습니다");
    return;
  }
  // Handle success
}
```

**After:**
```dart
Future<void> connectToElderlyAccount(String connectionCode) async {
  final result = await childAppService.getFamilyInfo(connectionCode);
  
  if (result == null) {
    showError("연결 코드를 찾을 수 없습니다");
    return;
  }
  
  // NEW: Check for lockout
  if (result['error'] == 'account_locked') {
    final lockoutLevel = result['lockoutLevel'];
    final remainingTime = result['remainingTime'] as Duration;
    
    final timeString = formatDuration(remainingTime);
    
    if (lockoutLevel == '24hour') {
      showError("24시간 계정 잠금이 적용되었습니다. $timeString 후 다시 시도해주세요.");
    } else {
      showError("30분 계정 잠금이 적용되었습니다. $timeString 후 다시 시도해주세요.");
    }
    return;
  }
  
  // Handle success
}
```

### 2. Add Duration Formatting Helper

```dart
String formatDuration(Duration duration) {
  if (duration.inHours > 0) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (minutes > 0) {
      return '${hours}시간 ${minutes}분';
    }
    return '${hours}시간';
  }
  
  final minutes = duration.inMinutes;
  if (minutes > 0) {
    return '${minutes}분';
  }
  
  return '1분 이내';
}
```

### 3. Update Error Handling

```dart
void handleConnectionError(Map<String, dynamic> result) {
  final errorType = result['error'];
  
  switch (errorType) {
    case 'account_locked':
      handleLockoutError(result);
      break;
    case 'connection_code_not_found':
      showError("연결 코드를 찾을 수 없습니다. 코드를 다시 확인해주세요.");
      break;
    default:
      showError("연결 중 오류가 발생했습니다. 다시 시도해주세요.");
  }
}

void handleLockoutError(Map<String, dynamic> result) {
  final lockoutLevel = result['lockoutLevel'];
  final remainingTime = result['remainingTime'] as Duration;
  final timeString = formatDuration(remainingTime);
  
  if (lockoutLevel == '24hour') {
    showError("24시간 계정 잠금이 적용되었습니다. $timeString 후 다시 시도해주세요.");
  } else {
    showError("30분 계정 잠금이 적용되었습니다. $timeString 후 다시 시도해주세요.");
  }
}
```

## Database Schema Changes

The family document now includes:

```dart
{
  // ... existing fields
  'accountLockout': {
    'failedAttempts': 0,
    'lockoutUntil': null, // Timestamp or null
    'lockoutLevel': null, // '30min' | '24hour' | null
    'lastFailedAttempt': null, // Timestamp or null
  },
}
```

## Testing Recommendations

1. **Test Failed Attempts**: Verify that 6 failed attempts trigger 30-minute lockout
2. **Test Extended Lockout**: Verify that 10 failed attempts trigger 24-hour lockout
3. **Test Lockout Expiration**: Verify that lockouts are automatically cleared when time expires
4. **Test Successful Connection**: Verify that successful connections clear failed attempt counters
5. **Test Error Messages**: Verify that lockout messages display correct remaining time

## Migration Notes

- **No breaking changes** for existing successful connection flows
- Only failed connection attempts now have additional error information
- Existing error handling will continue to work, but lockout errors may appear as generic failures without the enhanced error handling

## Security Benefits

1. **Prevents brute force attacks** on connection codes
2. **Progressive penalties** discourage repeated unauthorized attempts
3. **Account-based lockout** ensures security even if attacker changes devices
4. **Automatic recovery** prevents permanent lockouts from legitimate users

## Support

For questions or issues with this implementation, please contact the development team.

**Implementation Date**: January 2025
**API Version**: v1.1.0