const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Helper function to get all child app FCM tokens for a family
async function getFamilyMemberTokens(familyId) {
  try {
    const familyDoc = await admin.firestore()
      .collection('families')
      .doc(familyId)
      .get();
    
    if (!familyDoc.exists) {
      console.log('Family not found:', familyId);
      return [];
    }
    
    const familyData = familyDoc.data();
    const connectionCode = familyData?.connectionCode;
    
    if (!connectionCode) {
      console.log('No connection code found for family:', familyId);
      return [];
    }
    
    console.log('Looking for child apps with connection code:', connectionCode);
    
    // Method 1: Try to find tokens via users collection with familyCodes
    const tokens = [];
    
    try {
      const usersSnapshot = await admin.firestore()
        .collection('users')
        .where('familyCodes', 'array-contains', connectionCode)
        .get();
      
      console.log('Found users with familyCodes:', usersSnapshot.size);
      
      usersSnapshot.forEach(userDoc => {
        const userData = userDoc.data();
        const fcmToken = userData.fcmToken;
        if (fcmToken) {
          tokens.push(fcmToken);
          console.log('Added FCM token for user:', userDoc.id);
        }
      });
    } catch (error) {
      console.log('familyCodes method failed, trying alternative approach:', error.message);
    }
    
    // Method 2: Check child_devices subcollection (alternative approach)
    if (tokens.length === 0) {
      try {
        const devicesSnapshot = await admin.firestore()
          .collection('families')
          .doc(familyId)
          .collection('child_devices')
          .where('is_active', '==', true)
          .get();
        
        console.log('Found child devices:', devicesSnapshot.size);
        
        devicesSnapshot.forEach(deviceDoc => {
          const deviceData = deviceDoc.data();
          const fcmToken = deviceData.fcm_token;
          if (fcmToken) {
            tokens.push(fcmToken);
            console.log('Added FCM token from child_devices:', deviceDoc.id);
          }
        });
      } catch (error) {
        console.log('child_devices method failed:', error.message);
      }
    }
    
    // Method 3: Direct lookup in family document (if tokens stored there)
    if (tokens.length === 0) {
      const directTokens = familyData?.childAppTokens || [];
      tokens.push(...directTokens);
      console.log('Added direct tokens from family doc:', directTokens.length);
    }
    
    console.log('Total FCM tokens found:', tokens.length);
    return tokens;
  } catch (error) {
    console.error('Error getting family member tokens:', error);
    return [];
  }
}

// Updated sendNotification function for direct token messaging
exports.sendNotification = functions.runWith({
  invoker: 'public'
}).https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.status(200).send('');
    return;
  }
  
  try {
    console.log('🔔 FCM Function received:', req.body);
    
    const { type, familyId, elderlyName, timestamp, hoursInactive, hoursWithoutFood } = req.body;
    
    if (!type || !familyId || !elderlyName) {
      console.error('❌ Missing required fields');
      res.status(400).json({ success: false, error: 'Missing required fields' });
      return;
    }
    
    // Get all child app FCM tokens for this family
    const tokens = await getFamilyMemberTokens(familyId);
    
    if (tokens.length === 0) {
      console.log('⚠️ No child app tokens found for family:', familyId);
      res.status(200).json({ 
        success: true, 
        message: 'No child apps connected to receive notifications',
        familyId: familyId,
        type: type
      });
      return;
    }
    
    let notification, data;
    
    if (type === 'meal_recorded') {
      const date = new Date(timestamp);
      const timeString = date.toLocaleTimeString('ko-KR', { 
        hour: '2-digit', 
        minute: '2-digit',
        hour12: false
      });
      
      notification = {
        title: `${elderlyName}님이 식사하셨어요`,
        body: `오늘 ${timeString}에 식사했습니다`,
      };
      
      data = {
        type: 'meal_recorded',
        elderlyName: elderlyName,
        timestamp: timestamp,
        familyId: familyId,
      };
    } else if (type === 'survival_alert') {
      const hours = hoursInactive || 12;
      
      notification = {
        title: `⚠️ ${elderlyName} 안전 알림`,
        body: `${hours}시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요.`,
      };
      
      data = {
        type: 'survival_alert',
        elderlyName: elderlyName,
        hoursInactive: hours.toString(),
        familyId: familyId,
        timestamp: timestamp || new Date().toISOString(),
      };
    } else if (type === 'food_alert') {
      const foodHours = hoursWithoutFood || 8;
      
      notification = {
        title: `🍽️ ${elderlyName} 식사 알림`,
        body: `${foodHours}시간 이상 식사하지 않았습니다. 확인해주세요.`,
      };
      
      data = {
        type: 'food_alert',
        elderlyName: elderlyName,
        hoursWithoutFood: foodHours.toString(),
        familyId: familyId,
        timestamp: timestamp || new Date().toISOString(),
      };
    } else {
      res.status(400).json({ success: false, error: 'Invalid notification type' });
      return;
    }
    
    // Send to all child app tokens individually
    console.log(`📤 Sending ${type} notification to ${tokens.length} child app(s)`);
    
    const promises = tokens.map(async (token) => {
      try {
        const message = {
          token: token,
          notification: notification,
          data: data,
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
              channelId: 'high_importance_channel',
            },
          },
        };
        
        const result = await admin.messaging().send(message);
        console.log('✅ Notification sent to token:', token.substring(0, 20) + '...', 'MessageID:', result);
        return { success: true, messageId: result, token: token.substring(0, 20) + '...' };
      } catch (error) {
        console.error('❌ Failed to send to token:', token.substring(0, 20) + '...', error.message);
        return { success: false, error: error.message, token: token.substring(0, 20) + '...' };
      }
    });
    
    const results = await Promise.all(promises);
    const successCount = results.filter(r => r.success).length;
    
    console.log(`✅ Notifications sent: ${successCount}/${tokens.length}`);
    
    res.status(200).json({ 
      success: true, 
      sentTo: successCount,
      totalTokens: tokens.length,
      familyId: familyId,
      type: type,
      results: results
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message
    });
  }
});

