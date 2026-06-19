import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_uat.dart' as uat;
import 'flavors.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If using other firebase services, initialize Firebase first.
  await Firebase.initializeApp();
  debugPrint("Handling background message: ${message.messageId}");
}

FutureOr<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize flavor
  const flavorString = String.fromEnvironment('FLAVOR');
  F.appFlavor = Flavor.values.firstWhere(
    (e) => e.name == flavorString,
    orElse: () => Flavor.dev,
  );

  // Initialize Firebase based on flavor
  FirebaseOptions options;
  switch (F.appFlavor) {
    case Flavor.dev:
      options = dev.DefaultFirebaseOptions.currentPlatform;
      break;
    case Flavor.uat:
      options = uat.DefaultFirebaseOptions.currentPlatform;
      break;
    case Flavor.production:
      options = prod.DefaultFirebaseOptions.currentPlatform;
      break;
  }

  await Firebase.initializeApp(options: options);

  runApp(const ProviderScope(child: App()));
}
