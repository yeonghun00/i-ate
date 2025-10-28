package com.thousandemfla.thanks_everyday.elder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import com.google.firebase.firestore.FirebaseFirestore
import java.util.concurrent.atomic.AtomicBoolean

class GpsTrackingService : Service() {
    companion object {
        private const val TAG = "GpsTrackingService"
        private const val NOTIFICATION_ID = 1001 // Shared with ScreenMonitorService
        private const val CHANNEL_ID = "health_monitoring_channel" // Shared channel
        private const val UPDATE_INTERVAL_MS = 15 * 60 * 1000L // 15 minutes (matches Firebase Function schedule)
        
        private val isServiceRunning = AtomicBoolean(false)
        
        fun startService(context: Context) {
            if (!isServiceRunning.get()) {
                Log.d(TAG, "🌍 Starting GPS tracking service...")
                val intent = Intent(context, GpsTrackingService::class.java)
                ContextCompat.startForegroundService(context, intent)
            } else {
                Log.d(TAG, "🌍 GPS tracking service already running")
            }
        }
        
        fun stopService(context: Context) {
            Log.d(TAG, "🛑 Stopping GPS tracking service...")
            val intent = Intent(context, GpsTrackingService::class.java)
            context.stopService(intent)
            isServiceRunning.set(false)
        }
        
        fun isRunning(): Boolean = isServiceRunning.get()
    }
    
