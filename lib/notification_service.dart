import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Must be top-level — not inside any class
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('Permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await _saveToken();
      _messaging.onTokenRefresh.listen(_saveToken);
    }
  }

  Future<void> _saveToken([String? newToken]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = newToken ?? await _messaging.getToken();
    if (token == null) return;

    debugPrint('════════════════════════════════');
    debugPrint('FCM TOKEN: $token');
    debugPrint('════════════════════════════════');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
          'email':     user.email,
          'fcmToken':  token,
          'lastSeen':  FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  // Call this from chat page
  void listenForeground(BuildContext context) {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.blue,
            content: Row(
              children: [
                const Icon(Icons.notifications, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${notification.title}: ${notification.body}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }
}