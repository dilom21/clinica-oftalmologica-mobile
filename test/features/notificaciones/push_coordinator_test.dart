import 'dart:async';

import 'package:clinica_oftalmologica_mobile/core/storage/token_storage.dart';
import 'package:clinica_oftalmologica_mobile/features/notificaciones/services/push_coordinator.dart';
import 'package:clinica_oftalmologica_mobile/features/notificaciones/services/push_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> secureValues;
  late FakeTransport transport;
  late FakeBackend backend;
  late MemoryRegistrationStore registrations;
  late PushCoordinator coordinator;

  setUp(() async {
    secureValues = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
          final key = call.arguments?['key'] as String?;
          switch (call.method) {
            case 'read':
              return secureValues[key];
            case 'write':
              secureValues[key!] = call.arguments['value'] as String;
            case 'delete':
              secureValues.remove(key);
          }
          return null;
        });
    await TokenStorage().saveTenantSession(
      token: 'jwt-paciente-a',
      empresaCodigo: 'CLINICA_A',
    );
    transport = FakeTransport();
    backend = FakeBackend();
    registrations = MemoryRegistrationStore();
    coordinator = PushCoordinator(
      transport: transport,
      backend: backend,
      store: registrations,
      platform: 'ANDROID',
    );
  });

  tearDown(() async {
    await transport.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  test(
    'inicializa una sola vez y acepta permiso autorizado o provisional',
    () async {
      expect(await coordinator.initialize(), isTrue);
      expect(await coordinator.initialize(), isTrue);
      await coordinator.activateAuthenticatedPatient();
      expect(transport.initializeCalls, 1);
      expect(backend.registeredTokens, ['token-fcm-sintetico-largo-00000001']);

      final provisional = PushCoordinator(
        transport: FakeTransport(permission: PushPermissionStatus.provisional),
        backend: FakeBackend(),
        store: MemoryRegistrationStore(),
        platform: 'IOS',
      );
      await provisional.initialize();
      await provisional.activateAuthenticatedPatient();
    },
  );

  test(
    'no registra con permiso denegado, token ausente o push desactivado',
    () async {
      transport.permission = PushPermissionStatus.denied;
      await coordinator.initialize();
      await coordinator.activateAuthenticatedPatient();
      expect(backend.registeredTokens, isEmpty);

      transport.permission = PushPermissionStatus.authorized;
      transport.token = null;
      await coordinator.activateAuthenticatedPatient();
      expect(backend.registeredTokens, isEmpty);

      transport.token = 'token-fcm-sintetico-largo-00000001';
      backend.pushEnabled = false;
      await coordinator.activateAuthenticatedPatient();
      expect(backend.registeredTokens, isEmpty);
    },
  );

  test(
    'requiere sesión paciente persistida y evita registros duplicados',
    () async {
      await TokenStorage().deleteSession();
      await coordinator.initialize();
      await coordinator.activateAuthenticatedPatient();
      expect(backend.registeredTokens, isEmpty);

      await TokenStorage().saveTenantSession(
        token: 'jwt-paciente-a',
        empresaCodigo: 'CLINICA_A',
      );
      await coordinator.activateAuthenticatedPatient();
      await coordinator.activateAuthenticatedPatient();
      expect(backend.registeredTokens, hasLength(1));
      expect(registrations.value?.deviceId, 41);
    },
  );

  test(
    'token refresh actualiza registro sin exponer token en errores',
    () async {
      await coordinator.initialize();
      await coordinator.activateAuthenticatedPatient();
      transport.refreshes.add('token-renovado-sintetico-largo-00000002');
      await pumpEventQueue();
      expect(backend.registeredTokens, hasLength(2));
      expect(
        registrations.value?.tokenDigest,
        isNot(contains('token-renovado')),
      );

      backend.failRegister = true;
      transport.refreshes.add('token-secreto-que-no-debe-aparecer-00000003');
      await pumpEventQueue();
    },
  );

  test('revoca antes de logout y conserva pendiente si falla la red', () async {
    await coordinator.initialize();
    await coordinator.activateAuthenticatedPatient();
    await coordinator.revokeBeforeLogout();
    expect(backend.revokedIds, [41]);
    expect(registrations.value, isNull);

    await coordinator.activateAuthenticatedPatient();
    backend.failRevoke = true;
    await coordinator.revokeBeforeLogout();
    expect(registrations.value, isNotNull);
  });

  test('cambio de cuenta nunca reutiliza dispositivo anterior', () async {
    await coordinator.initialize();
    await coordinator.activateAuthenticatedPatient();
    final firstOwner = registrations.value!.ownerDigest;
    await coordinator.beforeSessionReplacement();
    await TokenStorage().saveTenantSession(
      token: 'jwt-paciente-b',
      empresaCodigo: 'CLINICA_B',
    );
    await coordinator.activateAuthenticatedPatient();
    expect(backend.revokedIds, [41]);
    expect(registrations.value!.ownerDigest, isNot(firstOwner));
  });

  test(
    'foreground deduplica y aperturas solo aceptan cita_id positivo',
    () async {
      await coordinator.initialize();
      final foreground = <PushMessage>[];
      final opened = <int>[];
      coordinator.foregroundMessages.listen(foreground.add);
      coordinator.openedCitaIds.listen(opened.add);

      const valid = PushMessage(
        messageId: 'm-1',
        data: {'cita_id': '17', 'route': 'https://malicioso.example'},
      );
      transport.foreground.add(valid);
      transport.foreground.add(valid);
      transport.opened.add(const PushMessage(data: {'cita_id': 18}));
      transport.opened.add(const PushMessage(data: {'cita_id': 0}));
      transport.opened.add(const PushMessage(data: {'cita_id': -1}));
      transport.opened.add(const PushMessage(data: {'cita_id': 'abc'}));
      transport.opened.add(
        const PushMessage(data: {'route': '/perfil', 'url': 'https://x.test'}),
      );
      await pumpEventQueue();
      expect(foreground, hasLength(1));
      expect(opened, [18]);
    },
  );

  test(
    'mensaje terminated válido queda pendiente hasta montar navegación',
    () async {
      transport.initialMessage = const PushMessage(data: {'cita_id': '22'});
      await coordinator.initialize();
      expect(coordinator.takePendingCitaId(), 22);
      expect(coordinator.takePendingCitaId(), isNull);
    },
  );
}

class FakeTransport implements PushTransport {
  FakeTransport({this.permission = PushPermissionStatus.authorized});
  int initializeCalls = 0;
  bool available = true;
  String? token = 'token-fcm-sintetico-largo-00000001';
  PushPermissionStatus permission;
  PushMessage? initialMessage;
  final refreshes = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return available;
  }

  @override
  Future<PushPermissionStatus> requestPermission() async => permission;
  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> get tokenRefreshes => refreshes.stream;
  @override
  Stream<PushMessage> get foregroundMessages => foreground.stream;
  @override
  Stream<PushMessage> get openedMessages => opened.stream;
  @override
  Future<PushMessage?> getInitialMessage() async => initialMessage;

  Future<void> close() async {
    await refreshes.close();
    await foreground.close();
    await opened.close();
  }
}

class FakeBackend implements PushBackend {
  bool pushEnabled = true;
  bool failRegister = false;
  bool failRevoke = false;
  final registeredTokens = <String>[];
  final revokedIds = <int>[];

  @override
  Future<bool> isPushEnabled() async => pushEnabled;
  @override
  Future<int> register({
    required String token,
    required String platform,
  }) async {
    if (failRegister) throw Exception('Registro no disponible');
    registeredTokens.add(token);
    return 40 + registeredTokens.length;
  }

  @override
  Future<void> revoke(int deviceId) async {
    if (failRevoke) throw Exception('Red no disponible');
    revokedIds.add(deviceId);
  }
}

class MemoryRegistrationStore implements PushRegistrationStore {
  PushRegistration? value;
  @override
  Future<PushRegistration?> read() async => value;
  @override
  Future<void> write(PushRegistration registration) async =>
      value = registration;
  @override
  Future<void> clear() async => value = null;
}
