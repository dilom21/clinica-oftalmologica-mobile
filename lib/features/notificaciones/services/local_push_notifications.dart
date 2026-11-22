import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_transport.dart';

class LocalPushNotifications {
  LocalPushNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void>? _initialization;

  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_clinica'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(settings: settings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      const channel = AndroidNotificationChannel(
        'clinica_push_channel',
        'Notificaciones de la clínica',
        description: 'Avisos de citas y actividad de la clínica.',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await android?.createNotificationChannel(channel);
    }
  }

  static Future<void> show(PushMessage message) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    await initialize();

    final title = _nonEmpty(message.title) ?? 'Clínica Oftalmológica';

    final body = _nonEmpty(message.body) ?? 'Tienes una nueva notificación.';

    final notificationId =
        (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) &
        0x7fffffff;

    await _plugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'clinica_push_channel',
          'Notificaciones de la clínica',
          channelDescription: 'Avisos de citas y actividad de la clínica.',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: 'ic_stat_clinica',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.citaId?.toString(),
    );
  }

  static String? _nonEmpty(String? value) {
    final result = value?.trim();

    if (result == null || result.isEmpty) {
      return null;
    }

    return result;
  }
}
