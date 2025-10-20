import 'package:flutter/material.dart';
import 'package:thanks_everyday/services/permission_manager_service.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/core/utils/app_logger.dart';

/// User-friendly permission guidance widget
/// Shows missing permissions with clear explanations and action buttons
class PermissionGuideWidget extends StatefulWidget {
  final VoidCallback? onAllPermissionsGranted;
  final bool showDismissButton;
  final bool compactMode;
  
  const PermissionGuideWidget({
    super.key,
    this.onAllPermissionsGranted,
    this.showDismissButton = true,
    this.compactMode = false,
  });

  @override
  State<PermissionGuideWidget> createState() => _PermissionGuideWidgetState();
}

class _PermissionGuideWidgetState extends State<PermissionGuideWidget> {
  PermissionStatusInfo? _permissionStatus;
  bool _isLoading = false;
  bool _isDismissed = false;
  
  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }
  
  Future<void> _checkPermissions() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final status = await PermissionManagerService.checkAllPermissions();
      if (mounted) {
        setState(() {
          _permissionStatus = status;
          _isLoading = false;
        });
        
        // Call callback if all permissions are granted
        if (status.allRequiredGranted && widget.onAllPermissionsGranted != null) {
          widget.onAllPermissionsGranted!();
        }
      }
    } catch (e) {
      AppLogger.error('Error checking permissions in guide widget: $e', tag: 'PermissionGuideWidget');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _requestPermission(PermissionType type) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final granted = await PermissionManagerService.requestPermission(type);
      
      if (granted) {
        _showMessage('권한이 허용되었습니다');
      } else {
        _showMessage('권한 설정을 완료해주세요');
        // Open system settings as fallback
        await PermissionManagerService.openPermissionSettings(type);
      }
      
      // Refresh permission status
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkPermissions();
      
    } catch (e) {
      AppLogger.error('Error requesting permission: $e', tag: 'PermissionGuideWidget');
      _showMessage('권한 요청 중 오류가 발생했습니다');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _showMessage(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: AppTheme.primaryGreen,
      ),
    );
  }
  
  void _dismissGuide() {
    setState(() {
      _isDismissed = true;
    });
    
    // Store preference to not show guide again for a while
    PermissionManagerService.setPermissionGuideShown(true);
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isDismissed || _permissionStatus?.allRequiredGranted == true) {
      return const SizedBox.shrink();
    }
    
    if (_isLoading || _permissionStatus == null) {
      return _buildLoadingWidget();
    }
    
    final missing = _permissionStatus!.missing;
    if (missing.isEmpty) {
      return const SizedBox.shrink();
    }
    
    if (widget.compactMode) {
      return _buildCompactGuide(missing);
    } else {
      return _buildFullGuide(missing);
    }
  }
  
  Widget _buildLoadingWidget() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
          ),
          SizedBox(width: 16),
          Text(
            '권한 상태를 확인하고 있습니다...',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCompactGuide(List<PermissionInfo> missing) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.accentOrange,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '안전 확인 기능 활성화',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentOrange,
                  ),
                ),
              ),
              if (widget.showDismissButton)
                IconButton(
                  icon: Icon(Icons.close, color: AppTheme.textLight),
                  onPressed: _dismissGuide,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '⚠️ 일부 기능이 제한됩니다',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.accentOrange,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '안전 확인, GPS 추적 등이 제대로 작동하지 않을 수 있습니다. ${missing.length}개 권한 설정이 필요합니다.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textMedium,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _showDetailedGuide(missing),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: AppTheme.textWhite,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: const Text(
              '권한 설정하기',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFullGuide(List<PermissionInfo> missing) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.security,
                color: AppTheme.primaryGreen,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '안전 확인 기능 설정',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (widget.showDismissButton)
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textLight),
                  onPressed: _dismissGuide,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
            ),
            child: const Text(
              '가족에게 안전 상태를 알리기 위해 몇 가지 권한 설정이 필요합니다. '
              '아래 권한들을 허용하시면 안전 확인 알림이 정상 작동합니다.',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.accentBlue,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...missing.map((permission) => _buildPermissionItem(permission)),
        ],
      ),
    );
  }
  
  Widget _buildPermissionItem(PermissionInfo permission) {
    IconData icon;
    Color iconColor;
    
    switch (permission.type) {
      case PermissionType.location:
        icon = Icons.my_location_rounded;
        iconColor = AppTheme.errorRed;
        break;
      case PermissionType.batteryOptimization:
        icon = Icons.battery_std;
        iconColor = AppTheme.primaryGreen;
        break;
      case PermissionType.usageStats:
        icon = Icons.security;
        iconColor = AppTheme.accentBlue;
        break;
      case PermissionType.overlay:
        icon = Icons.layers_rounded;
        iconColor = AppTheme.accentPurple;
        break;
      default:
        icon = Icons.settings;
        iconColor = AppTheme.textLight;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      permission.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      permission.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            permission.whyNeeded,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textLight,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _requestPermission(permission.type),
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                permission.actionText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showDetailedGuide(List<PermissionInfo> missing) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxHeight: 600),
          child: SingleChildScrollView(
            child: PermissionGuideWidget(
              showDismissButton: false,
              compactMode: false,
              onAllPermissionsGranted: () {
                Navigator.of(context).pop();
                _checkPermissions();
              },
            ),
          ),
        ),
      ),
    );
  }
}