import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationServiceException implements Exception {
  final String userMessage;
  final Object? cause;

  NotificationServiceException(this.userMessage, {this.cause});

  @override
  String toString() => cause == null ? userMessage : '$userMessage ($cause)';
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'rminder_alerts';
  static const String _channelName = 'RMinder Alerts';
  static const String _channelDesc = 'Budget alerts and reminders';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      initSettings,
    );

    // Create channel on Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    bool granted = true;
    // Android 13+ runtime permission
    final status = await Permission.notification.status;
    debugPrint('[NotificationService] Permission status before request: ${status.name}');
    if (!status.isGranted) {
      final res = await Permission.notification.request();
      debugPrint('[NotificationService] Permission request result: ${res.name}');
      granted = res.isGranted;
    }
    // iOS
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    if (ios == false) granted = false;
    debugPrint('[NotificationService] Permission final granted: $granted (ios: $ios)');
    return granted;
  }

  Future<bool> isGranted() async {
    final status = await Permission.notification.status;
    debugPrint('[NotificationService] isGranted -> ${status.isGranted} (${status.name})');
    return status.isGranted;
  }

  Future<void> openSystemSettings() async {
    await openAppSettings();
  }

  Future<void> show({required int id, required String title, required String body}) async {
    debugPrint('[NotificationService] show() id=$id title=$title');
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    try {
      await _plugin.show(id, title, body, details);
      debugPrint('[NotificationService] show() dispatched');
    } catch (e) {
      debugPrint('[NotificationService] show() error: $e');
      throw NotificationServiceException('Unable to show notification right now.', cause: e);
    }
  }

  Future<void> scheduleDailyReminder({required int id, required TimeOfDay time, required String title, required String body}) async {
    // Use periodicallyShow as a simple cross-version daily reminder (fires 24h after scheduling).
    // It won't align to a specific clock time but is robust without timezone dependencies.
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      await _plugin.periodicallyShow(
        id,
        title,
        body,
        RepeatInterval.daily,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] scheduleDailyReminder() error: $e');
      throw NotificationServiceException('Unable to schedule daily reminder.', cause: e);
    }
  }
}
