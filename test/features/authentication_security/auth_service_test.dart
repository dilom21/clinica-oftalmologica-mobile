import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/authentication_security/models/auth_models.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/services/auth_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// Construye un JWT tenant de prueba con los claims indicados.
///
/// La firma no importa: `AuthService` solo inspecciona el payload para
/// validar el rol y la clínica antes de aceptar la sesión. Por defecto emite
/// un token válido (`token_type = tenant`, `rol_nombre = Paciente` y
/// `empresa_codigo = CLN-A`); cada prueba omite o cambia lo que necesite.
String _jwt({
  int? rolId,
  String? rolNombre = 'Paciente',
  String? tokenType = 'tenant',
  String? empresaCodigo = 'CLN-A',
  Map<String, dynamic> extra = const {},
}) {
  final payload = <String, dynamic>{'sub': '1', 'exp': 4102444800, ...extra};

  if (rolId != null) {
    payload['rol_id'] = rolId;
  }
  if (rolNombre != null) {
    payload['rol_nombre'] = rolNombre;
  }
  if (tokenType != null) {
    payload['token_type'] = tokenType;
  }
  if (empresaCodigo != null) {
    payload['empresa_codigo'] = empresaCodigo;
  }

  final encabezado = base64Url.encode(
    utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})),
  );
  final carga = base64Url.encode(utf8.encode(jsonEncode(payload)));

  return '$encabezado.$carga.firma';
}

http.Response _json(Object cuerpo, int status) {
  return http.Response(jsonEncode(cuerpo), status, headers: _jsonHeaders);
}

const _empresas = [
  {'codigo': 'CLN-A', 'nombre': 'Visión Clara Norte'},
  {'codigo': 'CLN-B', 'nombre': 'Visión Clara Sur'},
];

LoginRequest _loginRequest({String empresa = 'CLN-A'}) {
  return LoginRequest(
    empresaCodigo: empresa,
    correo: 'paciente@correo.com',
    password: 'clave',
  );
}

Matcher _mensaje(String esperado) {
  return isA<AuthException>().having((e) => e.message, 'message', esperado);
}

