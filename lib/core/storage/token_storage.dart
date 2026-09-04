import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Responsable exclusivo del almacenamiento seguro del JWT.
///
/// Utiliza `flutter_secure_storage` (Keystore/Keychain de Android/iOS);
/// NO guarda el token en texto plano.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Clave bajo la cual se guarda el access_token.
  static const String _accessTokenKey = 'access_token';

  /// Guarda el token de acceso de forma segura.
  Future<void> saveToken(String token) {
    return _storage.write(key: _accessTokenKey, value: token);
  }

  /// Devuelve el token guardado o `null` si no existe.
  Future<String?> getToken() {
    return _storage.read(key: _accessTokenKey);
  }

  /// Elimina el token guardado (cierre de sesión).
  Future<void> deleteToken() {
    return _storage.delete(key: _accessTokenKey);
  }

  /// Indica si existe un token guardado y no vacío.
  Future<bool> hasToken() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null && token.isNotEmpty;
  }
}