    private lateinit var locationManager: LocationManager
    private lateinit var notificationManager: NotificationManager
    private var updateHandler: Handler? = null
    private var updateRunnable: Runnable? = null
    private var lastLocationTime = 0L
    private var lastLocation: Location? = null
    
    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            Log.d(TAG, "📍 GPS location received: ${location.latitude}, ${location.longitude}")
            handleLocationUpdate(location)
        }
        
        override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {
            Log.d(TAG, "📍 GPS status changed: provider=$provider, status=$status")
        }
        
        override fun onProviderEnabled(provider: String) {
            Log.d(TAG, "📍 Location provider enabled: $provider")
        }
        
        override fun onProviderDisabled(provider: String) {
            Log.d(TAG, "📍 Location provider disabled: $provider")
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🌍 GPS Tracking Service created")
        
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        createNotificationChannel()
        isServiceRunning.set(true)
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🌍 GPS Tracking Service started")
        
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        startLocationTracking()
        startPeriodicUpdates()
        
        return START_STICKY // Restart service if killed
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "🌍 GPS Tracking Service destroyed")
        
        stopLocationTracking()
        stopPeriodicUpdates()
        isServiceRunning.set(false)
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "건강 안전 서비스",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "가족과 함께하는 안전한 일상을 위한 서비스입니다"
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        // Check if screen monitoring is also active to create combined notification
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
        
        val title = "가족과 함께하는 안전한 일상"
        val text = if (survivalEnabled) {
            "위치 공유와 안전 확인 서비스가 활성화되어 있습니다"
        } else {
            "위치 공유 서비스가 활성화되어 있습니다"
        }
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_save) // Friendly save/care icon instead of monitoring eye
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }
    
    private fun startLocationTracking() {
        Log.d(TAG, "📍 Starting location tracking...")
        
        if (!checkLocationPermissions()) {
            Log.e(TAG, "❌ Missing location permissions, cannot start tracking")
            return
        }
        
        try {
            // Request updates from both GPS and Network providers
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                Log.d(TAG, "📍 Requesting GPS provider updates")
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    UPDATE_INTERVAL_MS,
                    10f, // 10 meters minimum distance
                    locationListener
                )
            }
            
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                Log.d(TAG, "📍 Requesting Network provider updates")
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    UPDATE_INTERVAL_MS,
                    10f, // 10 meters minimum distance  
                    locationListener
                )
            }
            
            Log.d(TAG, "✅ Location tracking started successfully")
            
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ Security exception starting location tracking: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting location tracking: ${e.message}")
        }
    }
    
    private fun stopLocationTracking() {
        Log.d(TAG, "🛑 Stopping location tracking...")
        try {
            locationManager.removeUpdates(locationListener)
            Log.d(TAG, "✅ Location tracking stopped")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping location tracking: ${e.message}")
        }
    }
    
    private fun startPeriodicUpdates() {
        Log.d(TAG, "⏰ Starting periodic update timer")
        
        updateHandler = Handler(Looper.getMainLooper())
        updateRunnable = object : Runnable {
            override fun run() {
                Log.d(TAG, "⏰ Periodic update timer triggered")
                requestManualLocationUpdate()
                updateHandler?.postDelayed(this, UPDATE_INTERVAL_MS)
            }
        }
        
        updateHandler?.postDelayed(updateRunnable!!, UPDATE_INTERVAL_MS)
    }
    
    private fun stopPeriodicUpdates() {
        Log.d(TAG, "🛑 Stopping periodic updates")
        updateHandler?.removeCallbacks(updateRunnable!!)
        updateHandler = null
        updateRunnable = null
    }
    
    private fun requestManualLocationUpdate() {
        if (!checkLocationPermissions()) {
            Log.e(TAG, "❌ Cannot request location: Missing permissions")
            return
        }
        
        try {
            // Try to get last known location if we haven't received updates
            val timeSinceLastUpdate = System.currentTimeMillis() - lastLocationTime
            if (timeSinceLastUpdate > UPDATE_INTERVAL_MS) {
                Log.d(TAG, "📍 Requesting manual location update (last update ${timeSinceLastUpdate}ms ago)")
                
                val gpsLocation = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                val networkLocation = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                
                val bestLocation = when {
                    gpsLocation != null && networkLocation != null -> {
                        if (gpsLocation.time > networkLocation.time) gpsLocation else networkLocation
                    }
                    gpsLocation != null -> gpsLocation
                    networkLocation != null -> networkLocation
                    else -> null
                }
                
                if (bestLocation != null) {
                    Log.d(TAG, "📍 Using last known location: ${bestLocation.latitude}, ${bestLocation.longitude}")
                    handleLocationUpdate(bestLocation)
                } else {
                    Log.w(TAG, "⚠️ No location available from any provider")
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ Security exception getting location: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting manual location: ${e.message}")
        }
    }
    
    private fun handleLocationUpdate(location: Location) {
        lastLocation = location
        lastLocationTime = System.currentTimeMillis()
        
        Log.d(TAG, "📍 Processing location update:")
        Log.d(TAG, "  - Latitude: ${location.latitude}")
        Log.d(TAG, "  - Longitude: ${location.longitude}")
        Log.d(TAG, "  - Accuracy: ${location.accuracy}m")
        Log.d(TAG, "  - Provider: ${location.provider}")
        Log.d(TAG, "  - Time: ${java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date(location.time))}")
        
        // Update Firebase with location
        updateFirebaseWithLocation(location)
    }
    
    private fun updateFirebaseWithLocation(location: Location) {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            // CRITICAL FIX: Try both key variations for maximum compatibility
            var familyId = prefs.getString("flutter.family_id", null)
            if (familyId == null) {
                familyId = prefs.getString("family_id", null)
                Log.d(TAG, "🔄 Using fallback key 'family_id': $familyId")
            }
            
            if (familyId.isNullOrEmpty()) {
                Log.w(TAG, "⚠️ No family ID found, skipping Firebase update")
                return
            }
            
            val db = FirebaseFirestore.getInstance()
            // Update main document location field (optimized schema - clean data only)
            val locationUpdate = mapOf(
                "location" to mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "timestamp" to com.google.firebase.Timestamp.now(),
                    "address" to "" // Address can be added later if needed
                )
            )
            
            db.collection("families").document(familyId)
                .update(locationUpdate)
                .addOnSuccessListener {
                    Log.d(TAG, "✅ Location uploaded to Firebase successfully")
                    updateNotification("최근 업데이트: ${java.text.SimpleDateFormat("HH:mm").format(java.util.Date())}")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "❌ Failed to upload location to Firebase: ${e.message}")
                }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating Firebase: ${e.message}")
        }
    }
    
    private fun updateNotification(text: String) {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val survivalEnabled = prefs.getBoolean("flutter.survival_signal_enabled", false)
            
            val title = "가족과 함께하는 안전한 일상"
            val mainText = if (survivalEnabled) {
                "위치 공유와 안전 확인 서비스가 활성화되어 있습니다"
            } else {
                "위치 공유 서비스가 활성화되어 있습니다"
            }
            
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(mainText)
                .setSmallIcon(android.R.drawable.ic_menu_save) // Friendly save/care icon instead of monitoring eye
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setAutoCancel(false)
                .build()
            
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating notification: ${e.message}")
        }
    }
    
    private fun checkLocationPermissions(): Boolean {
        val fineLocation = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseLocation = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val backgroundLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        
        return fineLocation && coarseLocation && backgroundLocation
    }
    
    private fun getBatteryLevel(): Int {
        return try {
            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
            batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
        } catch (e: Exception) {
            -1
        }
    }
}