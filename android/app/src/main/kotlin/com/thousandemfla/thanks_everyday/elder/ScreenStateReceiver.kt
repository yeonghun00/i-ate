package com.thousandemfla.thanks_everyday.elder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

class ScreenStateReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "ScreenStateReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "📱📱📱 SCREEN STATE CHANGE DETECTED: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> {
                Log.d(TAG, "📱 Screen turned ON (but may still be locked)")
                // Screen on doesn't mean user is active (could still be locked)
                // We only update on USER_PRESENT for cost efficiency
            }
            Intent.ACTION_USER_PRESENT -> {
                Log.d(TAG, "🔓🔓🔓 USER UNLOCKED PHONE - IMMEDIATE FIREBASE UPDATE!")
                Log.d(TAG, "⚡ This catches brief usage like checking time!")
                updateLastPhoneActivity(context)
            }
            else -> {
                Log.w(TAG, "⚠️ Unknown screen action received: ${intent.action}")
            }
        }
    }
    
    private fun updateLastPhoneActivity(context: Context) {
        try {
            Log.d(TAG, "⚡⚡⚡ PROCESSING IMMEDIATE UNLOCK DETECTION")
            
            // Check if monitoring is enabled
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            
            Log.d(TAG, "🔍 Survival signal monitoring enabled: $isEnabled")
            
            if (!isEnabled) {
                Log.d(TAG, "❌ Monitoring disabled - skipping immediate update")
                return
            }
            
            // Get family info
            val familyId = prefs.getString("flutter.family_id", null)
            if (familyId == null) {
                Log.w(TAG, "⚠️ No family ID found - cannot update Firebase")
                return
            }
            
            Log.d(TAG, "🚀 Updating Firebase immediately for family: $familyId")
            Log.d(TAG, "💡 This update happens INSTANTLY when user unlocks (even for 2 seconds!)")
            
            // Update Firebase with real phone activity
            val firestore = FirebaseFirestore.getInstance()
            firestore.collection("families")
                .document(familyId)
                .update("lastPhoneActivity", FieldValue.serverTimestamp())
                .addOnSuccessListener {
                    Log.d(TAG, "✅✅✅ IMMEDIATE UPDATE SUCCESS - Firebase shows user was active NOW!")
                    Log.d(TAG, "🎯 Brief usage detected and recorded (like checking time)")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "❌ Immediate Firebase update failed: ${e.message}")
                }
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in immediate unlock detection: ${e.message}")
        }
    }
}