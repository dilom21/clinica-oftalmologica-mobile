import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/core/storage/token_storage.dart';
import 'package:clinica_oftalmologica_mobile/features/perfil_paciente/services/paciente_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

/// Canal real de `flutter_secure_storage`.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Sustituye la plataforma de `flutter_secure_storage` por un mapa en memoria.
///
/// `PacienteService` lee el JWT con `TokenStorage`, así que sin este mock las
/// pruebas dependerían del Keystore del dispositivo.
Map<String, String> _mockSecureStorage() {
  final datos = <String, String>{};

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return datos[call.arguments['key'] as String];
          case 'write':
            datos[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          case 'delete':
            datos.remove(call.arguments['key'] as String);
            return null;
          case 'deleteAll':
            datos.clear();
            return null;
          case 'containsKey':
            return datos.containsKey(call.arguments['key'] as String);
          case 'readAll':
            return Map<String, String>.from(datos);
          default:
            return null;
        }
      });

  return datos;
}

/// Perfil tal como lo devuelve `GET /pacientes/me` (contrato real).
Map<String, dynamic> _perfilJson({
  String? telefono = '70011223',
  String? direccion = 'Av. Siempre Viva 123',
}) => {
  'id': 7,
  'correo': 'ana@correo.com',
  'nombres': 'Ana',
  'apellidos': 'Pérez',
  'ci': '12345678',
  'fecha_nacimiento': '1990-05-14',
  'sexo': 'F',
  'telefono': telefono,
  'contacto_emergencia': null,
  'direccion': direccion,
  'estado': true,
};

PacienteService _servicio(MockClient client) => PacienteService(client: client);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> almacen;

  setUp(() async {
    almacen = _mockSecureStorage();
    await TokenStorage().saveToken('jwt-paciente');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('obtenerMiPerfil', () {
    test('envía Authorization Bearer y mapea el perfil real', () async {
      String? auth;
      String? ruta;

      final client = MockClient((request) async {
        auth = request.headers['Authorization'];
        ruta = request.url.path;
        return _json(_perfilJson(), 200);
      });

      final perfil = await _servicio(client).obtenerMiPerfil();

      expect(ruta, '/pacientes/me');
      expect(auth, 'Bearer jwt-paciente');
      expect(perfil.id, 7);
      expect(perfil.nombreCompleto, 'Ana Pérez');
      expect(perfil.correo, 'ana@correo.com');
      expect(perfil.ci, '12345678');
      expect(perfil.sexo, 'F');
      expect(perfil.estado, isTrue);
      expect(perfil.fechaNacimiento, DateTime(1990, 5, 14));
      expect(perfil.contactoEmergencia, isNull);
    });

    test('acepta campos opcionales nulos sin inventar datos', () async {
      final client = MockClient(
        (r) async => _json(_perfilJson(telefono: null, direccion: null), 200),
      );

      final perfil = await _servicio(client).obtenerMiPerfil();

      expect(perfil.telefono, isNull);
      expect(perfil.direccion, isNull);
    });

    test('un 401 usa el detail del backend y expone statusCode 401', () async {
      final client = MockClient(
        (r) async => _json({
          'detail': 'Tu sesión expiró. Vuelve a iniciar sesión.',
        }, 401),
      );

      await expectLater(
        _servicio(client).obtenerMiPerfil(),
        throwsA(
          isA<PacienteException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('sesión expiró')),
        ),
      );
    });

    test(
      'sin token no llama al backend y lanza PacienteException 401',
      () async {
        await TokenStorage().deleteToken();
        expect(almacen, isEmpty);

        var llamadas = 0;
        final client = MockClient((r) async {
          llamadas++;
          return _json(_perfilJson(), 200);
        });

        await expectLater(
          _servicio(client).obtenerMiPerfil(),
          throwsA(
            isA<PacienteException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having((e) => e.message, 'message', contains('sesión')),
          ),
        );
        expect(llamadas, 0);
      },
    );

    test('un cuerpo con formato inesperado lanza PacienteException', () async {
      final client = MockClient(
        (r) async => _json(const <Object>['no-es-un-perfil'], 200),
      );

      await expectLater(
        _servicio(client).obtenerMiPerfil(),
        throwsA(
          isA<PacienteException>().having(
            (e) => e.message,
            'message',
            contains('respuesta inesperada'),
          ),
        ),
      );
    });

    test('sin conexión lanza un mensaje entendible', () async {
      final client = MockClient((r) async {
        throw http.ClientException('sin red');
      });

      await expectLater(
        _servicio(client).obtenerMiPerfil(),
        throwsA(
          isA<PacienteException>().having(
            (e) => e.message,
            'message',
            contains('No se pudo conectar con el servidor'),
          ),
        ),
      );
    });
  });
}
