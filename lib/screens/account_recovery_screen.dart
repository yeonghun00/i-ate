import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
// DataRecoveryScreen import removed - using name + connection code only
import 'package:thanks_everyday/theme/app_theme.dart';
import 'package:thanks_everyday/main.dart';

class AccountRecoveryScreen extends StatefulWidget {
  final VoidCallback onRecoveryComplete;
  
  const AccountRecoveryScreen({super.key, required this.onRecoveryComplete});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _connectionCodeController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>>? _multipleCandidates;

  Future<void> _attemptRecovery() async {
    final name = _nameController.text.trim();
    final connectionCode = _connectionCodeController.text.trim();
    
    if (name.isEmpty || connectionCode.isEmpty) {
      setState(() {
        _errorMessage = '이름과 연결 코드를 모두 입력해주세요';
        _multipleCandidates = null;
      });
      return;
    }

    if (connectionCode.length != 4) {
      setState(() {
        _errorMessage = '연결 코드는 4자리 숫자여야 합니다';
        _multipleCandidates = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _multipleCandidates = null;
    });

    try {
      final result = await _firebaseService.recoverAccountWithNameAndCode(
        name: name,
        connectionCode: connectionCode,
      );
      
      if (result != null && result['success'] == true) {
        _showMessage('계정 복구가 완료되었습니다!', isError: false);
        
        // Wait a moment to show success message
        await Future.delayed(const Duration(seconds: 1));
        
        // Navigate directly to HomePage after successful recovery
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomePage()),
            (route) => false, // Remove all previous routes
          );
        }
      } else if (result != null && result['error'] == 'multiple_matches') {
        // Handle multiple matches case
        setState(() {
          _multipleCandidates = List<Map<String, dynamic>>.from(result['candidates'] ?? []);
          _errorMessage = '${result['message']}\n아래에서 본인의 계정을 선택해주세요.';
        });
      } else {
        setState(() {
          _errorMessage = result?['message'] ?? '복구에 실패했습니다';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '복구 중 오류가 발생했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectCandidate(Map<String, dynamic> candidate) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Directly restore this specific candidate
      final result = await _firebaseService.recoverAccountWithNameAndCode(
        name: candidate['elderlyName'],
        connectionCode: _connectionCodeController.text.trim(),
      );
      
      if (result != null && result['success'] == true) {
        _showMessage('계정 복구가 완료되었습니다!', isError: false);
        
        await Future.delayed(const Duration(seconds: 1));
        
        // Navigate directly to HomePage after successful recovery
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomePage()),
            (route) => false, // Remove all previous routes
          );
        }
      } else {
        setState(() {
          _errorMessage = '선택한 계정 복구에 실패했습니다';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '복구 중 오류가 발생했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? AppTheme.errorRed : AppTheme.primaryGreen,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Title and description
                const Icon(
                  Icons.person_search_rounded,
                  size: 80,
                  color: AppTheme.primaryGreen,
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  '계정 찾기',
                  style: TextStyle(
                    fontSize: 28.0,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 12),
                
                const Text(
                  '이름과 4자리 연결 코드를 입력하시면\n이전 계정을 찾아드립니다',
                  style: TextStyle(
                    fontSize: 16.0,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),
                
                // Name input
                _buildInputField(
                  controller: _nameController,
                  label: '등록된 이름',
                  hint: '김할머니',
                  icon: Icons.person,
                ),
                
                const SizedBox(height: 20),
                
                // Connection code input
                _buildInputField(
                  controller: _connectionCodeController,
                  label: '4자리 연결 코드',
                  hint: '1234',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                
                const SizedBox(height: 30),
                
                // Error message or multiple candidates
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.errorRed),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _multipleCandidates != null ? Icons.info_outline : Icons.error_outline,
                          color: _multipleCandidates != null ? AppTheme.primaryGreen : AppTheme.errorRed,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: _multipleCandidates != null ? AppTheme.textPrimary : AppTheme.errorRed,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Multiple candidates selection
                if (_multipleCandidates != null && _multipleCandidates!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '일치하는 계정들',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...(_multipleCandidates!.map((candidate) => 
                          GestureDetector(
                            onTap: () => _selectCandidate(candidate),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundLight,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.borderLight),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    color: AppTheme.primaryGreen,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          candidate['elderlyName'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '유사도: ${((candidate['matchScore'] as double) * 100).toInt()}%',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: AppTheme.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Recovery button
                GestureDetector(
                  onTap: _isLoading ? null : _attemptRecovery,
                  child: Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: _isLoading 
                          ? const LinearGradient(
                              colors: [AppTheme.textDisabled, AppTheme.textLight],
                            )
                          : AppTheme.successGradient,
                      boxShadow: !_isLoading ? [
                        BoxShadow(
                          color: AppTheme.primaryGreen.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ] : [],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              '계정 찾기',
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Information card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryGreen.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppTheme.primaryGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '연결 코드를 모르시나요?',
                            style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '4자리 연결 코드는 처음 앱을 설정할 때 생성됩니다.\n가족들이 자녀 앱에서 확인할 수 있습니다.',
                        style: TextStyle(
                          fontSize: 14.0,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // 8-digit recovery code option removed - using name + connection code only
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
            border: _errorMessage != null
                ? Border.all(color: AppTheme.errorRed, width: 1)
                : null,
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppTheme.textDisabled,
                fontSize: 16.0,
              ),
              prefixIcon: Icon(icon, color: AppTheme.primaryGreen),
              border: InputBorder.none,
              counterText: '', // Hide character counter
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onChanged: (value) {
              if (_errorMessage != null) {
                setState(() {
                  _errorMessage = null;
                  _multipleCandidates = null;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _connectionCodeController.dispose();
    super.dispose();
  }
}