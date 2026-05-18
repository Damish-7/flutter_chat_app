import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ── Background message handler ─────────────────────────────────
// Must be a top-level function (not inside a class)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // App is in background or terminated — handle silently
  debugPrint('Background message: ${message.messageId}');
}

class NotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;

  Future<void> initialize() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission (shows popup on Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('Notification permission: ${settings.authorizationStatus}');

    // Get FCM token and save to Firestore
    await _saveTokenToFirestore();

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_updateToken);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  // ── Save FCM token to Firestore ────────────────────────────
  // Each user's token is saved so we know where to send notifications
  Future<void> _saveTokenToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await _messaging.getToken();
    if (token == null) return;

    debugPrint('FCM Token: $token');

    // Save under users/{uid}/tokens/{token}
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set({
          'email': user.email,
          'fcmToken': token,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _updateToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({
      'fcmToken': token,
    });
  }

  // ── Foreground message handler ─────────────────────────────
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message: ${message.notification?.title}');
    // When app is open, Firebase doesn't show a notification banner
    // automatically — we show a SnackBar instead (see chat_page.dart)
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    // Navigate to chat page if needed
  }
}