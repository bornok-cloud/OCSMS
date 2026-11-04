import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'firebase_options.dart';
import 'services/app_data.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await NotificationService.initialize();
    }
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // Make sure there's always at least one admin account to log in with.
  await AppData.instance.ensureDefaultAdmin();

  runApp(const CafeManagementApp());
}

class CafeManagementApp extends StatelessWidget {
  const CafeManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Overnight Cafe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