void main() {
  group('AuthService.listarEmpresas', () {
    test('obtiene las clínicas con GET /seguridad/tenant/empresas', () async {
      String? metodo;
      String? ruta;

      final client = MockClient((request) async {
        metodo = request.method;
        ruta = request.url.path;
        return _json(_empresas, 200);
      });

      final empresas = await AuthService(client: client).listarEmpresas();

      expect(metodo, 'GET');
      expect(ruta, '/seguridad/tenant/empresas');
      expect(empresas, hasLength(2));
      expect(empresas[0].codigo, 'CLN-A');
      expect(empresas[0].nombre, 'Visión Clara Norte');
      expect(empresas[1].codigo, 'CLN-B');
    });

    test(
      'devuelve una lista vacía cuando el backend no tiene clínicas',
      () async {
        final client = MockClient((request) async => _json(const [], 200));

        final empresas = await AuthService(client: client).listarEmpresas();

        expect(empresas, isEmpty);
      },
    );

    test('ignora entradas sin código y códigos duplicados', () async {
      final client = MockClient(
        (request) async => _json(const [
          {'codigo': '', 'nombre': 'Sin código'},
          {'nombre': 'Sin código tampoco'},
          {'codigo': 'CLN-A', 'nombre': 'Visión Clara Norte'},
          {'codigo': 'CLN-A', 'nombre': 'Duplicada'},
        ], 200),
      );

      final empresas = await AuthService(client: client).listarEmpresas();

      expect(empresas, hasLength(1));
      expect(empresas.single.codigo, 'CLN-A');
    });

    test('usa el código como nombre si el nombre llega vacío', () async {
      final client = MockClient(
        (request) async => _json(const [
          {'codigo': 'CLN-C', 'nombre': ''},
        ], 200),
      );

      final empresas = await AuthService(client: client).listarEmpresas();

      expect(empresas.single.nombre, 'CLN-C');
    });

    test(
      'un 503 avisa que el servicio de clínicas no está disponible',
      () async {
        final client = MockClient((request) async => _json({}, 503));

        await expectLater(
          AuthService(client: client).listarEmpresas(),
          throwsA(
            _mensaje(
              'El servicio de clínicas no está disponible en este momento. '
              'Inténtalo más tarde.',
            ),
          ),
        );
      },
    );

    test('un error de conexión se informa con un mensaje entendible', () async {
      final client = MockClient((request) async {
        throw http.ClientException('sin red');
      });

      await expectLater(
        AuthService(client: client).listarEmpresas(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('No se pudo conectar con el servidor'),
          ),
        ),
      );
    });

    test('una respuesta que no es JSON lanza un error claro', () async {
      final client = MockClient(
        (request) async => http.Response('<html>error</html>', 200),
      );

      await expectLater(
        AuthService(client: client).listarEmpresas(),
        throwsA(
          _mensaje(
            'El servidor devolvió una respuesta inesperada. '
            'Inténtalo de nuevo.',
          ),
        ),
      );
    });
  });

  group('AuthService.loginPaciente (endpoint /seguridad/tenant/login)', () {
    test(
      'envía empresa_codigo, correo y password a /seguridad/tenant/login',
      () async {
        String? metodo;
        String? ruta;
        Map<String, dynamic>? cuerpo;

        final client = MockClient((request) async {
          metodo = request.method;
          ruta = request.url.path;
          cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'access_token': _jwt(rolNombre: 'Paciente', empresaCodigo: 'CLN-A'),
            'token_type': 'bearer',
          }, 200);
        });

        final login = await AuthService(client: client)
            .loginPaciente(_loginRequest());

        expect(metodo, 'POST');
        expect(ruta, '/seguridad/tenant/login');
        expect(cuerpo, {
          'empresa_codigo': 'CLN-A',
          'correo': 'paciente@correo.com',
          'password': 'clave',
        });
        expect(login.accessToken, isNotEmpty);
        expect(login.tokenType, 'bearer');
      },
    );

    test(
      'acepta a un paciente con rol_id = 91 y rol_nombre Paciente',
      () async {
        // Los ids de rol son propios de cada base tenant: aquí Paciente es 91.
        final client = MockClient(
          (request) async => _json({
            'access_token': _jwt(rolId: 91),
            'token_type': 'bearer',
          }, 200),
        );

        final login = await AuthService(client: client)
            .loginPaciente(_loginRequest());

        expect(login.accessToken, isNotEmpty);
      },
    );

    test('acepta a un paciente con otro rol_id válido de su clínica', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolId: 3),
          'token_type': 'bearer',
        }, 200),
      );

      final login = await AuthService(client: client)
          .loginPaciente(_loginRequest());

      expect(login.accessToken, isNotEmpty);
    });

    test('normaliza mayúsculas y espacios del rol_nombre', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolId: 91, rolNombre: '  PACIENTE '),
          'token_type': 'bearer',
        }, 200),
      );

      final login = await AuthService(client: client)
          .loginPaciente(_loginRequest());

      expect(login.accessToken, isNotEmpty);
    });

    test('rechaza a un administrador con rol_id = 4', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolId: 4, rolNombre: 'Administrador'),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeSoloParaPacientes)),
      );
    });

    test('rechaza a un oftalmólogo', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolId: 2, rolNombre: 'Oftalmólogo'),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeSoloParaPacientes)),
      );
    });

    test('rechaza a un recepcionista', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolId: 5, rolNombre: 'Recepcionista'),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeSoloParaPacientes)),
      );
    });

    test('rechaza la sesión si el JWT no trae rol_nombre', () async {
      // Aunque el rol_id sea 4, sin rol_nombre no se puede confirmar el rol.
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolId: 4, rolNombre: null),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeRolNoIdentificado)),
      );
    });

    test('no infiere el rol desde otros claims si falta rol_nombre', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(
            rolNombre: null,
            extra: const {
              'rol': 'Paciente',
              'nombre_rol': 'Paciente',
              'rol_id': 91,
            },
          ),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeRolNoIdentificado)),
      );
    });

    test('rechaza un JWT legacy sin token_type tenant', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(tokenType: null),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeSesionNoTenant)),
      );
    });

    test('rechaza un token_type distinto de tenant', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(tokenType: 'access'),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeSesionNoTenant)),
      );
    });

    test('rechaza la sesión si el JWT no trae empresa_codigo', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(empresaCodigo: null),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje(AuthService.mensajeClinicaNoIdentificada)),
      );
    });

    test('marca la sesión como rechazada para que no se guarde', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolNombre: 'Administrador'),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(
          isA<AuthException>()
              .having((e) => e.sesionRechazada, 'sesionRechazada', isTrue)
              .having(
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
        final client = MockClient(
          (request) async => _json({
            'access_token': 'encabezado.payload-invalido.firma',
            'token_type': 'bearer',
          }, 200),
        );

        await expectLater(
          AuthService(client: client).loginPaciente(_loginRequest()),
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

    test('rechaza un JWT emitido para otra clínica', () async {
      final client = MockClient(
        (request) async => _json({
          'access_token': _jwt(rolNombre: 'Paciente', empresaCodigo: 'CLN-B'),
          'token_type': 'bearer',
        }, 200),
      );

      await expectLater(
        AuthService(client: client)
            .loginPaciente(_loginRequest(empresa: 'CLN-A')),
        throwsA(_mensaje(AuthService.mensajeClinicaDistinta)),
      );
    });

    test('un 401 usa el detail devuelto por FastAPI', () async {
      final client = MockClient(
        (request) async =>
            _json({'detail': 'Correo o contraseña incorrectos'}, 401),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje('Correo o contraseña incorrectos')),
      );
    });

    test('un 403 indica que no hay permisos para esa clínica', () async {
      final client = MockClient((request) async => _json({}, 403));

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(
          _mensaje('No tienes permisos para iniciar sesión en esta clínica'),
        ),
      );
    });

    test('un 422 muestra los mensajes de validación de FastAPI', () async {
      final client = MockClient(
        (request) async => _json({
          'detail': [
            {
              'loc': ['body', 'correo'],
              'msg': 'Value error, El correo no es válido',
              'type': 'value_error',
            },
          ],
        }, 422),
      );

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(_mensaje('El correo no es válido')),
      );
    });

    test('un 503 avisa que la clínica no está disponible', () async {
      final client = MockClient((request) async => _json({}, 503));

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(
          _mensaje(
            'La clínica no está disponible en este momento. '
            'Inténtalo más tarde.',
          ),
        ),
      );
    });

    test('exige una clínica antes de enviar la petición', () async {
      var peticiones = 0;
      final client = MockClient((request) async {
        peticiones++;
        return _json({}, 200);
      });

      await expectLater(
        AuthService(client: client)
            .loginPaciente(_loginRequest(empresa: '   ')),
        throwsA(_mensaje(AuthService.mensajeClinicaRequerida)),
      );
      expect(peticiones, 0);
    });

    test('una respuesta 200 sin access_token lanza un error claro', () async {
      final client = MockClient((request) async => _json({}, 200));

      await expectLater(
        AuthService(client: client).loginPaciente(_loginRequest()),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('access_token esperado'),
          ),
        ),
      );
    });
  });

  group('AuthService.registrarPaciente', () {
    RegistroPacienteRequest request({String empresa = 'CLN-A'}) {
      return RegistroPacienteRequest(
        empresaCodigo: empresa,
        ci: '12345678',
        nombres: 'Ana',
        apellidos: 'Pérez',
        fechaNacimiento: DateTime(1998, 7, 7),
        sexo: 'F',
        telefono: '70000000',
        contactoEmergencia: 'Familiar 71111111',
        direccion: 'Av. Ejemplo 123',
        correo: 'ana@correo.com',
        password: 'ClaveSegura123!',
      );
    }

    test(
      'usa POST /seguridad/tenant/registro-paciente con empresa_codigo',
      () async {
        String? metodo;
        String? ruta;
        Map<String, dynamic>? cuerpo;

        final client = MockClient((request) async {
          metodo = request.method;
          ruta = request.url.path;
          cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'message': 'Cuenta creada correctamente'}, 201);
        });

        await AuthService(client: client).registrarPaciente(request());

        expect(metodo, 'POST');
        expect(ruta, '/seguridad/tenant/registro-paciente');
        expect(cuerpo, {
          'empresa_codigo': 'CLN-A',
          'ci': '12345678',
          'nombres': 'Ana',
          'apellidos': 'Pérez',
          'fecha_nacimiento': '1998-07-07',
          'sexo': 'F',
          'telefono': '70000000',
          'contacto_emergencia': 'Familiar 71111111',
          'direccion': 'Av. Ejemplo 123',
          'correo': 'ana@correo.com',
          'password': 'ClaveSegura123!',
        });
      },
    );

    test('nunca usa el endpoint legacy', () async {
      final rutas = <String>[];

      final client = MockClient((request) async {
        rutas.add(request.url.path);
        return _json({'message': 'Cuenta creada correctamente'}, 201);
      });

      await AuthService(client: client).registrarPaciente(request());

      expect(rutas, ['/seguridad/tenant/registro-paciente']);
      expect(rutas, isNot(contains('/seguridad/registro-paciente')));
    });

    test('no envía tenant_id, database_name, rol_id ni usuario_id', () async {
      Map<String, dynamic>? cuerpo;

      final client = MockClient((request) async {
        cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'message': 'Cuenta creada correctamente'}, 201);
      });

      await AuthService(client: client).registrarPaciente(request());

      expect(cuerpo!.containsKey('tenant_id'), isFalse);
      expect(cuerpo!.containsKey('database_name'), isFalse);
      expect(cuerpo!.containsKey('rol_id'), isFalse);
      expect(cuerpo!.containsKey('usuario_id'), isFalse);
    });

    test('normaliza el código de clínica antes de enviarlo', () async {
      Map<String, dynamic>? cuerpo;

      final client = MockClient((request) async {
        cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'message': 'Cuenta creada correctamente'}, 201);
      });

      await AuthService(client: client)
          .registrarPaciente(request(empresa: '  CLN-B  '));

      expect(cuerpo!['empresa_codigo'], 'CLN-B');
    });

    test('exige una clínica antes de enviar la petición', () async {
      var peticiones = 0;
      final client = MockClient((request) async {
        peticiones++;
        return _json({'message': 'Cuenta creada correctamente'}, 201);
      });

      await expectLater(
        AuthService(client: client).registrarPaciente(request(empresa: '   ')),
        throwsA(_mensaje(AuthService.mensajeClinicaRequerida)),
      );
      expect(peticiones, 0);
    });

    test('un 201 devuelve el mensaje del backend', () async {
      final client = MockClient(
        (request) async =>
            _json({'message': 'Cuenta creada correctamente'}, 201),
      );

      final respuesta = await AuthService(client: client)
          .registrarPaciente(request());

      expect(respuesta.message, 'Cuenta creada correctamente');
    });

    test('un 409 de paciente existente pide verificar la identidad', () async {
      final client = MockClient(
        (request) async => _json({
          'detail': 'Ya existe un paciente con estos datos en esta clínica.',
        }, 409),
      );

      await expectLater(
        AuthService(client: client).registrarPaciente(request()),
        throwsA(_mensaje(AuthService.mensajePacienteExistente)),
      );
    });

    test(
      'un 409 de correo duplicado conserva el mensaje del backend',
      () async {
        const detalle = 'El correo ya está registrado en esta clínica.';
        final client = MockClient(
          (request) async => _json({'detail': detalle}, 409),
        );

        await expectLater(
          AuthService(client: client).registrarPaciente(request()),
          throwsA(_mensaje(detalle)),
        );
      },
    );

    test('un 409 sin detalle usa un mensaje neutro de conflicto', () async {
      final client = MockClient((request) async => _json({}, 409));

      await expectLater(
        AuthService(client: client).registrarPaciente(request()),
        throwsA(_mensaje(AuthService.mensajeConflictoRegistro)),
      );
    });

    test('un 403 avisa que la suscripción no está vigente', () async {
      final client = MockClient((request) async => _json({}, 403));

      await expectLater(
        AuthService(client: client).registrarPaciente(request()),
        throwsA(_mensaje(AuthService.mensajeClinicaSinSuscripcion)),
      );
    });

    test('un 404 avisa que la clínica no existe o está inactiva', () async {
      final client = MockClient((request) async => _json({}, 404));

      await expectLater(
        AuthService(client: client).registrarPaciente(request()),
        throwsA(_mensaje(AuthService.mensajeClinicaNoDisponible)),
      );
    });

    test('un 422 muestra el detalle de validación de FastAPI', () async {
      final client = MockClient(
        (request) async => _json({
          'detail': [
            {
              'loc': ['body', 'correo'],
              'msg': 'El correo no es válido',
              'type': 'value_error',
            },
          ],
        }, 422),
      );

      await expectLater(
        AuthService(client: client).registrarPaciente(request()),
        throwsA(_mensaje('El correo no es válido')),
      );
    });

    test('un 503 avisa que la clínica no está disponible', () async {
      final client = MockClient((request) async => _json({}, 503));

      await expectLater(
        AuthService(client: client).registrarPaciente(request()),
        throwsA(
          _mensaje(
            'La clínica no está disponible en este momento. '
            'Inténtalo más tarde.',
          ),
        ),
      );
    });

    test('un error de conexión lanza un mensaje entendible', () async {
      final client = MockClient(
        (request) async => throw http.ClientException('sin red'),
      );

      await expectLater(
        AuthService(client: client).registrarPaciente(request()),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('No se pudo conectar con el servidor'),
          ),
        ),
      );
    });
  });
}
