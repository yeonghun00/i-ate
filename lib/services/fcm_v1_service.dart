import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class FCMv1Service {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // Your Firebase Project ID from google-services.json
  static const String _projectId = 'thanks-everyday';

  // TODO: Place your service account JSON content here
  static const Map<String, dynamic> _serviceAccountJson = {
    "type": "service_account",
    "project_id": "thanks-everyday",
    "private_key_id": "182bb18c228384723149ad25fce50ea8b27d49d1",
    "private_key":
        "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCbrpIcdS/12HNT\nFbrqIcZsmwclmIFYmG1ko3ggF2c78NtJvIHohNAKnQsGz3GG36cPcXgvXrsopryu\ncAcr6Halw+np4PHek818scUZ8El0IOabLekNh/P0VBcrobEqGMVTyfjDYdXAAYYN\nolVmoleuwDcdzeo4etiMh4u1nalMVNn835N5T/tJLkoq9vaISkiIVAceHvmuJhIU\nEgaQz4xVm21MQ/6nTefQy9HgxpYPQjLaoRZY9dfcBetuKgz48+TquVDPGOBLbr3+\njVYd1NxGXW0Cq40acEZEea604hmY1N6/HBKiaYVhVImlddxFM06TiRFy99gmHvyi\nANTJjEbtAgMBAAECggEAEW6PZTjY9S/2n9HB02gTQgNs3jCQoSU2MIveTkeYk11h\njITbTfgbHGkfvDQ7q8S8vc2wjatPjRp4a5bXMrstl9uTRFEf/BJ0MpdsML6XVvW9\nJJiULSPxNMU6r/PDtOk/pSVrIaOBjeWNx1aLNfoNE9/pfACbzpWwzDF8OwqLk6SK\n5Ur6XruLeZgwawRjK6qc0qMAVchUJwD31NTrLOEu06JEds7KCI2xk0a3pdwhq6X7\ndBDZ8et0IFXWwPXm459HdFmRKIbUt67Wm/+T79YmPg2yOwZptsv1CJK7/YQQUv8H\nSrjZx1wh5WGlSAFHVjXUjWpOzPrpalgEnYJ0mRvC8QKBgQDOjZ35UM7dKadajY02\n0QOK0N2oEw8aHdRwzfYVWQ5imybymWtrrbA+ZrJBRxPkK1LKcAd/tVlnmh/P2LZ2\nfUK71hwt4ng45lq3IDPnALDRvCE76AIX5y3mqR8FCAxYUVoV5XyAmXl26xh3+4mu\nZFro8tMhWzMj2X3GMCN61NoyHQKBgQDA8101Yi6fiRgfAjagRfdnE/oH6AE/7sAR\nAJc17GpDpWXv8ChR1N1VGMVlos1a78y6Wj7Qwgjy6WddaVDP4Ma1XDLSbBvnv++j\nuqVh6Z7NG5+Y8UPahLhapusLNPLJFTJwY37QECUMM9h/4T/MCq9TzSR7rY0rfq8v\nkkMk5HhPEQKBgBoDoAfMc6FLI7a16TkkLewHzkLi054Yb68dYYbixnsIy2j2hZ70\nKyRQztaF2y17f1vbrDYbYv03XhZRVvmpYQRDPR1STo3sBTTXK3JGlf50UUM4Pzs/\ndHp+hled4eAlrtDfLEUOD0w448YIuhhqr0BzhL/IurIjLEIPwggwUqLJAoGAc8+e\nmnQb19XJjJMfhoN4Q35SDHzMgzsiPRJFsC/+eCvGS4WyLau+TV1Y3fAhoftcvl18\nZoCQLny5de/IeX1Ix4JXXsVU2nzxsSxOJ765ehKicIIfYAFZRc/6M/fL4bW/WIXf\nj7KhCfn0cI0aZbXkFkCDLVi16u1W6Q65DmOzcoECgYEAlL+F+pFjQoP14o11tfMq\nDRiqaktxZJeouCf1jh/5TZFEfNT5VW1cIW63BwoX54LFipuBkOSQ8kidjBE0XeXG\nQEMTPcf5Fg/9P6ohHtTuEkfgUQzZ5XcUONVJ2ycy903/TTbka/WeN6BGcxxdosP/\nhCebPaDhfX//n7uL9wLB0JE=\n-----END PRIVATE KEY-----\n",
    "client_email":
        "firebase-adminsdk-fbsvc@thanks-everyday.iam.gserviceaccount.com",
    "client_id": "109514701744966123949",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url":
        "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40thanks-everyday.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com",
  };

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
  ];

  /// Initialize FCM for the parent app
  static Future<void> initialize() async {
    try {
      // Request permission for notifications
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('FCM permissions granted');
      } else {
        print('FCM permissions denied');
      }
    } catch (e) {
      print('FCM initialization failed: $e');
    }
  }

  /// Get OAuth2 access token for FCM v1 API
  static Future<String?> _getAccessToken() async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(
        _serviceAccountJson,
      );
      final client = http.Client();

      try {
        final accessCredentials =
            await obtainAccessCredentialsViaServiceAccount(
              accountCredentials,
              _scopes,
              client,
            );

        return accessCredentials.accessToken.data;
      } finally {
        client.close();
      }
    } catch (e) {
      print('Failed to get access token: $e');
      return null;
    }
  }

  /// Send meal notification when parent clicks "I ate"
  static Future<bool> sendMealNotification({
    required String familyId,
    required String elderlyName,
    required DateTime timestamp,
    required int mealNumber,
  }) async {
    try {
      // Get all child app FCM tokens for this family
      final childTokens = await _getChildAppTokens(familyId);

      if (childTokens.isEmpty) {
        print('No child app tokens found for family: $familyId');
        return false;
      }

      // Format timestamp for display
      final timeStr =
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

      bool allSent = true;

      // Send to each child app token
      for (String token in childTokens) {
        final success = await _sendNotificationV1(
          token: token,
          title: '🍽️ 식사 알림',
          body: '$elderlyName님이 $mealNumber번째 식사를 하셨습니다 ($timeStr)',
          data: {
            'type': 'meal_recorded',
            'family_id': familyId,
            'elderly_name': elderlyName,
            'timestamp': timestamp.toIso8601String(),
            'meal_number': mealNumber.toString(),
            'time_display': timeStr,
          },
        );
        if (!success) allSent = false;
      }

      return allSent;
    } catch (e) {
      print('Failed to send meal notification: $e');
      return false;
    }
  }

  /// Send survival alert notification
  static Future<bool> sendSurvivalAlert({
    required String familyId,
    required String elderlyName,
    required int hoursInactive,
  }) async {
    try {
      final childTokens = await _getChildAppTokens(familyId);

      if (childTokens.isEmpty) {
        print('No child app tokens found for family: $familyId');
        return false;
      }

      bool allSent = true;

      for (String token in childTokens) {
        final success = await _sendNotificationV1(
          token: token,
          title: '🚨 생존 신호 알림',
          body: '$elderlyName님이 $hoursInactive시간 이상 활동이 없습니다. 안부를 확인해 주세요.',
          data: {
            'type': 'survival_alert',
            'family_id': familyId,
            'elderly_name': elderlyName,
            'hours_inactive': hoursInactive.toString(),
            'alert_level': 'critical',
          },
          androidChannelId: 'emergency_alerts',
          priority: 'high',
        );
        if (!success) allSent = false;
      }

      return allSent;
    } catch (e) {
      print('Failed to send survival alert: $e');
      return false;
    }
  }

  /// Send food alert notification
  static Future<bool> sendFoodAlert({
    required String familyId,
    required String elderlyName,
    required int hoursWithoutFood,
  }) async {
    try {
      final childTokens = await _getChildAppTokens(familyId);

      if (childTokens.isEmpty) {
        print('No child app tokens found for family: $familyId');
        return false;
      }

      bool allSent = true;

      for (String token in childTokens) {
        final success = await _sendNotificationV1(
          token: token,
          title: '🍽️ 식사 패턴 알림',
          body: '$elderlyName님이 $hoursWithoutFood시간 이상 식사를 하지 않으셨습니다.',
          data: {
            'type': 'food_alert',
            'family_id': familyId,
            'elderly_name': elderlyName,
            'hours_without_food': hoursWithoutFood.toString(),
            'alert_level': 'warning',
          },
          androidChannelId: 'meal_alerts',
        );
        if (!success) allSent = false;
      }

      return allSent;
    } catch (e) {
      print('Failed to send food alert: $e');
      return false;
    }
  }

  /// Send notification using FCM v1 API
  static Future<bool> _sendNotificationV1({
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
    String androidChannelId = 'meal_notifications',
    String priority = 'normal',
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        print('Failed to get access token');
        return false;
      }

      final url =
          'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';

      final message = {
        'message': {
          'token': token,
          'notification': {'title': title, 'body': body},
          'data': data,
          'android': {
            'priority': priority.toLowerCase(),
            'notification': {
              'channel_id': androidChannelId,
              'sound': 'default',
              'default_sound': true,
              'default_vibrate_timings': true,
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'alert': {'title': title, 'body': body},
                'sound': 'default',
                'badge': 1,
                'content-available': 1,
              },
            },
          },
        },
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('FCM v1 notification sent successfully: ${responseData['name']}');
        return true;
      } else {
        print('FCM v1 error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Failed to send FCM v1 notification: $e');
      return false;
    }
  }

  /// Get all child app FCM tokens for a family
  static Future<List<String>> _getChildAppTokens(String familyId) async {
    try {
      final snapshot = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('child_devices')
          .where('fcm_token', isNotEqualTo: null)
          .where('is_active', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => doc.data()['fcm_token'] as String)
          .where((token) => token.isNotEmpty)
          .toList();
    } catch (e) {
      print('Failed to get child app tokens: $e');
      return [];
    }
  }

  /// Register child app FCM token (to be called by child app)
  static Future<bool> registerChildAppToken({
    required String familyId,
    required String deviceId,
    required String fcmToken,
    String? deviceName,
  }) async {
    try {
      await _firestore
          .collection('families')
          .doc(familyId)
          .collection('child_devices')
          .doc(deviceId)
          .set({
            'fcm_token': fcmToken,
            'device_id': deviceId,
            'device_name': deviceName ?? 'Child Device',
            'is_active': true,
            'registered_at': FieldValue.serverTimestamp(),
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      print('Child app FCM token registered successfully');
      return true;
    } catch (e) {
      print('Failed to register child app FCM token: $e');
      return false;
    }
  }
}
