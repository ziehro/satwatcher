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

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'satellite_passes',
      'Satellite Passes',
      description: 'Notifications for upcoming satellite passes',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<bool> requestPermissions() async {
    // Request notification permission (Android 13+)
    final notificationStatus = await Permission.notification.request();

    // Request exact alarm permission (Android 12+)
    final alarmStatus = await Permission.scheduleExactAlarm.request();

    if (!notificationStatus.isGranted) {
      print('Notification permission denied');
      return false;
    }

    if (!alarmStatus.isGranted) {
      print('Exact alarm permission denied');
      return false;
    }

    return true;
  }

  static Future<void> scheduleNotification(
      String title,
      String body,
      DateTime scheduledTime,
      ) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'satellite_passes',
        'Satellite Passes',
        channelDescription: 'Notifications for upcoming satellite passes',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
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