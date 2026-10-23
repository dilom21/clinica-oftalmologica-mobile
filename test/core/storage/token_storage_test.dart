import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/core/storage/token_storage.dart';

/// Canal real de `flutter_secure_storage`.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Sustituye la plataforma de `flutter_secure_storage` por un mapa en memoria.
void _mockSecureStorage(Map<String, String> almacen) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return almacen[call.arguments['key'] as String];
          case 'write':
            almacen[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          case 'delete':
            almacen.remove(call.arguments['key'] as String);
            return null;
          case 'deleteAll':
            almacen.clear();
            return null;
          case 'containsKey':
            return almacen.containsKey(call.arguments['key'] as String);
          case 'readAll':
            return Map<String, String>.from(almacen);
          default:
            return null;
        }
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saveTenantSession guarda el JWT junto al código y nombre de la clínica',
    () async {
      final almacen = <String, String>{};
      _mockSecureStorage(almacen);

      await TokenStorage().saveTenantSession(
        token: 'jwt-clinica-a',
        empresaCodigo: 'CLN-A',
        empresaNombre: 'Visión Clara Norte',
      );

      expect(await TokenStorage().getToken(), 'jwt-clinica-a');
      expect(await TokenStorage().getEmpresaCodigo(), 'CLN-A');
      expect(await TokenStorage().getEmpresaNombre(), 'Visión Clara Norte');
    },
  );

  test(
    'saveTenantSession descarta el JWT legacy y la clínica anterior',
    () async {
      final almacen = <String, String>{
        'access_token': 'jwt-legacy',
        'empresa_codigo': 'CLN-B',
        'empresa_nombre': 'Visión Clara Sur',
      };
      _mockSecureStorage(almacen);

      await TokenStorage().saveTenantSession(
        token: 'jwt-clinica-a',
        empresaCodigo: 'CLN-A',
        empresaNombre: 'Visión Clara Norte',
      );

      expect(almacen['access_token'], 'jwt-clinica-a');
      expect(almacen['empresa_codigo'], 'CLN-A');
      expect(almacen['empresa_nombre'], 'Visión Clara Norte');
      expect(almacen, hasLength(3));
    },
  );

  test(
    'deleteToken también borra la clínica autenticada (cierre de sesión)',
    () async {
      final almacen = <String, String>{
        'access_token': 'jwt-clinica-a',
        'empresa_codigo': 'CLN-A',
        'empresa_nombre': 'Visión Clara Norte',
      };
      _mockSecureStorage(almacen);

      await TokenStorage().deleteToken();

      expect(almacen, isEmpty);
      expect(await TokenStorage().hasToken(), isFalse);
      expect(await TokenStorage().getEmpresaCodigo(), isNull);
    },
  );

  test('hasToken refleja si existe una sesión guardada', () async {
    final almacen = <String, String>{};
    _mockSecureStorage(almacen);

    expect(await TokenStorage().hasToken(), isFalse);

    await TokenStorage().saveTenantSession(
      token: 'jwt-clinica-a',
      empresaCodigo: 'CLN-A',
    );

    expect(await TokenStorage().hasToken(), isTrue);
    expect(await TokenStorage().getEmpresaNombre(), isNull);
  });
}
