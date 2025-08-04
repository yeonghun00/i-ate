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
    
    const members = familyDoc.data()?.members || [];
    console.log('Found family members:', members);
    
    const tokens = [];
    for (const userId of members) {
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(userId)
        .get();
      
      if (userDoc.exists) {
        const fcmToken = userDoc.data()?.fcmToken;
        if (fcmToken) {
          tokens.push(fcmToken);
          console.log('Added FCM token for user:', userId);
        }
      }
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

// Monitor all families for survival alerts - RUNS EVERY 2 MINUTES ON GOOGLE'S SERVERS (FOR TESTING)
exports.checkFamilySurvival = functions.pubsub
  .schedule('every 2 minutes')
  .timeZone('Asia/Seoul')
  .onRun(async (context) => {
    console.log('🔍 Checking family survival status every 2 minutes for testing...');
    
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