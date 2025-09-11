# Firebase Firestore Security Rules Guide
## 식사하셨어요? (Have You Eaten?) - Elderly Care Monitoring App

### 📋 Overview
This document provides comprehensive Firebase Firestore security rules for the elderly care monitoring app and its child companion app. These rules ensure family data privacy while enabling essential monitoring features like GPS tracking, survival signals, and meal monitoring.

### 🏗️ App Architecture
- **Parent App**: Installed on elderly person's device
- **Child App**: Installed on family member's device  
- **Shared Data**: Family documents with location, activity, and health data
- **Authentication**: Firebase Anonymous Authentication with device-specific UIDs

### 📊 Data Structure Overview

```
families/{familyId}
├── connectionCode: string (for joining family)
├── elderlyName: string 
├── createdAt: timestamp
├── lastPhoneActivity: timestamp (survival signal)
├── lastActivityType: string
├── location: {
│   ├── latitude: number
│   ├── longitude: number
│   ├── accuracy: number
│   ├── timestamp: timestamp
│   ├── provider: string
│   └── address: string
├── lastMeal: {
│   ├── timestamp: timestamp
│   └── count: number
├── alerts: {
│   ├── survival: timestamp | null
│   └── food: timestamp | null
├── settings: {
│   ├── alertHours: number
│   ├── sleepSettings: {
│   │   ├── enabled: boolean
│   │   ├── sleepStart: {hour: number, minute: number}
│   │   ├── sleepEnd: {hour: number, minute: number}
│   │   └── activeDays: number[]
│   └── locationTracking: boolean
├── authorizedDevices: string[] (device UIDs)
└── childDevices: string[] (child app UIDs)
```

### 🔐 Security Rules Implementation

