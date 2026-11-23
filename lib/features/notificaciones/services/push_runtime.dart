import 'firebase_push_transport.dart';
import 'push_coordinator.dart';

class PushRuntime {
  PushRuntime._();

  static final PushCoordinator coordinator = PushCoordinator(
    transport: FirebasePushTransport(),
  );

  static Future<bool> initialize() => coordinator.initialize();
}
