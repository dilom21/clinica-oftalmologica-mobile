import 'dart:async';

enum PushPermissionStatus { authorized, provisional, denied }

class PushMessage {
  const PushMessage({
    required this.data,
    this.messageId,
    this.title,
    this.body,
  });

  final Map<String, dynamic> data;
  final String? messageId;
  final String? title;
  final String? body;

  int? get citaId {
    final value = data['cita_id'];
    if (value is int && value > 0) return value;
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }
}

abstract interface class PushTransport {
  Future<bool> initialize();
  Future<PushPermissionStatus> requestPermission();
  Future<String?> getToken();
  Stream<String> get tokenRefreshes;
  Stream<PushMessage> get foregroundMessages;
  Stream<PushMessage> get openedMessages;
  Future<PushMessage?> getInitialMessage();
}

abstract interface class PushRegistrationStore {
  Future<PushRegistration?> read();
  Future<void> write(PushRegistration registration);
  Future<void> clear();
}

class PushRegistration {
  const PushRegistration({
    required this.deviceId,
    required this.ownerDigest,
    required this.tokenDigest,
  });

  final int deviceId;
  final String ownerDigest;
  final String tokenDigest;
}

abstract interface class PushBackend {
  Future<bool> isPushEnabled();
  Future<int> register({required String token, required String platform});
  Future<void> revoke(int deviceId);
}