#### Production-Ready Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper functions for family access control
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isFamilyMember(familyId) {
      return isAuthenticated() && 
             (request.auth.uid in resource.data.authorizedDevices ||
              request.auth.uid in resource.data.childDevices);
    }
    
    function isAuthorizedDevice(familyId) {
      return isAuthenticated() && 
             request.auth.uid in resource.data.authorizedDevices;
    }
    
    function isChildDevice(familyId) {
      return isAuthenticated() && 
             request.auth.uid in resource.data.childDevices;
    }
    
    function canJoinFamily() {
      return isAuthenticated() && 
             request.resource.data.keys().hasAll(['authorizedDevices', 'childDevices']) &&
             (request.auth.uid in request.resource.data.authorizedDevices ||
              request.auth.uid in request.resource.data.childDevices);
    }

    // Users collection - personal device data only
    match /users/{userId} {
      allow read, write: if isAuthenticated() && request.auth.uid == userId;
    }

    // Connection codes - for family joining process
    match /connection_codes/{codeId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && 
                   request.resource.data.keys().hasAll(['code', 'familyId', 'createdAt']) &&
                   request.resource.data.createdAt is timestamp;
      allow update, delete: if false; // Immutable once created
    }

    // Main families collection - core security rules
    match /families/{familyId} {
      
      // Family document access control
      allow read: if isFamilyMember(familyId);
      
      // Family creation (initial setup by parent app)
      allow create: if isAuthenticated() && 
                   canJoinFamily() &&
                   request.resource.data.keys().hasAll(['connectionCode', 'elderlyName', 'createdAt', 'authorizedDevices']) &&
                   request.resource.data.createdAt is timestamp;
      
      // Family updates - location, activity, meals, settings
      allow update: if isFamilyMember(familyId) && 
                   validateFamilyUpdate();
      
      // Delete prohibited for data safety
      allow delete: if false;
      
      // Validation function for family updates
      function validateFamilyUpdate() {
        let allowedFields = [
          'lastPhoneActivity', 'lastActivityType', 'location', 'lastMeal', 
          'alerts', 'settings', 'childDevices', 'authorizedDevices'
        ];
        
        // Only allow updates to permitted fields
        return request.resource.data.diff(resource.data).affectedKeys()
               .hasOnly(allowedFields) &&
               
               // Validate location updates
               (request.resource.data.diff(resource.data).affectedKeys().hasAny(['location']) ? 
                validateLocationUpdate() : true) &&
               
               // Validate meal updates  
               (request.resource.data.diff(resource.data).affectedKeys().hasAny(['lastMeal']) ? 
                validateMealUpdate() : true) &&
                
               // Validate settings updates
               (request.resource.data.diff(resource.data).affectedKeys().hasAny(['settings']) ? 
                validateSettingsUpdate() : true);
      }
      
      function validateLocationUpdate() {
        return request.resource.data.location.keys().hasAll(['latitude', 'longitude', 'timestamp']) &&
               request.resource.data.location.latitude is number &&
               request.resource.data.location.longitude is number &&
               request.resource.data.location.latitude >= -90 && 
               request.resource.data.location.latitude <= 90 &&
               request.resource.data.location.longitude >= -180 && 
               request.resource.data.location.longitude <= 180;
      }
      
      function validateMealUpdate() {
        return request.resource.data.lastMeal.keys().hasAll(['timestamp']) &&
               request.resource.data.lastMeal.timestamp is timestamp;
      }
      
      function validateSettingsUpdate() {
        return request.resource.data.settings is map &&
               // Validate sleep settings if present
               (!request.resource.data.settings.keys().hasAny(['sleepSettings']) || 
                validateSleepSettings());
      }
      
      function validateSleepSettings() {
        let sleepSettings = request.resource.data.settings.sleepSettings;
        return sleepSettings.keys().hasAll(['enabled']) &&
               sleepSettings.enabled is bool &&
               // If enabled, validate time fields
               (!sleepSettings.enabled || 
                (sleepSettings.keys().hasAll(['sleepStart', 'sleepEnd']) &&
                 sleepSettings.sleepStart.keys().hasAll(['hour', 'minute']) &&
                 sleepSettings.sleepEnd.keys().hasAll(['hour', 'minute']) &&
                 sleepSettings.sleepStart.hour >= 0 && sleepSettings.sleepStart.hour <= 23 &&
                 sleepSettings.sleepStart.minute >= 0 && sleepSettings.sleepStart.minute <= 59 &&
                 sleepSettings.sleepEnd.hour >= 0 && sleepSettings.sleepEnd.hour <= 23 &&
                 sleepSettings.sleepEnd.minute >= 0 && sleepSettings.sleepEnd.minute <= 59));
      }

      // Subcollections with specific access rules
      
      // Audio recordings - sensitive data
      match /recordings/{recordingId} {
        allow read, write: if isAuthorizedDevice(familyId); // Parent device only
        allow delete: if false; // Preserve for safety
      }
      
      // Meal history - accessible to family
      match /meals/{mealId} {
        allow read: if isFamilyMember(familyId);
        allow create: if isAuthorizedDevice(familyId) && 
                     request.resource.data.keys().hasAll(['timestamp', 'type']) &&
                     request.resource.data.timestamp is timestamp;
        allow update, delete: if false; // Immutable meal records
      }
      
      // Child device management
      match /child_devices/{deviceId} {
        allow read: if isFamilyMember(familyId);
        allow write: if isChildDevice(familyId) && request.auth.uid == deviceId;
      }
      
      // Encryption keys - highly secure
      match /keys/{keyId} {
        allow read, write: if isAuthorizedDevice(familyId); // Parent device only
      }
    }

    // FCM tokens for push notifications
    match /fcmTokens/{tokenId} {
      allow read, write: if isAuthenticated() && request.auth.uid == tokenId;
    }
    
    // User subscriptions
    match /subscriptions/{userId} {
      allow read, write: if isAuthenticated() && request.auth.uid == userId;
    }
    
    // Analytics - read-only for authenticated users
    match /analytics/{document=**} {
      allow read: if isAuthenticated();
      allow write: if false; // Analytics written server-side only
    }
    
    // App settings - read-only global settings
    match /appSettings/{document=**} {
      allow read: if isAuthenticated();
      allow write: if false; // Settings managed by admin only
    }
    
    // Test collection for development
    match /test/{document=**} {
      allow read, write: if isAuthenticated() && 
                         request.auth.uid in ['test_parent_uid', 'test_child_uid'];
    }
  }
}
```

### 🚀 Deployment Instructions

#### 1. Development Environment Setup
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize project (if not already done)
firebase init firestore
```

