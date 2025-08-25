// Android Kotlin integration with Cloud Functions
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.httpsCallable
import kotlinx.coroutines.tasks.await
import android.util.Log

class SecureFamilyService {
    private val functions = FirebaseFunctions.getInstance()
    
    // 1. CREATE FAMILY (Parent App)
    suspend fun createFamily(elderlyName: String): Result<FamilyCreationResult> {
        return try {
            val data = hashMapOf(
                "elderlyName" to elderlyName
            )
            
            val result = functions
                .getHttpsCallable("createFamily")
                .call(data)
                .await()
            
            val resultData = result.data as Map<String, Any>
            val familyId = resultData["familyId"] as String
            val connectionCode = resultData["connectionCode"] as String
            
            Log.d("FamilyService", "Family created: $familyId with code: $connectionCode")
            
            Result.success(
                FamilyCreationResult(
                    familyId = familyId,
                    connectionCode = connectionCode,
                    success = true
                )
            )
        } catch (e: Exception) {
            Log.e("FamilyService", "Failed to create family", e)
            Result.failure(e)
        }
    }
    
    // 2. JOIN FAMILY (Child App)
    suspend fun joinFamily(connectionCode: String, childName: String): Result<String> {
        return try {
            val data = hashMapOf(
                "connectionCode" to connectionCode,
                "childName" to childName
            )
            
            val result = functions
                .getHttpsCallable("joinFamily")
                .call(data)
                .await()
            
            val resultData = result.data as Map<String, Any>
            val familyId = resultData["familyId"] as String
            
            Log.d("FamilyService", "Joined family: $familyId")
            Result.success(familyId)
            
        } catch (e: Exception) {
            Log.e("FamilyService", "Failed to join family", e)
            Result.failure(e)
        }
    }
    
    // 3. UPDATE LOCATION (Parent App) 
    suspend fun updateLocation(
        familyId: String,
        latitude: Double,
        longitude: Double,
        address: String? = null
    ): Result<Boolean> {
        return try {
            val data = hashMapOf(
                "familyId" to familyId,
                "latitude" to latitude,
                "longitude" to longitude
            )
            
            address?.let { data["address"] = it }
            
            val result = functions
                .getHttpsCallable("updateLocation")
                .call(data)
                .await()
            
            Log.d("FamilyService", "Location updated successfully")
            Result.success(true)
            
        } catch (e: Exception) {
            Log.e("FamilyService", "Failed to update location", e)
            Result.failure(e)
        }
    }
    
    // 4. UPDATE SURVIVAL SIGNAL (Parent App)
    suspend fun updateSurvivalSignal(
        familyId: String,
        isActive: Boolean,
        lastActiveTime: Long
    ): Result<Boolean> {
        return try {
            val data = hashMapOf(
                "familyId" to familyId,
                "isActive" to isActive,
                "lastActiveTime" to lastActiveTime,
                "deviceInfo" to getDeviceInfo()
            )
            
            val result = functions
                .getHttpsCallable("updateSurvivalSignal")
                .call(data)
                .await()
            
            Log.d("FamilyService", "Survival signal updated")
            Result.success(true)
            
        } catch (e: Exception) {
            Log.e("FamilyService", "Failed to update survival signal", e)
            Result.failure(e)
        }
    }
    
    private fun getDeviceInfo(): Map<String, Any> {
        return hashMapOf(
            "model" to android.os.Build.MODEL,
            "manufacturer" to android.os.Build.MANUFACTURER,
            "androidVersion" to android.os.Build.VERSION.RELEASE
        )
    }
}

// Data classes for results
data class FamilyCreationResult(
    val familyId: String,
    val connectionCode: String,
    val success: Boolean
)

// Usage in your Activity/Fragment:
class MainActivity : AppCompatActivity() {
    private val familyService = SecureFamilyService()
    
    private fun createFamily() {
        lifecycleScope.launch {
            val result = familyService.createFamily("할머니")
            
            result.fold(
                onSuccess = { familyResult ->
                    // Show success UI with connection code
                    showConnectionCode(familyResult.connectionCode)
                },
                onFailure = { error ->
                    // Handle error
                    showError("Failed to create family: ${error.message}")
                }
            )
        }
    }
    
    private fun updateLocationPeriodically() {
        // Called every 2 minutes by your native service
        lifecycleScope.launch {
            val location = getCurrentLocation() // Your location service
            location?.let { loc ->
                familyService.updateLocation(
                    familyId = getFamilyId(),
                    latitude = loc.latitude,
                    longitude = loc.longitude,
                    address = getAddressFromLocation(loc)
                )
            }
        }
    }
}