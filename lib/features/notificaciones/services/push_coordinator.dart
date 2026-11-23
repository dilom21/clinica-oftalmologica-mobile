import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/storage/token_storage.dart';
import 'notificaciones_service.dart';
import 'push_transport.dart';

class SecurePushRegistrationStore implements PushRegistrationStore {
  SecurePushRegistrationStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _deviceKey = 'push_device_id';
  static const _ownerKey = 'push_owner_digest';
  static const _tokenKey = 'push_token_digest';

  @override
  Future<PushRegistration?> read() async {
    final values = await Future.wait([
      _storage.read(key: _deviceKey),
      _storage.read(key: _ownerKey),
      _storage.read(key: _tokenKey),
    ]);
    final id = int.tryParse(values[0] ?? '');
    if (id == null || id <= 0 || values[1] == null || values[2] == null) {
      return null;
    }
    return PushRegistration(
      deviceId: id,
      ownerDigest: values[1]!,
      tokenDigest: values[2]!,
    );
  }

  @override
  Future<void> write(PushRegistration registration) async {
    await _storage.write(key: _deviceKey, value: '${registration.deviceId}');
    await _storage.write(key: _ownerKey, value: registration.ownerDigest);
    await _storage.write(key: _tokenKey, value: registration.tokenDigest);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _deviceKey);
    await _storage.delete(key: _ownerKey);
    await _storage.delete(key: _tokenKey);
  }
}

class NotificacionesPushBackend implements PushBackend {
  NotificacionesPushBackend({NotificacionesService? service})
    : _service = service ?? NotificacionesService();
  final NotificacionesService _service;

  @override
  Future<bool> isPushEnabled() async =>
      (await _service.obtenerPreferencias()).pushHabilitado;

  @override
  Future<int> register({
    required String token,
    required String platform,
  }) async => (await _service.registrarDispositivo(
    tokenFcm: token,
    plataforma: platform,
  )).id;

  @override
  Future<void> revoke(int deviceId) => _service.revocarDispositivo(deviceId);
}

class PushCoordinator {
  PushCoordinator({
    required this._transport,
    PushBackend? backend,
    PushRegistrationStore? store,
    TokenStorage? tokenStorage,
    String? platform,
  }) : _backend = backend ?? NotificacionesPushBackend(),
       _store = store ?? SecurePushRegistrationStore(),
       _tokenStorage = tokenStorage ?? TokenStorage(),
       _platform = platform ?? (Platform.isIOS ? 'IOS' : 'ANDROID');

  final PushTransport _transport;
  final PushBackend _backend;
  final PushRegistrationStore _store;
  final TokenStorage _tokenStorage;
  final String _platform;
  final _foregroundController = StreamController<PushMessage>.broadcast();
  final _openController = StreamController<int>.broadcast();
  final Set<String> _seenMessages = <String>{};
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<PushMessage>? _foregroundSubscription;
  StreamSubscription<PushMessage>? _openedSubscription;
  bool _initialized = false;
  bool _activating = false;
  int? _pendingCitaId;

  Stream<PushMessage> get foregroundMessages => _foregroundController.stream;
  Stream<int> get openedCitaIds => _openController.stream;
  bool get initialized => _initialized;

  int? takePendingCitaId() {
    final value = _pendingCitaId;
    _pendingCitaId = null;
    return value;
  }

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _transport.initialize();
    if (!_initialized) return false;
    _tokenSubscription ??= _transport.tokenRefreshes.listen(
      _registerTokenSafely,
    );
    _foregroundSubscription ??= _transport.foregroundMessages.listen((message) {
      if (_isDuplicate(message)) return;
      _foregroundController.add(message);
    });
    _openedSubscription ??= _transport.openedMessages.listen(_openSafely);
    final initial = await _transport.getInitialMessage();
    if (initial != null) _openSafely(initial);
    return true;
  }

  Future<void> activateAuthenticatedPatient() async {
    if (!_initialized || _activating) return;
    _activating = true;
    try {
      final owner = await _ownerDigest();
      if (owner == null) return;
      final existing = await _store.read();
      if (existing != null && existing.ownerDigest != owner) {
        // Nunca se reutiliza el id de otra cuenta con el JWT actual.
        await _store.clear();
      }
      if (!await _backend.isPushEnabled()) return;
      final permission = await _transport.requestPermission();
      if (permission == PushPermissionStatus.denied) return;
      final token = await _transport.getToken();
      if (token == null || token.trim().isEmpty) return;
      await _registerToken(token);
    } on Exception {
      // Push no impide usar una sesión válida; se reintentará en otro arranque.
    } finally {
      _activating = false;
    }
  }

  Future<void> beforeSessionReplacement() => revokeBeforeLogout();

  Future<void> revokeBeforeLogout() async {
    final registration = await _store.read();
    if (registration == null) return;
    try {
      await _backend.revoke(registration.deviceId);
      await _store.clear();
    } on Exception {
      // Se conserva como revocación pendiente de esta cuenta, pero el logout
      // continúa. Nunca se usa para registrar otra cuenta.
    }
  }

  Future<void> _registerTokenSafely(String token) async {
    try {
      if (await _backend.isPushEnabled()) await _registerToken(token);
    } on Exception {
      // Renovación best-effort; no se imprime ni propaga el token.
    }
  }

  Future<void> _registerToken(String token) async {
    final owner = await _ownerDigest();
    if (owner == null) return;
    final tokenDigest = _digest(token);
    final existing = await _store.read();
    if (existing != null &&
        existing.ownerDigest == owner &&
        existing.tokenDigest == tokenDigest) {
      return;
    }
    final id = await _backend.register(token: token, platform: _platform);
    await _store.write(
      PushRegistration(
        deviceId: id,
        ownerDigest: owner,
        tokenDigest: tokenDigest,
      ),
    );
  }

  Future<String?> _ownerDigest() async {
    final token = await _tokenStorage.getToken();
    final company = await _tokenStorage.getEmpresaCodigo();
    if (token == null || token.isEmpty || company == null || company.isEmpty) {
      return null;
    }
    return _digest('$company\u0000$token');
  }

  String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

  bool _isDuplicate(PushMessage message) {
    final id = message.messageId;
    return id != null && id.isNotEmpty && !_seenMessages.add(id);
  }

  void _openSafely(PushMessage message) {
    if (_isDuplicate(message)) return;
    final citaId = message.citaId;
    if (citaId == null) return;
    if (_openController.hasListener) {
      _openController.add(citaId);
    } else {
      _pendingCitaId = citaId;
    }
  }
}
