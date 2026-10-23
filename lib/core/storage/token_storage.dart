import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Responsable exclusivo del almacenamiento seguro de la sesión.
///
/// Utiliza `flutter_secure_storage` (Keystore/Keychain de Android/iOS);
/// NO guarda el JWT ni los datos de la clínica en texto plano.
///
/// Además del JWT tenant guarda el código y el nombre de la clínica con la
/// que se inició sesión. Así la app sabe a qué clínica pertenece el token y
/// no reutiliza datos de una sesión anterior (legacy u otra clínica): al
/// guardar una sesión nueva se elimina primero todo lo anterior.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Clave bajo la cual se guarda el access_token.
  static const String _accessTokenKey = 'access_token';

  /// Clave de la clínica autenticada (código interno de empresa).
  static const String _empresaCodigoKey = 'empresa_codigo';

  /// Clave del nombre comercial de la clínica autenticada.
  static const String _empresaNombreKey = 'empresa_nombre';

  /// Guarda el token de acceso de forma segura.
  ///
  /// El login multitenant usa [saveTenantSession] para guardar el JWT junto a
  /// la clínica; este método se conserva para usos puntuales.
  Future<void> saveToken(String token) {
    return _storage.write(key: _accessTokenKey, value: token);
  }

  /// Devuelve el token guardado o `null` si no existe.
  Future<String?> getToken() {
    return _storage.read(key: _accessTokenKey);
  }

  /// Guarda una sesión tenant completa.
  ///
  /// Solo debe llamarse después de que `AuthService` haya validado el JWT
  /// tenant (`token_type = "tenant"`, `rol_nombre = "Paciente"` y
  /// `empresa_codigo` de la clínica elegida): la app nunca persiste un token
  /// que no pudo validar.
  ///
  /// Elimina primero cualquier JWT legacy o de otra clínica y luego escribe
  /// el token con el código/nombre de la clínica autenticada. De este modo un
  /// cambio de clínica nunca reutiliza el token anterior.
  Future<void> saveTenantSession({
    required String token,
    required String empresaCodigo,
    String? empresaNombre,
  }) async {
    await deleteSession();

    await _storage.write(key: _accessTokenKey, value: token);
    await _storage.write(key: _empresaCodigoKey, value: empresaCodigo);

    if (empresaNombre != null && empresaNombre.isNotEmpty) {
      await _storage.write(key: _empresaNombreKey, value: empresaNombre);
    }
  }

  /// Código de la clínica con la que se inició sesión (o `null` si no hay
  /// sesión tenant guardada).
  Future<String?> getEmpresaCodigo() {
    return _storage.read(key: _empresaCodigoKey);
  }

  /// Nombre comercial de la clínica autenticada.
  Future<String?> getEmpresaNombre() {
    return _storage.read(key: _empresaNombreKey);
  }

  /// Elimina la sesión completa (JWT + clínica).
  ///
  /// Se mantiene el nombre [deleteToken] porque es el usado por el cierre de
  /// sesión y por el manejo de sesiones expiradas.
  Future<void> deleteToken() {
    return deleteSession();
  }

  /// Borra el JWT y los datos de la clínica autenticada.
  Future<void> deleteSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _empresaCodigoKey);
    await _storage.delete(key: _empresaNombreKey);
  }

  /// Indica si existe un token guardado y no vacío.
  Future<bool> hasToken() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null && token.isNotEmpty;
  }
}
