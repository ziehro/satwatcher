import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);

    // Create notification channel with MAX importance
    const androidChannel = AndroidNotificationChannel(
      'satellite_passes',
      'Satellite Passes',
      description: 'Notifications for upcoming satellite passes',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<bool> requestPermissions() async {
    final notificationStatus = await Permission.notification.request();
    final alarmStatus = await Permission.scheduleExactAlarm.request();

    if (!notificationStatus.isGranted) {
      print('Notification permission denied');
      return false;
    }

    if (!alarmStatus.isGranted) {
      print('Exact alarm permission denied - trying without');
      // Continue anyway, will use fallback
    }

    return true;
  }

  /// Schedule notification using zonedSchedule (may be blocked by Android)
  static Future<void> scheduleNotification(
      String title,
      String body,
      DateTime scheduledTime,
      ) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'satellite_passes',
        'Satellite Passes',
        channelDescription: 'Notifications for upcoming satellite passes',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        icon: '@mipmap/ic_launcher',
        showWhen: true,
        when: scheduledTime.millisecondsSinceEpoch,
        channelShowBadge: true,
        autoCancel: true,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,  // ADDED: May help trigger notification
        category: AndroidNotificationCategory.alarm,  // ADDED: Treat as alarm
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

      await _notifications.zonedSchedule(
        scheduledTime.millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        tzScheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('Scheduled notification for $title at $scheduledTime');
    } catch (e) {
      print('Error scheduling notification: $e');
    }
  }

  /// Schedule using Timer (works while app is open)
  static Future<void> scheduleWithTimer(
      String title,
      String body,
      Duration delay,
      ) async {
    print('⏱️ Setting Timer for ${delay.inSeconds} seconds...');

    Timer(delay, () async {
      print('⏱️ Timer fired! Showing notification...');
      await showImmediateNotification(title, body);
    });
  }

  /// Show notification immediately
  static Future<void> showImmediateNotification(String title, String body) async {
    final androidDetails = AndroidNotificationDetails(
      'satellite_passes',
      'Satellite Passes',
      channelDescription: 'Notifications for upcoming satellite passes',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      icon: '@mipmap/ic_launcher',
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );

    print('✅ Immediate notification shown: $title');
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    print('Cancelled all notifications');
  }

  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
    print('Cancelled notification with id: $id');
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
}