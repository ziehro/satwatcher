// lib/services/notification_service.dart - Replace entire file
import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduledAlarm {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledTime;

  ScheduledAlarm({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'scheduledTime': scheduledTime.toIso8601String(),
  };

  factory ScheduledAlarm.fromJson(Map<String, dynamic> json) => ScheduledAlarm(
    id: json['id'],
    title: json['title'],
    body: json['body'],
    scheduledTime: DateTime.parse(json['scheduledTime']),
  );
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();
  static const _alarmChannel = MethodChannel('com.ziehro.satwatcher/alarms');
  static const String _alarmsKey = 'scheduled_alarms';

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

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
      ),
    );
  }

  static Future<Map<String, bool>> checkPermissions() async {
    final notifGranted = await Permission.notification.isGranted;
    final exactAlarmGranted = await Permission.scheduleExactAlarm.isGranted;

    bool canSchedule = false;
    try {
      canSchedule = await _alarmChannel.invokeMethod('canScheduleExactAlarms');
    } catch (e) {
      print('Error checking alarm permission: $e');
    }

    return {
      'notifications': notifGranted,
      'exactAlarms': exactAlarmGranted,
      'canSchedule': canSchedule,
    };
  }

  static Future<bool> requestPermissions() async {
    final notificationStatus = await Permission.notification.request();
    if (!notificationStatus.isGranted) {
      print('Notification permission denied');
      return false;
    }

    try {
      final canSchedule = await _alarmChannel.invokeMethod('canScheduleExactAlarms');
      if (!canSchedule) {
        await _alarmChannel.invokeMethod('openAlarmSettings');
      }
      return canSchedule;
    } catch (e) {
      print('Error requesting alarm permission: $e');
      return false;
    }
  }

  static Future<void> scheduleNotification(
      String title,
      String body,
      DateTime scheduledTime,
      ) async {
    final id = scheduledTime.millisecondsSinceEpoch ~/ 1000;
    final delay = scheduledTime.difference(DateTime.now());

    if (delay.isNegative) return;

    try {
      await _alarmChannel.invokeMethod('scheduleAlarm', {
        'id': id,
        'title': title,
        'body': body,
        'timestamp': scheduledTime.millisecondsSinceEpoch,
      });

      // Track the alarm
      await _saveScheduledAlarm(ScheduledAlarm(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
      ));

      print('Alarm scheduled via platform: $title at $scheduledTime');
    } catch (e) {
      print('Failed to schedule alarm: $e');
      // Fallback to flutter_local_notifications
      await _scheduleSystem(id, title, body, scheduledTime);
    }
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
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      print('System schedule failed: $e');
    }
  }

  static Future<void> _saveScheduledAlarm(ScheduledAlarm alarm) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = await _getScheduledAlarms();

      // Remove any existing alarm with same ID
      alarms.removeWhere((a) => a.id == alarm.id);

      // Add new alarm
      alarms.add(alarm);

      // Save back
      final alarmsJson = jsonEncode(alarms.map((a) => a.toJson()).toList());
      await prefs.setString(_alarmsKey, alarmsJson);
    } catch (e) {
      print('Error saving scheduled alarm: $e');
    }
  }

  static Future<List<ScheduledAlarm>> _getScheduledAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = prefs.getString(_alarmsKey);

      if (alarmsJson == null) return [];

      final List<dynamic> decoded = jsonDecode(alarmsJson);
      return decoded.map((e) => ScheduledAlarm.fromJson(e)).toList();
    } catch (e) {
      print('Error getting scheduled alarms: $e');
      return [];
    }
  }

  static Future<void> showImmediateNotification(String title, String body, {int? id}) async {
    final androidDetails = AndroidNotificationDetails(
      'satellite_passes',
      'Satellite Passes',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
    );

    await _notifications.show(
      id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  static Future<void> cancelNotification(int id) async {
    try {
      await _alarmChannel.invokeMethod('cancelAlarm', {'id': id});

      // Remove from tracked alarms
      final prefs = await SharedPreferences.getInstance();
      final alarms = await _getScheduledAlarms();
      alarms.removeWhere((a) => a.id == id);
      final alarmsJson = jsonEncode(alarms.map((a) => a.toJson()).toList());
      await prefs.setString(_alarmsKey, alarmsJson);
    } catch (e) {
      print('Failed to cancel alarm: $e');
    }
    await _notifications.cancel(id);
  }

  static Future<void> cancelAllNotifications() async {
    try {
      await _alarmChannel.invokeMethod('cancelAllAlarms');

      // Clear tracked alarms
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_alarmsKey);
    } catch (e) {
      print('Failed to cancel all alarms: $e');
    }
    await _notifications.cancelAll();
  }

  static Future<List<ScheduledAlarm>> getScheduledAlarms() async {
    final alarms = await _getScheduledAlarms();
    final now = DateTime.now();

    // Filter out past alarms and clean up
    final validAlarms = alarms.where((a) => a.scheduledTime.isAfter(now)).toList();

    // If we filtered any out, save the cleaned list
    if (validAlarms.length != alarms.length) {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = jsonEncode(validAlarms.map((a) => a.toJson()).toList());
      await prefs.setString(_alarmsKey, alarmsJson);
    }

    return validAlarms;
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }

  static Future<int> getScheduledCount() async {
    final alarms = await getScheduledAlarms();
    return alarms.length;
  }
}