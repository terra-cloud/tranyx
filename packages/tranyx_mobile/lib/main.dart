import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_uat.dart' as uat;
import 'flavors.dart';

FirebaseOptions _getFirebaseOptions(Flavor flavor) {
  switch (flavor) {
    case Flavor.dev:
      return dev.DefaultFirebaseOptions.currentPlatform;
    case Flavor.uat:
      return uat.DefaultFirebaseOptions.currentPlatform;
    case Flavor.production:
      return prod.DefaultFirebaseOptions.currentPlatform;
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final options = _getFirebaseOptions(F.appFlavor);
    await Firebase.initializeApp(options: options);
    debugPrint("Handling background message: ${message.messageId}");
  } catch (e) {
    debugPrint("Background Firebase initialization warning: $e");
  }
}

FutureOr<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Catch unhandled framework Flutter error details
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint("UNHANDLED FLUTTER FRAMEWORK ERROR: ${details.exception}");
    };

    // Catch unhandled asynchronous errors in Dart Event Loop
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint("UNHANDLED ASYNC ERROR: $error\n$stack");
      return true; // Prevents process crash
    };

    // Initialize flavor
    const flavorString = String.fromEnvironment('FLAVOR');
    F.appFlavor = Flavor.values.firstWhere(
      (e) => e.name == flavorString,
      orElse: () => Flavor.dev,
    );

    // Resilient Firebase Initialization
    try {
      final options = _getFirebaseOptions(F.appFlavor);
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint("Warning: Firebase initialization deferred or failed: $e");
    }

    runApp(const ProviderScope(child: App()));
  } catch (e, stackTrace) {
    debugPrint("CRITICAL INITIALIZATION ERROR: $e");
    debugPrint(stackTrace.toString());
    
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1E1B4B), // Sleek indigo dark theme
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 64,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Startup Failed",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "An error occurred during app initialization. Please check the logs or your configuration.",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white12,
                      ),
                    ),
                    child: Text(
                      e.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

