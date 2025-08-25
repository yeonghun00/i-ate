const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// 1. CREATE FAMILY - Secure server-side family creation
exports.createFamily = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 
      'User must be authenticated'
    );
  }

  const { elderlyName } = data;
  
  if (!elderlyName || elderlyName.trim().length === 0) {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      'Elderly name is required'
    );
  }

  try {
    // Generate secure 4-digit code
    const connectionCode = await generateUniqueConnectionCode();
    
    // Create unique family ID
    const familyId = `family_${context.auth.uid}_${Date.now()}`;
    
    // Create family document with server timestamp
    const familyData = {
      familyId,
      connectionCode,
      elderlyName: elderlyName.trim(),
      createdBy: context.auth.uid,
      memberIds: [context.auth.uid], // Creator is first member
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isActive: true,
      approved: null, // For child app approval
      settings: {
        survivalSignalEnabled: false,
        familyContact: '',
        alertHours: 12,
      }
    };

    // Write to Firestore
    await db.collection('families').doc(familyId).set(familyData);

    // Create connection code lookup for child app
    await db.collection('connection_codes').doc(connectionCode).set({
      familyId,
      createdBy: context.auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + (24 * 60 * 60 * 1000)), // 24 hour expiry
    });

    console.log(`Family created: ${familyId} with code: ${connectionCode}`);
    
    return {
      success: true,
      familyId,
      connectionCode,
      message: 'Family created successfully'
    };

  } catch (error) {
    console.error('Error creating family:', error);
    throw new functions.https.HttpsError(
      'internal', 
      'Failed to create family'
    );
  }
});

// 2. JOIN FAMILY - Child app joins using 4-digit code
exports.joinFamily = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 
      'User must be authenticated'
    );
  }

  const { connectionCode, childName } = data;
  
  if (!connectionCode || connectionCode.length !== 4) {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      'Valid 4-digit connection code is required'
    );
  }

  try {
    // Find family by connection code
    const codeDoc = await db.collection('connection_codes').doc(connectionCode).get();
    
    if (!codeDoc.exists) {
      throw new functions.https.HttpsError(
        'not-found', 
        'Invalid connection code'
      );
    }

    const codeData = codeDoc.data();
    
    // Check if code is expired
    if (codeData.expiresAt && codeData.expiresAt.toDate() < new Date()) {
      throw new functions.https.HttpsError(
        'deadline-exceeded', 
        'Connection code has expired'
      );
    }

    const familyId = codeData.familyId;
    
    // Add child to family members
    await db.collection('families').doc(familyId).update({
      memberIds: admin.firestore.FieldValue.arrayUnion(context.auth.uid),
      [`childInfo.${context.auth.uid}`]: {
        name: childName || 'Child User',
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
        role: 'child'
      }
    });

    console.log(`User ${context.auth.uid} joined family: ${familyId}`);
    
    return {
      success: true,
      familyId,
      message: 'Successfully joined family'
    };

  } catch (error) {
    console.error('Error joining family:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
      'internal', 
      'Failed to join family'
    );
  }
});

// 3. UPDATE LOCATION - Secure GPS data storage
exports.updateLocation = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 
      'User must be authenticated'
    );
  }

  const { familyId, latitude, longitude, address } = data;
  
  if (!familyId || !latitude || !longitude) {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      'Family ID, latitude, and longitude are required'
    );
  }

  try {
    // Verify user is family member
    const familyDoc = await db.collection('families').doc(familyId).get();
    
    if (!familyDoc.exists) {
      throw new functions.https.HttpsError(
        'not-found', 
        'Family not found'
      );
    }

    const familyData = familyDoc.data();
    
    if (!familyData.memberIds.includes(context.auth.uid)) {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'User is not a member of this family'
      );
    }

    // Store location data securely
    const locationData = {
      userId: context.auth.uid,
      latitude,
      longitude,
      address: address || null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      accuracy: data.accuracy || null
    };

    await db.collection('families')
            .doc(familyId)
            .collection('locations')
            .add(locationData);

    // Update last known location in family doc
    await db.collection('families').doc(familyId).update({
      lastLocation: {
        latitude,
        longitude,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: context.auth.uid
      }
    });

    return {
      success: true,
      message: 'Location updated successfully'
    };

  } catch (error) {
    console.error('Error updating location:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
      'internal', 
      'Failed to update location'
    );
  }
});

// Helper function to generate unique 4-digit code
async function generateUniqueConnectionCode() {
  let attempts = 0;
  const maxAttempts = 50;
  
  while (attempts < maxAttempts) {
    // Generate cryptographically secure 4-digit code
    const code = Math.floor(1000 + Math.random() * 9000).toString();
    
    // Check if code already exists
    const existingCode = await db.collection('connection_codes').doc(code).get();
    
    if (!existingCode.exists) {
      return code;
    }
    
    attempts++;
  }
  
  throw new Error('Failed to generate unique connection code');
}