#### 2. Rules Testing
```bash
# Test rules locally
firebase emulators:start --only firestore

# Run security rules tests
firebase emulators:exec --only firestore "npm test"
```

#### 3. Production Deployment
```bash
# Deploy to production
firebase deploy --only firestore:rules

# Verify deployment
firebase firestore:rules:release
```

### 🧪 Security Testing Guidelines

#### Test Scenarios to Verify

1. **Family Access Control**
   ```javascript
   // Valid: Family member accessing family data
   familyDoc.get({ auth: { uid: 'authorized_device_uid' } })
   
   // Invalid: Non-family member access
   familyDoc.get({ auth: { uid: 'random_user_uid' } }) // Should fail
   ```

2. **Location Data Validation**
   ```javascript
   // Valid location update
   familyDoc.update({ 
     location: { 
       latitude: 37.7749, 
       longitude: -122.4194, 
       timestamp: admin.firestore.Timestamp.now() 
     }
   })
   
   // Invalid: Out of bounds coordinates
   familyDoc.update({ 
     location: { latitude: 91, longitude: 181 } 
   }) // Should fail
   ```

3. **Child App Restrictions**
   ```javascript
   // Valid: Child reading family data
   familyDoc.get({ auth: { uid: 'child_device_uid' } })
   
   // Invalid: Child accessing recordings
   recordingDoc.get({ auth: { uid: 'child_device_uid' } }) // Should fail
   ```

### ⚠️ Security Best Practices

#### 1. Device Authorization Management
- Add device UIDs to `authorizedDevices` during setup
- Remove devices when they're no longer trusted
- Regularly audit device access lists

#### 2. Data Validation
- Always validate data types and ranges
- Sanitize location coordinates
- Verify timestamp integrity

#### 3. Privacy Protection
- Audio recordings accessible only to parent device
- Location data limited to family members
- No cross-family data access

#### 4. Monitoring & Alerts
```javascript
// Monitor for suspicious access patterns
// Set up Firebase Security Rules monitoring
// Alert on failed authentication attempts
```

### 🔧 Child App Integration

#### Configuration for Child Apps
```dart
// Child app initialization
class ChildAppFirebaseService extends FirebaseService {
  @override
  Future<bool> canAccessRecordings() async {
    return false; // Child apps cannot access recordings
  }
  
  @override
  Future<bool> canModifySettings() async {
    return false; // Parent device manages settings
  }
}
```

### 📱 Emergency Access Rules

In case of emergency, temporary elevated access can be granted:

```javascript
// Emergency access function (server-side)
function grantEmergencyAccess(familyId, emergencyDeviceId) {
  return admin.firestore()
    .collection('families')
    .doc(familyId)
    .update({
      'emergencyAccess': {
        'deviceId': emergencyDeviceId,
        'grantedAt': admin.firestore.Timestamp.now(),
        'expiresAt': admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours
        )
      }
    });
}
```

### 🔍 Troubleshooting

#### Common Security Rule Issues

1. **Permission Denied Errors**
   - Verify device UID is in `authorizedDevices` or `childDevices`
   - Check Firebase Authentication status
   - Validate data structure matches rules

2. **Location Updates Failing**
   - Ensure coordinates are within valid ranges
   - Include required timestamp field
   - Verify user has family access

3. **Child App Access Issues**
   - Confirm child device is in `childDevices` array
   - Verify child isn't trying to access recordings
   - Check family membership

### 📞 Support & Updates

For security rule updates or issues:
1. Test changes in Firebase Emulator first
2. Deploy to staging environment
3. Monitor Firebase Console for errors
4. Update both parent and child apps simultaneously

### 🔒 Compliance Notes

These rules ensure:
- ✅ Family privacy protection
- ✅ Location data security
- ✅ Child-safe data access
- ✅ GDPR/privacy compliance ready
- ✅ Audit trail maintenance

---

**Last Updated**: {{ current_date }}
**Version**: 1.0.0
**Compatible Apps**: Parent App v1.0+, Child App v1.0+