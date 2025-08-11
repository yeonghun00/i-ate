import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thanks_everyday/services/firebase_service.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

class DataRecoveryScreen extends StatefulWidget {
  final VoidCallback onRecoveryComplete;
  
  const DataRecoveryScreen({super.key, required this.onRecoveryComplete});

  @override
  State<DataRecoveryScreen> createState() => _DataRecoveryScreenState();
}

class _DataRecoveryScreenState extends State<DataRecoveryScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _connectionCodeController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _attemptRecovery() async {
    final name = _nameController.text.trim();
    final connectionCode = _connectionCodeController.text.trim();
    
    if (name.isEmpty) {
      setState(() {
        _errorMessage = '이름을 입력해주세요';
      });
      return;
    }

    if (connectionCode.isEmpty) {
      setState(() {
        _errorMessage = '연결 코드를 입력해주세요';
      });
      return;
    }

    if (connectionCode.length != 4) {
      setState(() {
        _errorMessage = '연결 코드는 4자리 숫자여야 합니다';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _firebaseService.recoverAccountWithNameAndCode(
        name: name,
        connectionCode: connectionCode,
      );
      
      if (result != null && result['success'] == true) {
        _showMessage('데이터 복구가 완료되었습니다!', isError: false);
        
        // Wait a moment to show success message
        await Future.delayed(const Duration(seconds: 2));
        widget.onRecoveryComplete();
      } else {
        final errorMessage = result?['message'] ?? '입력된 정보가 올바르지 않습니다';
        setState(() {
          _errorMessage = errorMessage;
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
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Title
                const Icon(
                  Icons.restore,
                  size: 80,
                  color: AppTheme.primaryGreen,
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  '데이터 복구',
                  style: TextStyle(
                    fontSize: 28.0,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 12),
                
                const Text(
                  '앱을 다시 설치하셨나요?\n등록된 이름과 연결 코드를 입력하시면\n이전 데이터를 복구할 수 있습니다',
                  style: TextStyle(
                    fontSize: 16.0,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),
                
                // Name input
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                    border: _errorMessage != null
                        ? Border.all(color: AppTheme.errorRed, width: 2)
                        : null,
                  ),
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      hintText: '등록된 이름 (예: 김영희)',
                      hintStyle: TextStyle(
                        color: AppTheme.textDisabled,
                        fontSize: 16.0,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 20),
                    ),
                    textAlign: TextAlign.center,
                    onChanged: (value) {
                      if (_errorMessage != null) {
                        setState(() {
                          _errorMessage = null;
                        });
                      }
                    },
                  ),
                ),
                
                // Connection code input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                    border: _errorMessage != null
                        ? Border.all(color: AppTheme.errorRed, width: 2)
                        : null,
                  ),
                  child: TextField(
                    controller: _connectionCodeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    style: const TextStyle(
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                    decoration: const InputDecoration(
                      hintText: '1234',
                      hintStyle: TextStyle(
                        color: AppTheme.textDisabled,
                        fontSize: 24.0,
                        letterSpacing: 4,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 20),
                    ),
                    textAlign: TextAlign.center,
                    onChanged: (value) {
                      if (_errorMessage != null) {
                        setState(() {
                          _errorMessage = null;
                        });
                      }
                    },
                  ),
                ),
                
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.errorRed),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppTheme.errorRed,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.errorRed,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 40),
                
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
                              '데이터 복구하기',
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
                            '복구 방법',
                            style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '첫 설정 시 입력한 이름과\n4자리 연결 코드를 입력해주세요.\n연결 코드는 가족앱에서 확인할 수 있습니다.',
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
                
                // Cancel button
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '나중에 하기',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _connectionCodeController.dispose();
    super.dispose();
  }
}