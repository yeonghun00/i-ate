import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BootDebugScreen extends StatefulWidget {
  const BootDebugScreen({Key? key}) : super(key: key);

  @override
  _BootDebugScreenState createState() => _BootDebugScreenState();
}

class _BootDebugScreenState extends State<BootDebugScreen> {
  static const MethodChannel _channel = MethodChannel('com.thousandemfla.thanks_everyday/screen_monitor');
  String _logContent = 'Loading...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBootLog();
  }

  Future<void> _loadBootLog() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final String result = await _channel.invokeMethod('getBootDebugLog');
      setState(() {
        _logContent = result;
        _isLoading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _logContent = 'Error loading boot log: ${e.message}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🔧 Boot Debug Log',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E3440),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF6B7280)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBootLog,
            tooltip: 'Refresh Log',
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8F9FA), Color(0xFFE9ECEF)],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF10B981),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Instructions Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '리부팅 테스트 방법',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '1. GPS와 생존 신호를 활성화하세요\n'
                            '2. 기기를 재부팅하세요\n'
                            '3. 재부팅 후 이 화면을 확인하세요\n'
                            '4. 로그가 나타나면 BootReceiver가 작동 중입니다',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF374151),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Log Content Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.terminal, color: Color(0xFF10B981), size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Boot Debug Log',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              _logContent,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFF374151),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}