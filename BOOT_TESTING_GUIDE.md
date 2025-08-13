# CRITICAL BOOT FAILURE TESTING GUIDE

## 🚨 ROOT CAUSE IDENTIFIED: SharedPreferences Key Mismatch

**THE PROBLEM**: Flutter saves `family_id` but Android reads `flutter.family_id`
**THE FIX**: Check both key variations in all Android code

## 📱 DEFINITIVE TEST METHODS

### **TEST #1: Verify SharedPreferences Key Consistency**

**Before Testing:**
1. Open the app and set up family monitoring
2. Verify GPS tracking and survival signal work normally
3. Check that Firebase updates are working

**Test Commands:**
```bash
# Check Flutter SharedPreferences
adb shell run-as com.thousandemfla.thanks_everyday cat /data/data/com.thousandemfla.thanks_everyday/shared_prefs/FlutterSharedPreferences.xml

# Look for these keys:
# - family_id (Flutter saves this)  
# - flutter.family_id (Android tries to read this)
```

**Expected Results:**
- Before fix: Only `family_id` key exists, `flutter.family_id` is missing
- After fix: Both keys work, fallback logic retrieves the correct value

### **TEST #2: Boot Receiver Verification**

**Test Commands:**
```bash
# Clear logs and reboot
adb logcat -c
adb reboot

# After reboot, check for BootReceiver logs
adb logcat | grep "BootReceiver"
```

**Expected Log Messages:**
```
🚀🚀🚀 BOOT RECEIVER TRIGGERED: android.intent.action.BOOT_COMPLETED
📱📱📱 DEVICE REBOOT DETECTED - STARTING RESTORATION
🔄 Using fallback key 'family_id': [FAMILY_ID_VALUE]
📱 Boot settings: survival=true, location=true, family=[FAMILY_ID]
```

**CRITICAL**: If you see `family=null`, the SharedPreferences fix didn't work.

### **TEST #3: AlarmManager Scheduling Verification**

**Test Commands:**
```bash
# Check alarm scheduling logs
adb logcat | grep "AlarmUpdateReceiver"
```

**Expected Log Messages:**
```
🚀 scheduleAlarms() called from BootReceiver
🌍 Scheduling GPS location alarm...
💓 Scheduling survival signal alarm...
✅ GPS alarm scheduled successfully for 2 minutes interval
✅ Survival signal alarm scheduled successfully for 2 minutes interval
```

**CRITICAL**: If alarms aren't scheduled, check system readiness logs.

### **TEST #4: Foreground Service Startup Verification**

**Test Commands:**
```bash
# Check ScreenMonitorService startup
adb logcat | grep "ScreenMonitorService"

# Check if notification appears
adb shell dumpsys notification | grep "안전 모니터링"
```

**Expected Results:**
- **Android 11 and below**: Service starts successfully, notification appears
- **Android 12+**: May fail with `ForegroundServiceStartNotAllowedException`

**For Android 12+ failure:**
```
💡 ANDROID 12+ RESTRICTION: Foreground services cannot start from boot
💡 Solution: User must open app manually after reboot
```

### **TEST #5: Firebase Connectivity Test**

**Test Commands:**
```bash
# Wait 2-3 minutes after reboot, then check Firebase update logs
adb logcat | grep "Firebase update"
```

**Expected Results:**
- **Success**: `✅ GPS Firebase update successful - Lat: X, Lng: Y`
- **Network Issues**: `🔄 GPS: Network/Firebase not ready, scheduling retry in 30 seconds...`
- **Family ID Issues**: `❌ No family ID found for GPS update`

## 🔧 STEP-BY-STEP DEBUGGING STRATEGY

### **Phase 1: Isolate SharedPreferences Issue**
1. Reboot device
2. Immediately check logs for family_id retrieval
3. If `family=null`, the key mismatch is confirmed
4. Apply the SharedPreferences fix
5. Test again

### **Phase 2: Test Alarm Scheduling**
1. After confirming family_id works, check alarm scheduling
2. Look for "System ready for alarm scheduling" logs
3. If system isn't ready, alarms will retry in 30 seconds
4. Verify both GPS and survival alarms are scheduled

### **Phase 3: Test Service Startup**
1. Check if ScreenMonitorService starts successfully
2. On Android 12+, service may fail - this is expected
3. User needs to open app manually on Android 12+ after reboot
4. Verify notification appears after service starts

### **Phase 4: Test Firebase Updates**
1. Wait 2 minutes for first GPS alarm to fire
2. Check Firebase update logs
3. If network isn't ready, updates will retry in 30 seconds
4. Verify timestamps are updated in Firebase console

## ⚠️ KNOWN ANDROID 12+ LIMITATIONS

### **Foreground Service Restrictions**
- **Problem**: Android 12+ blocks foreground service startup from BootReceiver
- **Symptom**: `ForegroundServiceStartNotAllowedException` in logs
- **Solution**: User must open app once after reboot
- **Workaround**: AlarmManager still works, so GPS/survival tracking continues

### **Exact Alarm Restrictions**
- **Problem**: `SCHEDULE_EXACT_ALARM` permission may be required
- **Solution**: App automatically falls back to inexact alarms
- **Impact**: Alarms may fire slightly less precisely but still work

## 🎯 SUCCESS CRITERIA

### **Complete Success** (GPS + Survival working after reboot):
1. ✅ BootReceiver triggers and finds family_id
2. ✅ GPS and survival alarms are scheduled
3. ✅ ScreenMonitorService starts (Android 11-) or user opens app (Android 12+)
4. ✅ Firebase receives location and survival updates within 2-3 minutes
5. ✅ Persistent notification shows "안전 모니터링 활성"

### **Partial Success** (Alarms work but service doesn't):
1. ✅ BootReceiver triggers and finds family_id  
2. ✅ GPS and survival alarms are scheduled
3. ❌ ScreenMonitorService fails to start (Android 12+ restriction)
4. ✅ Firebase receives updates from AlarmManager
5. ❌ No persistent notification until user opens app

### **Failure** (Nothing works after reboot):
1. ❌ family_id is null - SharedPreferences key mismatch
2. ❌ No alarms are scheduled
3. ❌ No Firebase updates occur
4. ❌ Complete silence in logs after boot

## 📊 VERIFICATION COMMANDS

```bash
# Complete test suite
adb logcat -c && adb reboot

# Wait 1 minute after reboot, then run:
echo "=== BOOT RECEIVER TEST ==="
adb logcat -d | grep "BootReceiver" | tail -20

echo "=== FAMILY ID TEST ==="  
adb logcat -d | grep "family_id" | tail -10

echo "=== ALARM SCHEDULING TEST ==="
adb logcat -d | grep "alarm scheduled" | tail -10

echo "=== FIREBASE UPDATE TEST ==="
adb logcat -d | grep "Firebase update" | tail -10

echo "=== NOTIFICATION TEST ==="
adb shell dumpsys notification | grep -A 5 "안전 모니터링"
```

This testing approach will definitively identify whether the root cause has been resolved.