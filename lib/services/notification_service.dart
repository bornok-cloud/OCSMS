import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("Handling background message: ${message.messageId}");
    await NotificationService.showNotificationFromRemoteMessage(message);
  } catch (e) {
    debugPrint("Error in background handler: $e");
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important chat and message notifications.',
    importance: Importance.max,
    playSound: true,
  );

  static Future<void> initialize() async {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint("Notification clicked: ${response.payload}");
        },
      );

      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_channel);
      }

      final messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('User granted notification permission: ${settings.authorizationStatus}');

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      await messaging.subscribeToTopic('all_messages');
      await messaging.subscribeToTopic('new_orders');
      await messaging.subscribeToTopic('order_updates');
      debugPrint("Subscribed to FCM topics: all_messages, new_orders, order_updates");

      final token = await messaging.getToken();
      debugPrint("FCM Registration Token: $token");

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("Foreground message received: ${message.notification?.title}");
        showNotificationFromRemoteMessage(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint("Notification opened app: ${message.data}");
      });

    } catch (e) {
      debugPrint("Error initializing NotificationService: $e");
    }
  }

  static Future<void> subscribeToRoleTopics(dynamic role) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.subscribeToTopic('all_messages');
      await messaging.subscribeToTopic('new_orders');
      await messaging.subscribeToTopic('order_updates');
      debugPrint("Subscribed to FCM topics for background notifications.");
    } catch (e) {
      debugPrint("Error subscribing to FCM topics: $e");
    }
  }

  static Future<void> unsubscribeFromTopics() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.unsubscribeFromTopic('all_messages');
      await messaging.unsubscribeFromTopic('new_orders');
      await messaging.unsubscribeFromTopic('order_updates');
      debugPrint("Unsubscribed from FCM topics.");
    } catch (e) {
      debugPrint("Error unsubscribing from FCM topics: $e");
    }
  }

  static Future<void> showNotificationFromRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'New Message';
    final body = notification?.body ?? message.data['body'] ?? message.data['text'] ?? 'You received a new message.';

    await showLocalNotification(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      payload: jsonEncode(message.data),
    );
  }

  static Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        channelDescription: 'This channel is used for important chat and message notifications.',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint("Error showing local notification: $e");
    }
  }
}
