# Modern FCM Setup Guide (2024/2025)

⚠️ **Important**: Google has deprecated legacy FCM Server Keys. Here are the modern approaches to implement FCM notifications.

## 🚨 Why Server Key is Missing

The legacy "Server Key" in Firebase Console has been **deprecated** as of 2024. Google now recommends using:
1. **Firebase Functions** (Recommended)
2. **FCM HTTP v1 API** with Service Account credentials
3. **Legacy Server Key** (if still needed for existing projects)

## 🔧 Solution Options

### **Option 1: Firebase Functions (Recommended)**

Create a Firebase Function to send notifications securely:

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendNotification = functions.https.onRequest(async (req, res) => {
  const { type, familyId, elderlyName, timestamp, hoursInactive, hoursWithoutFood } = req.body;
  
  let message;
  switch (type) {
    case 'meal_recorded':
      const time = new Date(timestamp).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
      message = {
        topic: `family_${familyId}`,
        data: {
          type: 'meal_recorded',
          elderlyName,
          timestamp,
          familyId,
        },
        notification: {
          title: `${elderlyName}이 식사하셨어요`,
          body: `오늘 ${time}에 식사했습니다`,
        },
      };
      break;
    case 'survival_alert':
      message = {
        topic: `family_${familyId}`,
        data: {
          type: 'survival_alert',
          elderlyName,
          hoursInactive: hoursInactive.toString(),
          familyId,
          timestamp,
        },
        notification: {
          title: `⚠️ ${elderlyName} 안전 알림`,
          body: `${hoursInactive}시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요.`,
        },
      };
      break;
    case 'food_alert':
      message = {
        topic: `family_${familyId}`,
        data: {
          type: 'food_alert',
          elderlyName,
          hoursWithoutFood: hoursWithoutFood.toString(),
          familyId,
          timestamp,
        },
        notification: {
          title: `🍽️ ${elderlyName} 식사 알림`,
          body: `${hoursWithoutFood}시간 이상 식사하지 않았습니다. 확인해주세요.`,
        },
      };
      break;
    default:
      return res.status(400).send('Invalid notification type');
  }
  
  try {
    await admin.messaging().send(message);
    res.status(200).send('Notification sent successfully');
  } catch (error) {
    console.error('Error sending notification:', error);
    res.status(500).send('Error sending notification');
  }
});
```

**Deploy:**
```bash
cd functions
npm install firebase-functions firebase-admin
firebase deploy --only functions
```

### **Option 2: Legacy Server Key (If Available)**

If you have an existing project that still shows Server Key:

1. **Enable Legacy API:**
   - Google Cloud Console > APIs & Services
   - Search for "Firebase Cloud Messaging API (Legacy)"
   - Enable it
   - Go back to Firebase Console > Cloud Messaging
   - Server Key should now appear

2. **Update FCM Service:**
   ```dart
   // In fcm_notification_service.dart
   static const bool _enableDirectFCM = true; // Enable direct FCM
   static const String _serverKey = 'YOUR_ACTUAL_SERVER_KEY_HERE';
   ```

### **Option 3: Service Account JSON (Advanced)**

For production apps, use Service Account credentials:

1. **Get Service Account:**
   - Firebase Console > Settings > Service Accounts
   - Generate new private key (downloads JSON)

2. **Implement OAuth 2.0 flow** in your app (complex)

## 🧪 Current Testing

With current setup, when you click "I ate", you should see:

```
🔔 Attempting Firebase Functions for meal_recorded notification...
❌ Firebase Functions call failed: 404
⚠️ Direct FCM disabled or server key not configured
💡 Please set up Firebase Functions or enable legacy server key
Failed to send FCM notification for meal record: false
```

## 📱 Quick Test Options

### **Option A: Test with Firebase Console**
1. Firebase Console > Cloud Messaging
2. Send test message
3. Target: Topic `family_{your_family_id}`
4. Check if child app receives it

### **Option B: Enable Legacy API (Temporary)**
1. Google Cloud Console > APIs & Services
2. Enable "Firebase Cloud Messaging API (Legacy)"
3. Look for Server Key in Firebase Console
4. Update `_enableDirectFCM = true` and add real server key

### **Option C: Deploy Firebase Functions**
1. Follow Option 1 above
2. Deploy the function
3. FCM notifications will work automatically

## 🎯 Recommended Next Steps

1. **For immediate testing**: Try Option B (Legacy API)
2. **For production**: Implement Option A (Firebase Functions)
3. **Current state**: App saves meals correctly, but FCM needs setup

The meal recording functionality works perfectly - you just need to set up the notification delivery method!