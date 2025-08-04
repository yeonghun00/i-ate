# FCM Notification Setup Guide

This guide explains how to configure Firebase Cloud Messaging (FCM) notifications for the parent app to send notifications to the child app.

## 🔧 Setup Steps

### 1. Get FCM Server Key

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `thanks-everyday`
3. Click ⚙️ **Project Settings**
4. Go to **Cloud Messaging** tab
5. Copy the **Server Key** (under Project credentials)

### 2. Update FCM Service

Replace the placeholder in `/lib/services/fcm_notification_service.dart`:

```dart
// Replace this line:
static const String _serverKey = 'YOUR_FCM_SERVER_KEY_HERE';

// With your actual server key:
static const String _serverKey = 'AAAAxxxxxxx:APA91bHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
```

### 3. Android Permissions (Already Added)

The following permissions are already in `android/app/src/main/AndroidManifest.xml`:
- `INTERNET` ✅
- `WAKE_LOCK` ✅

### 4. Dependencies (Already Added)

Required dependencies in `pubspec.yaml`:
- `firebase_messaging: ^15.0.0` ✅
- `http: ^1.1.0` ✅

## 📱 How It Works

### Notification Types

The app sends 3 types of FCM notifications:

#### 1. **Meal Recorded** (`meal_recorded`)
**When**: User clicks "식사 했어요!" button
**Topic**: `family_{familyId}`
**Message Format**:
```json
{
  "topic": "family_12345",
  "data": {
    "type": "meal_recorded",
    "elderlyName": "할머니",
    "timestamp": "2025-01-19T12:30:00.000Z",
    "familyId": "12345"
  },
  "notification": {
    "title": "할머니이 식사하셨어요",
    "body": "오늘 12:30에 식사했습니다"
  }
}
```

#### 2. **Survival Alert** (`survival_alert`)
**When**: No phone activity for X hours (3/6/12/24)
**Topic**: `family_{familyId}`
**Message Format**:
```json
{
  "topic": "family_12345",
  "data": {
    "type": "survival_alert",
    "elderlyName": "할머니",
    "hoursInactive": "12",
    "familyId": "12345"
  },
  "notification": {
    "title": "⚠️ 할머니 안전 알림",
    "body": "12시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요."
  }
}
```

#### 3. **Food Alert** (`food_alert`)
**When**: No food intake for X hours (default 8)
**Topic**: `family_{familyId}`
**Message Format**:
```json
{
  "topic": "family_12345",
  "data": {
    "type": "food_alert",
    "elderlyName": "할머니",
    "hoursWithoutFood": "8",
    "familyId": "12345"
  },
  "notification": {
    "title": "🍽️ 할머니 식사 알림",
    "body": "8시간 이상 식사하지 않았습니다. 확인해주세요."
  }
}
```

## 🔒 Security Recommendations

### Option 1: Direct FCM (Current Implementation)
- ✅ Simple setup
- ❌ Server key exposed in app
- ❌ Less secure for production

### Option 2: Firebase Functions (Recommended)
- ✅ Server key hidden
- ✅ More secure
- ✅ Better for production

To use Firebase Functions:
1. Deploy the FCM function to Firebase
2. Update the Functions URL in the service
3. Remove the server key from the app

## 🧪 Testing

### Test FCM Notifications

1. **Manual Test**: Use Firebase Console > Cloud Messaging > Send test message
2. **Topic Test**: Send to topic `family_{familyId}`
3. **App Test**: Record a meal and check child app receives notification

### Debug Steps

1. Check console logs for FCM errors
2. Verify child app is subscribed to the correct topic
3. Ensure FCM server key is correct
4. Check internet connectivity

## 📁 Integration Points

### Parent App Integration
- ✅ `firebase_service.dart` - Calls FCM service after meal recording
- ✅ `firebase_service.dart` - Calls FCM service for survival alerts
- ✅ `firebase_service.dart` - Calls FCM service for food alerts

### Child App Requirements
The child app should:
1. Subscribe to topic `family_{familyId}` when connecting
2. Handle FCM data messages with the formats above
3. Display appropriate notifications/UI updates

## 🚨 Important Notes

1. **Firebase Project**: Both apps must use the same Firebase project (`thanks-everyday`)
2. **Topic Format**: Always use `family_{familyId}` format
3. **Error Handling**: FCM failures won't break meal recording
4. **Fallback**: If Firebase Functions fail, it falls back to direct FCM
5. **Production**: Consider moving to Firebase Functions for security

## 🔍 Troubleshooting

### Common Issues

**FCM not sending**: 
- Check server key is correct
- Verify internet connection
- Check Firebase project is correct

**Child app not receiving**:
- Ensure child app subscribes to correct topic
- Check child app FCM implementation
- Verify both apps use same Firebase project

**Authentication errors**:
- Server key might be wrong
- Check Firebase Console credentials

### Logs to Check

```
FCM notification sent successfully to topic: family_12345
Survival alert FCM notification sent
Food alert FCM notification sent
Failed to send FCM notification: 401
```