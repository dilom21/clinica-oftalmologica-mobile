import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_transport.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } on FirebaseException {
    // Sin configuración Firebase legítima no se procesa el mensaje.
  }
  // El isolate de fondo no navega ni toca interfaz o sesión.
}

class FirebasePushTransport implements PushTransport {
  FirebasePushTransport({FirebaseMessaging? messaging})
    : _injectedMessaging = messaging;

  final FirebaseMessaging? _injectedMessaging;
  FirebaseMessaging get _messaging =>
      _injectedMessaging ?? FirebaseMessaging.instance;
  static Future<bool>? _initialization;

  @override
  Future<bool> initialize() => _initialization ??= _initializeOnce();

  Future<bool> _initializeOnce() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
      return true;
    } on FirebaseException {
      return false;
    }
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => PushPermissionStatus.authorized,
      AuthorizationStatus.provisional => PushPermissionStatus.provisional,
      _ => PushPermissionStatus.denied,
    };
  }

  @override
  Future<String?> getToken() async {
    final registration = _messaging.onRegistered.first.timeout(
      const Duration(seconds: 15),
      onTimeout: () => '',
    );
    await _messaging.register();
    final value = await registration;
    return value.trim().isEmpty ? null : value;
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onRegistered;

  @override
  Stream<PushMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage.map(_convert);

  @override
  Stream<PushMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map(_convert);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _convert(message);
  }

  PushMessage _convert(RemoteMessage message) => PushMessage(
    data: Map<String, dynamic>.from(message.data),
    messageId: message.messageId,
    title: message.notification?.title,
    body: message.notification?.body,
  );
}
