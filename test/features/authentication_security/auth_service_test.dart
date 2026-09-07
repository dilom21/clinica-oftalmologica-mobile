import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/authentication_security/models/auth_models.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/services/auth_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// Construye un JWT de prueba con el `rol_id` indicado en el payload.
///
/// La firma no importa: `AuthService` solo inspecciona el payload para
/// validar el rol antes de aceptar la sesión.
String _jwtConRol(int rolId) {
  final encabezado = base64Url.encode(
    utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})),
  );
  final carga = base64Url.encode(
    utf8.encode(jsonEncode({'sub': '1', 'rol_id': rolId, 'exp': 4102444800})),
  );
  return '$encabezado.$carga.firma';
}

void main() {
  AuthService crearServicio(MockClient client) {
    return AuthService(client: client);
  }

  group('AuthService.loginPaciente (endpoint /seguridad/login)', () {
    test('publica en POST /seguridad/login con correo y password', () async {
      String? metodo;
      String? ruta;
      String? contentType;
      Map<String, dynamic>? cuerpo;
      final client = MockClient((request) async {
        metodo = request.method;
        ruta = request.url.path;
        contentType = request.headers['Content-Type'];
        cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'access_token': _jwtConRol(4), 'token_type': 'bearer'}),
          200,
          headers: _jsonHeaders,
        );
      });

      final login = await crearServicio(client).loginPaciente(
        const LoginRequest(correo: 'paciente@correo.com', password: 'clave'),
      );

      expect(metodo, 'POST');
      expect(ruta, '/seguridad/login');
      expect(contentType, startsWith('application/json'));
      expect(cuerpo, {'correo': 'paciente@correo.com', 'password': 'clave'});
      expect(login.accessToken, isNotEmpty);
    });

    test(
      'acepta la sesión cuando el JWT trae rol_id == 4 (paciente)',
      () async {
        final token = _jwtConRol(4);
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({'access_token': token, 'token_type': 'bearer'}),
            200,
            headers: _jsonHeaders,
          );
        });

        final login = await crearServicio(client).loginPaciente(
          const LoginRequest(correo: 'paciente@correo.com', password: 'clave'),
        );

        expect(login.accessToken, token);
        expect(login.tokenType, 'bearer');
      },
    );

    test('rechaza la sesión cuando el usuario autenticado no es paciente '
        '(rol_id != 4)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'access_token': _jwtConRol(1), 'token_type': 'bearer'}),
          200,
          headers: _jsonHeaders,
        );
      });

      await expectLater(
        crearServicio(client).loginPaciente(
          const LoginRequest(
            correo: 'administrador@clinica.com',
            password: 'clave',
          ),
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            AuthService.mensajeSoloParaPacientes,
          ),
        ),
      );
    });

    test(
      'rechaza la sesión cuando el JWT no trae un payload legible',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'access_token': 'encabezado.payload-invalido.firma',
              'token_type': 'bearer',
            }),
            200,
            headers: _jsonHeaders,
          );
        });

        await expectLater(
          crearServicio(client).loginPaciente(
            const LoginRequest(
              correo: 'paciente@correo.com',
              password: 'clave',
            ),
          ),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              contains('No se pudo verificar la sesión'),
            ),
          ),
        );
      },
    );

    test('respuesta 200 sin access_token lanza un error claro', () async {
      final client = MockClient((request) async {
        return http.Response('{}', 200, headers: _jsonHeaders);
      });

      await expectLater(
        crearServicio(client).loginPaciente(
          const LoginRequest(correo: 'paciente@correo.com', password: 'clave'),
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('access_token esperado'),
          ),
        ),
      );
    });

    test('una respuesta 401 usa el detail devuelto por FastAPI', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Correo o contraseña incorrectos'}),
          401,
          headers: _jsonHeaders,
        );
      });

      await expectLater(
        crearServicio(client).loginPaciente(
          const LoginRequest(
            correo: 'desconocido@correo.com',
            password: 'clave',
          ),
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Correo o contraseña incorrectos',
          ),
        ),
      );
    });
  });
}
