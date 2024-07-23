import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;


Future<void> handleBackgroundMessage(RemoteMessage message)async{
  print('title: ${message.notification?.title}');
  print('body: ${message.notification?.body}');
  print('payload: ${message.data}');
}

class FirebaseApi{
  final firebaseMessaging = FirebaseMessaging.instance;

  final androidChannel = const AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: "This channel is used for notifications",
      importance: Importance.defaultImportance
  );
  final localNotifications = FlutterLocalNotificationsPlugin();



  Future initLocalNotification()async{
    const ios = DarwinInitializationSettings();
    const android = AndroidInitializationSettings("@drawable/bankal");
    const setting = InitializationSettings(android: android, iOS: ios);
    await localNotifications.initialize(
        setting,
        onDidReceiveNotificationResponse: (NotificationResponse response){
          final String? payload = response.payload;
          if (payload != null) {
            final message = RemoteMessage.fromMap(jsonDecode(payload));
            handleBackgroundMessage(message);
          }
        }
    );
    final platform = localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await platform?.createNotificationChannel(androidChannel);
  }

  Future initPushNotification()async{
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert:  true,
        badge: true,
        sound: true
    );
    FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if(notification == null) return;
      localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
              android: AndroidNotificationDetails(
                androidChannel.id,
                androidChannel.name,
                channelDescription: androidChannel.description,
                icon: "@drawable/bankal",
              )
          ),
          payload: jsonEncode(message.toMap())
      );
    });
  }

  //daily notifs start here
  Future<void> scheduleDailyNotification() async {
    print('Current time zone: ${tz.local}');
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'daily_notification_channel_id',
      'daily_notification_channel_name',
      channelDescription: 'Daily notification channel',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await localNotifications.zonedSchedule(
      0,
      'Daily Notification',
      'This is your scheduled notification at 9 AM.',
      _nextInstanceOfNineAM(),
      platformChannelSpecifics,
      androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOfNineAM() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 17, 54);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
  // ends here

  Future<void> showImmediateNotification() async {
    await localNotifications.show(
      0,
      'Immediate Notification',
      'This is an immediate notification.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannel.id,
          androidChannel.name,
          channelDescription: androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: "@drawable/bankal",
        ),
      ),
    );
  }
  Future<void> initNotifications()async{
    await firebaseMessaging.requestPermission();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? fcmToken;
    if (Platform.isAndroid) {
      fcmToken = await firebaseMessaging.getToken();
    } else if (Platform.isIOS) {
      fcmToken = await firebaseMessaging.getAPNSToken();
    }
    if (fcmToken != null) {
      prefs.setString('fcmToken', fcmToken);
      print('FCM Token: $fcmToken');
    }
    firebaseMessaging.onTokenRefresh.listen((newToken) {
      // TODO: If necessary, send new token to application server.
      prefs.setString('fcmToken', newToken);
      print('FCM Token Refreshed: $newToken');
    }, onError: (error) {
      print('FCM Token Refresh Error: $error');
    });
     initPushNotification();
    initLocalNotification();
     scheduleDailyNotification();
  }
}