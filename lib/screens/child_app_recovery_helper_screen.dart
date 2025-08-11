import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

class ChildAppRecoveryHelperScreen extends StatefulWidget {
  const ChildAppRecoveryHelperScreen({super.key});

  @override
  State<ChildAppRecoveryHelperScreen> createState() => _ChildAppRecoveryHelperScreenState();
}

class _ChildAppRecoveryHelperScreenState extends State<ChildAppRecoveryHelperScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _connectionCodes = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadConnectionCodes();
  }

  Future<void> _loadConnectionCodes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final codes = await _firebaseService.getConnectionCodesForRecovery();
      setState(() {
        _connectionCodes = codes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '연결 코드를 불러오는데 실패했습니다: $e';
        _isLoading = false;
      });
    }
  }

  void _copyConnectionCode(String code, String name) {
    Clipboard.setData(ClipboardData(text: code));
    _showMessage('$name의 연결 코드 $code가 복사되었습니다');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppTheme.primaryGreen,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  String _formatLastActivity(dynamic lastActivity) {
    if (lastActivity == null) return '활동 기록 없음';
    
    try {
      final DateTime activityTime;
      if (lastActivity is DateTime) {
        activityTime = lastActivity;
      } else {
        activityTime = DateTime.parse(lastActivity.toString());
      }
      
      final now = DateTime.now();
      final difference = now.difference(activityTime);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}일 전';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}시간 전';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}분 전';
      } else {
        return '방금 전';
      }
    } catch (e) {
      return '알 수 없음';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '부모님 계정 복구 도우미',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                ),
              )
            : _errorMessage != null
                ? _buildErrorState()
                : _buildContent(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 80,
              color: AppTheme.errorRed,
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _loadConnectionCodes,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.help_outline,
                      color: AppTheme.primaryGreen,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '부모님께서 계정을 찾지 못하시나요?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '아래 목록에서 부모님의 이름을 찾으시고, 4자리 연결 코드를 부모님께 알려주세요. 부모님이 이름과 연결 코드를 함께 입력하시면 계정을 찾을 수 있습니다.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Connection codes list
          Expanded(
            child: _connectionCodes.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _connectionCodes.length,
                    itemBuilder: (context, index) {
                      final family = _connectionCodes[index];
                      return _buildFamilyCard(family);
                    },
                  ),
          ),
          
          // Refresh button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _loadConnectionCodes,
                icon: const Icon(Icons.refresh),
                label: const Text('목록 새로고침'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: AppTheme.textDisabled,
          ),
          const SizedBox(height: 20),
          const Text(
            '등록된 계정이 없습니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '부모님께서 먼저 앱을 설정하신 후\n이 기능을 사용해주세요',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textLight,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyCard(Map<String, dynamic> family) {
    final name = family['elderlyName'] ?? '이름 없음';
    final connectionCode = family['connectionCode'] ?? '코드 없음';
    final approved = family['approved'];
    final lastActivity = family['lastActivity'];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person,
                    color: AppTheme.primaryGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: approved == true 
                                  ? AppTheme.primaryGreen 
                                  : approved == false
                                      ? AppTheme.errorRed
                                      : AppTheme.textDisabled,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            approved == true 
                                ? '승인됨' 
                                : approved == false
                                    ? '거부됨'
                                    : '승인 대기 중',
                            style: TextStyle(
                              fontSize: 12,
                              color: approved == true 
                                  ? AppTheme.primaryGreen 
                                  : approved == false
                                      ? AppTheme.errorRed
                                      : AppTheme.textDisabled,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Connection code
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.numbers,
                    color: AppTheme.primaryGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '연결 코드: ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    connectionCode,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _copyConnectionCode(connectionCode, name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '복사',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Last activity
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppTheme.textLight,
                ),
                const SizedBox(width: 6),
                Text(
                  '마지막 활동: ${_formatLastActivity(lastActivity)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}