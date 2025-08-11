import 'package:flutter/material.dart';
import 'package:thanks_everyday/services/screen_monitor_service.dart';

class AutoStartPermissionScreen extends StatefulWidget {
  const AutoStartPermissionScreen({Key? key}) : super(key: key);

  @override
  _AutoStartPermissionScreenState createState() => _AutoStartPermissionScreenState();
}

class _AutoStartPermissionScreenState extends State<AutoStartPermissionScreen> {
  Map<String, dynamic>? autoStartInfo;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAutoStartPermission();
  }

  Future<void> _checkAutoStartPermission() async {
    setState(() {
      isLoading = true;
    });

    final info = await ScreenMonitorService.checkAutoStartPermission();
    setState(() {
      autoStartInfo = info;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('자동 시작 권한 확인'),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF10B981),
          ),
        ),
      );
    }

    if (autoStartInfo == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('자동 시작 권한 확인'),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            '권한 정보를 불러올 수 없습니다.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final requiresAutoStart = autoStartInfo!['requiresAutoStart'] as bool;
    final oem = autoStartInfo!['oem'] as String;
    final instructions = autoStartInfo!['instructions'] as String;
    final manufacturer = autoStartInfo!['manufacturer'] as String;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '자동 시작 권한',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E3440),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF6B7280)),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Info Card
              _buildInfoCard(
                title: '기기 정보',
                items: [
                  '제조사: $manufacturer',
                  'OS: $oem',
                  '자동 시작 필요: ${requiresAutoStart ? "예" : "아니오"}',
                ],
                icon: Icons.phone_android,
                color: const Color(0xFF3B82F6),
              ),

              const SizedBox(height: 20),

              if (requiresAutoStart) ...[
                // Warning Card
                _buildInfoCard(
                  title: '⚠️ 중요한 설정 필요',
                  items: [
                    '재부팅 후 앱이 자동으로 실행되려면',
                    '"자동 시작" 권한이 필요합니다.',
                    '이 설정이 없으면 GPS 추적과',
                    '안전 모니터링이 작동하지 않습니다.',
                  ],
                  icon: Icons.warning,
                  color: const Color(0xFFEF4444),
                ),

                const SizedBox(height: 20),

                // Instructions Card
                _buildInfoCard(
                  title: '설정 방법',
                  items: instructions.split('→').map((s) => s.trim()).toList(),
                  icon: Icons.settings,
                  color: const Color(0xFF10B981),
                ),

                const SizedBox(height: 30),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await ScreenMonitorService.openAutoStartSettings();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      '자동 시작 설정 열기',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Skip Button (for testing)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      '나중에 설정하기',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Good to go card
                _buildInfoCard(
                  title: '✅ 설정 완료',
                  items: [
                    '이 기기에서는 별도의',
                    '자동 시작 설정이 필요하지 않습니다.',
                    'GPS 추적과 안전 모니터링이',
                    '재부팅 후에도 자동으로 작동합니다.',
                  ],
                  icon: Icons.check_circle,
                  color: const Color(0xFF10B981),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required List<String> items,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
              Icon(
                icon,
                size: 24,
                color: color,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              item,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF374151),
                height: 1.5,
              ),
            ),
          )).toList(),
        ],
      ),
    );
  }
}