// Helper function to check if current time is within sleep period
function isCurrentlySleepTime(settings) {
  if (!settings || !settings.sleepExclusionEnabled) {
    return false;
  }

  const now = new Date();
  const sleepStartHour = settings.sleepStartHour || 22;
  const sleepStartMinute = settings.sleepStartMinute || 0;
  const sleepEndHour = settings.sleepEndHour || 6;
  const sleepEndMinute = settings.sleepEndMinute || 0;
  const sleepActiveDays = settings.sleepActiveDays || [1, 2, 3, 4, 5, 6, 7];

  // Check if today is an active sleep day
  const dayOfWeek = now.getDay(); // 0 = Sunday, 6 = Saturday
  const mondayBased = dayOfWeek === 0 ? 7 : dayOfWeek; // Convert to Monday=1, Sunday=7

  if (!sleepActiveDays.includes(mondayBased)) {
    return false;
  }

  // Current time in minutes since midnight
  const currentMinutes = now.getHours() * 60 + now.getMinutes();
  const sleepStartMinutes = sleepStartHour * 60 + sleepStartMinute;
  const sleepEndMinutes = sleepEndHour * 60 + sleepEndMinute;

  // Check if in sleep period
  if (sleepStartMinutes > sleepEndMinutes) {
    // Overnight period (e.g., 22:00 - 06:00)
    return currentMinutes >= sleepStartMinutes || currentMinutes <= sleepEndMinutes;
  } else {
    // Same-day period (e.g., 14:00 - 16:00)
    return currentMinutes >= sleepStartMinutes && currentMinutes <= sleepEndMinutes;
  }
}

