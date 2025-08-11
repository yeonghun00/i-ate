import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thanks_everyday/services/firebase_service.dart';

class FamilySetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;
  
  const FamilySetupScreen({super.key, required this.onSetupComplete});

  @override
  State<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends State<FamilySetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = false;
  String? _generatedCode;
  // Recovery code variable removed

  Future<void> _setupFamily() async {
    if (_nameController.text.trim().isEmpty) {
      _showMessage('이름을 입력해주세요');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _firebaseService.setupFamilyCode(_nameController.text.trim());
      
      if (result != null) {
        setState(() {
          _generatedCode = _firebaseService.familyCode;
          // Recovery code removed
        });
        
        // Wait a moment to show the codes, then complete setup
        await Future.delayed(const Duration(seconds: 5));
        widget.onSetupComplete();
      } else {
        _showMessage('설정에 실패했습니다. 다시 시도해주세요.');
      }
    } catch (e) {
      _showMessage('오류가 발생했습니다: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF8F9FA),
                Color(0xFFE9ECEF),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                
                // App title
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Text(
                    '고마워요',
                    style: TextStyle(
                      fontSize: 26.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E3440),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                if (_generatedCode != null) ...[
                  // Show generated code
                  const Text(
                    '가족 코드가 생성되었습니다!',
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Text(
                      _generatedCode!,
                      style: const TextStyle(
                        fontSize: 36.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 8,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  const Text(
                    '이 코드를 가족들에게 알려주세요.\n가족들이 이 코드로 당신의 이야기를 들을 수 있어요.',
                    style: TextStyle(
                      fontSize: 16.0,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  // Recovery code display removed - using name + connection code only
                  
                ] else ...[
                  // Setup form
                  const Icon(
                    Icons.family_restroom,
                    size: 80,
                    color: Color(0xFF10B981),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  const Text(
                    '가족과 연결하기',
                    style: TextStyle(
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E3440),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 10),
                  
                  const Text(
                    '가족들이 당신의 감사 이야기를 들을 수 있도록\n간단한 설정을 해보세요',
                    style: TextStyle(
                      fontSize: 15.0,
                      color: Color(0xFF6B7280),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 25),
                  
                  // Name input
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: const InputDecoration(
                        hintText: '이름을 입력하세요 (예: 김할머니)',
                        hintStyle: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 16.0,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 20),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  
                  const SizedBox(height: 25),
                  
                  // Setup button
                  GestureDetector(
                    onTap: _isLoading ? null : _setupFamily,
                    child: Container(
                      width: double.infinity,
                      height: 70,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(35),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF10B981),
                            Color(0xFF059669),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              )
                            : const Text(
                                '가족 코드 만들기',
                                style: TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: const Color(0xFF3B82F6),
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFF3B82F6),
                          size: 20,
                        ),
                        SizedBox(height: 6),
                        Text(
                          '가족 코드란?',
                          style: TextStyle(
                            fontSize: 14.0,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '4자리 숫자로 된 간단한 코드입니다.\n가족들이 이 코드로 당신의 감사 이야기를 들을 수 있어요.',
                          style: TextStyle(
                            fontSize: 12.0,
                            color: Color(0xFF6B7280),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
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
    super.dispose();
  }
}