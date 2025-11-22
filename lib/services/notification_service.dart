import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static final Map<int, Timer> _activeTimers = {};
  static bool _exactAlarmPermitted = false;

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
    _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
      const AndroidNotificationChannel(
        'satellite_passes',
        'Satellite Passes',
        description: 'Notifications for upcoming satellite passes',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      ),
    );
  }

  static Future<bool> requestPermissions() async {
    final notificationStatus = await Permission.notification.request();
    if (!notificationStatus.isGranted) {
      print('Notification permission denied');
      return false;
    }

    final alarmStatus = await Permission.scheduleExactAlarm.status;
    if (alarmStatus.isGranted) {
      _exactAlarmPermitted = true;
    } else {
      final requested = await Permission.scheduleExactAlarm.request();
      _exactAlarmPermitted = requested.isGranted;
    }

    print('Exact alarm permitted: $_exactAlarmPermitted');
    return true;
  }

  static Future<void> scheduleNotification(
      String title,
      String body,
      DateTime scheduledTime,
      ) async {
    final id = scheduledTime.millisecondsSinceEpoch ~/ 1000;
    final delay = scheduledTime.difference(DateTime.now());

    if (delay.isNegative) return;

    _scheduleTimer(id, title, body, delay);
    await _scheduleSystem(id, title, body, scheduledTime);
  }

  static void _scheduleTimer(int id, String title, String body, Duration delay) {
    _activeTimers[id]?.cancel();
    _activeTimers[id] = Timer(delay, () async {
      await showImmediateNotification(title, body, id: id);
      _activeTimers.remove(id);
    });
    print('Timer scheduled: $title in ${delay.inMinutes}m');
  }

  static Future<void> _scheduleSystem(
      int id,
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
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.reminder,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: _exactAlarmPermitted
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );
      print('System scheduled: $title at $scheduledTime (exact: $_exactAlarmPermitted)');
    } catch (e) {
      print('System schedule failed: $e');
    }
  }

  static Future<void> showImmediateNotification(String title, String body, {int? id}) async {
    final androidDetails = AndroidNotificationDetails(
      'satellite_passes',
      'Satellite Passes',
      channelDescription: 'Notifications for upcoming satellite passes',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      visibility: NotificationVisibility.public,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(
      id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static Future<void> cancelNotification(int id) async {
    _activeTimers[id]?.cancel();
    _activeTimers.remove(id);
    await _notifications.cancel(id);
  }

  static Future<void> cancelAllNotifications() async {
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    await _notifications.cancelAll();
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }

  static int getScheduledCount() => _activeTimers.length;
}