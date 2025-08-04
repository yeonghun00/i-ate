# 🚀 Firebase Functions Setup (Easiest Solution)

This is the **simplest way** to get FCM notifications working with FCM v1 API.

## Step 1: Initialize Firebase Functions

```bash
# In your project root directory
npm install -g firebase-tools
firebase login
firebase init functions
```

Select:
- ✅ TypeScript or JavaScript (your choice)
- ✅ Install dependencies

## Step 2: Create the Function

Create `functions/src/index.ts` (or `functions/index.js`):

```javascript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

export const sendNotification = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.status(200).send('');
    return;
  }
  
  try {
    const { type, familyId, elderlyName, timestamp, hoursInactive, hoursWithoutFood } = req.body;
    
    if (!type || !familyId || !elderlyName) {
      res.status(400).send('Missing required fields');
      return;
    }
    
    let message;
    const topic = `family_${familyId}`;
    
    switch (type) {
      case 'meal_recorded':
        const date = new Date(timestamp);
        const timeString = date.toLocaleTimeString('ko-KR', { 
          hour: '2-digit', 
          minute: '2-digit',
          hour12: false
        });
        
        message = {
          topic,
          data: {
            type: 'meal_recorded',
            elderlyName,
            timestamp,
            familyId,
          },
          notification: {
            title: `${elderlyName}이 식사하셨어요`,
            body: `오늘 ${timeString}에 식사했습니다`,
          },
          android: {
            priority: 'high' as const,
            notification: {
              sound: 'default',
              channelId: 'high_importance_channel',
            },
          },
        };
        break;
        
      case 'survival_alert':
        message = {
          topic,
          data: {
            type: 'survival_alert',
            elderlyName,
            hoursInactive: hoursInactive?.toString() || '12',
            familyId,
            timestamp: timestamp || new Date().toISOString(),
          },
          notification: {
            title: `⚠️ ${elderlyName} 안전 알림`,
            body: `${hoursInactive || 12}시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요.`,
          },
          android: {
            priority: 'high' as const,
            notification: {
              sound: 'default',
              channelId: 'high_importance_channel',
            },
          },
        };
        break;
        
      case 'food_alert':
        message = {
          topic,
          data: {
            type: 'food_alert',
            elderlyName,
            hoursWithoutFood: hoursWithoutFood?.toString() || '8',
            familyId,
            timestamp: timestamp || new Date().toISOString(),
          },
          notification: {
            title: `🍽️ ${elderlyName} 식사 알림`,
            body: `${hoursWithoutFood || 8}시간 이상 식사하지 않았습니다. 확인해주세요.`,
          },
          android: {
            priority: 'high' as const,
            notification: {
              sound: 'default',
              channelId: 'high_importance_channel',
            },
          },
        };
        break;
        
      default:
        res.status(400).send('Invalid notification type');
        return;
    }
    
    console.log('Sending notification:', { topic, type, elderlyName });
    
    const result = await admin.messaging().send(message);
    console.log('Notification sent successfully:', result);
    
    res.status(200).json({ 
      success: true, 
      messageId: result,
      topic,
      type 
    });
    
  } catch (error) {
    console.error('Error sending notification:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});
```

## Step 3: Deploy the Function

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

## Step 4: Update Your App

The app is already configured to call Firebase Functions! Just verify the URL is correct.

Check in `/lib/services/fcm_notification_service.dart`:
```dart
static const String _functionsUrl = 'https://us-central1-thanks-everyday.cloudfunctions.net';
```

## Step 5: Test

1. Click "I ate" in your parent app
2. Check Flutter console for:
```
🔔 Attempting Firebase Functions for meal_recorded notification...
✅ Notification sent via Firebase Functions
```

3. Check Firebase Functions logs:
```bash
firebase functions:log
```

## That's it! 🎉

Your notifications should now work with the modern FCM v1 API via Firebase Functions.

## Troubleshooting

**If deployment fails:**
```bash
firebase login --reauth
firebase use thanks-everyday
firebase deploy --only functions
```

**If function URL is different:**
Update the URL in `fcm_notification_service.dart` to match your deployed function.

**To test the function directly:**
```bash
curl -X POST https://us-central1-thanks-everyday.cloudfunctions.net/sendNotification \
  -H "Content-Type: application/json" \
  -d '{
    "type": "meal_recorded",
    "familyId": "test123",
    "elderlyName": "할머니",
    "timestamp": "2025-01-19T12:30:00.000Z"
  }'
```