// Monitor all families for survival alerts - RUNS EVERY 15 MINUTES ON GOOGLE'S SERVERS
exports.checkFamilySurvival = functions.pubsub
  .schedule('every 15 minutes')
  .timeZone('Asia/Seoul')
  .onRun(async (context) => {
    console.log('🔍 Checking family survival status every 15 minutes...');
    
    try {
      const familiesSnapshot = await admin.firestore()
        .collection('families')
        .where('settings.survivalSignalEnabled', '==', true)
        .get();
      
      console.log(`📊 Found ${familiesSnapshot.size} families with survival monitoring enabled`);
      
      const now = admin.firestore.Timestamp.now();
      const promises = [];
      
      familiesSnapshot.forEach(familyDoc => {
        const familyData = familyDoc.data();
        const familyId = familyDoc.id;
        const elderlyName = familyData.elderlyName || 'Unknown';
        const lastPhoneActivity = familyData.lastPhoneActivity;
        const alertHours = familyData.settings?.alertHours || 12;
        
        if (!lastPhoneActivity) {
          console.log(`⚠️ Family ${familyId} (${elderlyName}) has no lastPhoneActivity data`);
          return;
        }
        
        // Calculate hours since last phone activity
        const diffMs = now.toMillis() - lastPhoneActivity.toMillis();
        const diffHours = diffMs / (1000 * 60 * 60);
        
        console.log(`📱 Family ${familyId} (${elderlyName}): ${diffHours.toFixed(1)} hours since last activity (threshold: ${alertHours}h)`);
        
        // Also check location data for additional survival indicators
        const location = familyData.location;
        let locationStatus = '';
        if (location && location.timestamp) {
          const locationDiffMs = now.toMillis() - location.timestamp.toMillis();
          const locationHours = locationDiffMs / (1000 * 60 * 60);
          locationStatus = ` | Location: ${locationHours.toFixed(1)}h ago`;
          
          // Could add location-based alerts here
          if (locationHours > 24) {
            console.log(`⚠️ ${elderlyName} location not updated for ${locationHours.toFixed(1)} hours`);
          }
        }
        
        console.log(`📊 ${elderlyName} status: Phone activity: ${diffHours.toFixed(1)}h ago${locationStatus}`);
        
        if (diffHours > alertHours) {
          console.log(`🚨 SURVIVAL ALERT: ${elderlyName} inactive for ${diffHours.toFixed(1)} hours`);

          // Check if currently in sleep time
          if (isCurrentlySleepTime(familyData.settings)) {
            const sleepStart = familyData.settings?.sleepStartHour || 22;
            const sleepEnd = familyData.settings?.sleepEndHour || 6;
            console.log(`😴 ${elderlyName} is in sleep period (${sleepStart}:00-${sleepEnd}:00) - skipping alert`);
            return;
          }

          // Check if alert already active to avoid spam
          const currentAlert = familyData.survivalAlert;
          if (currentAlert?.isActive) {
            console.log(`📢 Alert already active for ${elderlyName}, skipping`);
            return;
          }
          
          // Update survival alert status
          const alertPromise = admin.firestore()
            .collection('families')
            .doc(familyId)
            .update({
              'survivalAlert': {
                isActive: true,
                timestamp: now,
                elderlyName: elderlyName,
                message: `${Math.floor(diffHours)}시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요.`,
                locationData: familyData.location || null,
                hoursInactive: Math.floor(diffHours)
              }
            })
            .then(() => {
              console.log(`✅ Survival alert status updated for ${elderlyName}`);
              
              // Send FCM notification
              return sendSurvivalNotification(familyId, elderlyName, Math.floor(diffHours));
            })
            .catch(error => {
              console.error(`❌ Failed to update survival alert for ${elderlyName}:`, error);
            });
          
          promises.push(alertPromise);
        } else {
          console.log(`✅ ${elderlyName} is active (${diffHours.toFixed(1)}h ago)`);
          
          // Clear any existing alert if person is now active
          if (familyData.survivalAlert?.isActive) {
            console.log(`🔄 Clearing previous alert for ${elderlyName}`);
            const clearPromise = admin.firestore()
              .collection('families')
              .doc(familyId)
              .update({
                'survivalAlert.isActive': false,
                'survivalAlert.clearedAt': now
              });
            promises.push(clearPromise);
          }
        }
      });
      
      await Promise.all(promises);
      console.log('✅ Family survival check completed');
      
    } catch (error) {
      console.error('❌ Error checking family survival:', error);
    }
  });

// Helper function to send survival alert notifications
async function sendSurvivalNotification(familyId, elderlyName, hoursInactive) {
  try {
    console.log(`📢 Sending survival notification for ${elderlyName}`);
    
    // Get family member tokens
    const tokens = await getFamilyMemberTokens(familyId);
    
    if (tokens.length === 0) {
      console.log(`⚠️ No child app tokens found for family: ${familyId}`);
      return;
    }
    
    const notification = {
      title: `⚠️ ${elderlyName} 안전 알림`,
      body: `${hoursInactive}시간 이상 휴대폰 사용이 없습니다. 안부를 확인해주세요.`,
    };
    
    const data = {
      type: 'survival_alert',
      elderlyName: elderlyName,
      hoursInactive: hoursInactive.toString(),
      familyId: familyId,
      timestamp: new Date().toISOString(),
    };
    
    const promises = tokens.map(async (token) => {
      try {
        const message = {
          token: token,
          notification: notification,
          data: data,
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
              channelId: 'high_importance_channel',
            },
          },
        };
        
        const result = await admin.messaging().send(message);
        console.log('✅ Survival alert sent to token:', token.substring(0, 20) + '...', 'MessageID:', result);
        return { success: true, messageId: result };
      } catch (error) {
        console.error('❌ Failed to send survival alert to token:', token.substring(0, 20) + '...', error.message);
        return { success: false, error: error.message };
      }
    });
    
    const results = await Promise.all(promises);
    const successCount = results.filter(r => r.success).length;
    
    console.log(`✅ Survival alerts sent: ${successCount}/${tokens.length}`);
    return results;
    
  } catch (error) {
    console.error('❌ Error sending survival notification:', error);
    throw error;
  }
}