import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/core/router/app_router.dart';

final fcmProvider = Provider<FirebaseMessagingService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return FirebaseMessagingService(firestore, auth, ref);
});

class FirebaseMessagingService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Ref _ref;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  bool _isInitialized = false;

  FirebaseMessagingService(this._firestore, this._auth, this._ref);

  Future<void> initialize(BuildContext context) async {
    if (_isInitialized) return;
    
    final user = _auth.currentUser;
    if (user == null) return;

    final messaging = FirebaseMessaging.instance;

    // 1. Request Permission
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('FCM: Notification permission granted');

        // 2. Get FCM token (safely handle simulator APNS delay)
        try {
          final token = await messaging.getToken();
          if (token != null) {
            await _updateTokenInFirestore(user.uid, token);
          }
        } catch (e) {
          debugPrint('FCM: Token fetching postponed (APNS pending): $e');
        }

        // 3. Listen to token refresh
        _tokenRefreshSub?.cancel();
        _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
          final currentUser = _auth.currentUser;
          if (currentUser != null) {
            await _updateTokenInFirestore(currentUser.uid, newToken);
          }
        });

        // 4. Foreground notifications handling
        _onMessageSub?.cancel();
        _onMessageSub = FirebaseMessaging.onMessage.listen((message) {
          debugPrint('FCM: Foreground message received: ${message.notification?.title}');
          if (context.mounted) {
            _showForegroundNotification(context, message);
          }
        });

        // 5. Background opened notifications handling
        _onMessageOpenedAppSub?.cancel();
        _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
          debugPrint('FCM: App opened from message: ${message.data}');
          if (context.mounted) {
            _handleNotificationClick(context, message);
          }
        });

        // 6. Terminated state opened notifications handling
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null && context.mounted) {
          debugPrint('FCM: Initial message received: ${initialMessage.data}');
          _handleNotificationClick(context, initialMessage);
        }
        
        _isInitialized = true;
      } else {
        debugPrint('FCM: Notification permission denied');
      }
    } catch (e) {
      debugPrint('FCM: Error initializing messaging: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _isInitialized = false;
  }

  Future<void> _updateTokenInFirestore(String uid, String token) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
      debugPrint('FCM: Token successfully registered in Firestore for user $uid');
    } catch (e) {
      debugPrint('FCM: Failed to save token to Firestore: $e');
    }
  }

  void _showForegroundNotification(BuildContext context, RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title'] as String? ?? 'Notification';
    final body = message.notification?.body ?? message.data['body'] as String? ?? '';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty) Text(body, style: const TextStyle(fontSize: 12)),
          ],
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.indigoAccent,
          onPressed: () => _handleNotificationClick(context, message),
        ),
      ),
    );
  }

  void _handleNotificationClick(BuildContext context, RemoteMessage message) {
    final jobId = message.data['jobId'] as String?;
    if (jobId != null) {
      debugPrint('FCM: Navigating to job details: $jobId');
      _ref.read(routerProvider).go('/job/$jobId');
    }
  }
}
