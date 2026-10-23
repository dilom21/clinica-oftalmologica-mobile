import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
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

/// Simula un almacenamiento seguro que no está disponible.
void _mockSecureStorageConFallo() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        throw PlatformException(
          code: 'keystore_no_disponible',
          message: 'El almacenamiento seguro no está disponible',
        );
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test('cargar expone la clínica real guardada junto al JWT', () async {
    _mockSecureStorage(<String, String>{
      'access_token': 'jwt-clinica-a',
      'empresa_codigo': 'SAN_RAFAEL',
      'empresa_nombre': 'Clínica San Rafael',
    });

    final sesion = SesionClinica();
    addTearDown(sesion.dispose);

    expect(sesion.clinica, isNull);
    expect(sesion.cargada, isFalse);

    await sesion.cargar();

    expect(sesion.cargada, isTrue);
    expect(
      sesion.clinica,
      const ClinicaSesion(
        codigo: 'SAN_RAFAEL',
        nombre: 'Clínica San Rafael',
      ),
    );
    expect(sesion.clinica!.etiqueta, 'Clínica San Rafael');
  });

  test('sin sesión guardada no se inventa ninguna clínica', () async {
    _mockSecureStorage(<String, String>{});

    final sesion = SesionClinica();
    addTearDown(sesion.dispose);

    await sesion.cargar();

    expect(sesion.cargada, isTrue);
    expect(sesion.clinica, isNull);
  });

  test('usa el código de la clínica cuando el backend no envió nombre', () async {
    _mockSecureStorage(<String, String>{
      'access_token': 'jwt-clinica-b',
      'empresa_codigo': 'CENTRO_OCULAR',
    });

    final sesion = SesionClinica();
    addTearDown(sesion.dispose);
    await sesion.cargar();

    expect(sesion.clinica!.etiqueta, 'CENTRO_OCULAR');
  });

  test('limpiar olvida la clínica anterior y avisa a la interfaz', () async {
    _mockSecureStorage(<String, String>{
      'access_token': 'jwt-clinica-a',
      'empresa_codigo': 'SAN_RAFAEL',
      'empresa_nombre': 'Clínica San Rafael',
    });

    final sesion = SesionClinica();
    addTearDown(sesion.dispose);

    var avisos = 0;
    sesion.addListener(() => avisos++);

    await sesion.cargar();
    expect(sesion.clinica, isNotNull);
    expect(avisos, 1);

    // El cierre de sesión borra el almacenamiento y olvida la identidad.
    await TokenStorage().deleteToken();
    sesion.limpiar();

    expect(sesion.clinica, isNull);
    expect(avisos, 2);

    // Volver a cargar tampoco recupera la clínica anterior.
    await sesion.cargar();
    expect(sesion.clinica, isNull);
  });

  test('un fallo del almacenamiento no rompe la app', () async {
    _mockSecureStorageConFallo();

    final sesion = SesionClinica();
    addTearDown(sesion.dispose);

    await sesion.cargar();

    expect(sesion.cargada, isTrue);
    expect(sesion.clinica, isNull);
  });
}
