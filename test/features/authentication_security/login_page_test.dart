import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/login/login_page.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/register/register_page.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/services/auth_service.dart';
import 'package:clinica_oftalmologica_mobile/features/home/pages/main_navigation_page.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// Canal real de `flutter_secure_storage`.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

const _empresas = [
  {'codigo': 'CLN-A', 'nombre': 'Visión Clara Norte'},
  {'codigo': 'CLN-B', 'nombre': 'Visión Clara Sur'},
];

/// Construye un JWT tenant de prueba con los claims indicados.
///
/// La firma no importa: `AuthService` solo inspecciona el payload. Por
/// defecto genera un token válido para la clínica `CLN-A`.
String _jwt({
  int? rolId,
  String? rolNombre = 'Paciente',
  String? tokenType = 'tenant',
  String? empresaCodigo = 'CLN-A',
}) {
  final payload = <String, dynamic>{'sub': '1', 'exp': 4102444800};

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

/// Sustituye la plataforma de `flutter_secure_storage` por un mapa en
/// memoria para verificar qué se guarda o elimina.
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

/// Cliente que responde el listado de clínicas y el login tenant.
MockClient _cliente({
  List<Map<String, dynamic>> empresas = _empresas,
  int empresasStatus = 200,
  String? token,
  int loginStatus = 200,
  Map<String, dynamic>? loginBody,
  List<String>? peticiones,
  Map<String, dynamic>? cuerpoLogin,
  Completer<void>? esperarEmpresas,
  int registroStatus = 201,
  Map<String, dynamic>? registroBody,
  Map<String, dynamic>? cuerpoRegistro,
  Completer<void>? esperarRegistro,
}) {
  return MockClient((request) async {
    peticiones?.add('${request.method} ${request.url.path}');

    if (request.method == 'GET' &&
        request.url.path == '/seguridad/tenant/empresas') {
      if (esperarEmpresas != null) {
        await esperarEmpresas.future;
      }

      return http.Response(
        jsonEncode(empresas),
        empresasStatus,
        headers: _jsonHeaders,
      );
    }

    if (request.method == 'POST' &&
        request.url.path == '/seguridad/tenant/login') {
      if (cuerpoLogin != null) {
        cuerpoLogin.addAll(jsonDecode(request.body) as Map<String, dynamic>);
      }

      return http.Response(
        jsonEncode(
          loginBody ??
              {'access_token': token ?? _jwt(), 'token_type': 'bearer'},
        ),
        loginStatus,
        headers: _jsonHeaders,
      );
    }

    if (request.method == 'POST' &&
        request.url.path == '/seguridad/tenant/registro-paciente') {
      if (cuerpoRegistro != null) {
        cuerpoRegistro.addAll(jsonDecode(request.body) as Map<String, dynamic>);
      }

      if (esperarRegistro != null) {
        await esperarRegistro.future;
      }

      return http.Response(
        jsonEncode(registroBody ?? {'message': 'Cuenta creada correctamente'}),
        registroStatus,
        headers: _jsonHeaders,
      );
    }

    return http.Response('{}', 404, headers: _jsonHeaders);
  });
}

Future<void> _pumpLogin(WidgetTester tester, AuthService service) async {
  await tester.pumpWidget(MaterialApp(home: LoginPage(authService: service)));

  // Deja completar la carga de clínicas y la animación de entrada.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _seleccionarClinica(WidgetTester tester, String codigo) async {
  final selector = find.byKey(const Key('login-clinica-selector'));
  await tester.ensureVisible(selector);
  await tester.pump();
  await tester.tap(selector);

  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  await tester.tap(find.byKey(Key('login-clinica-opcion-$codigo')));

  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pulsarLogin(WidgetTester tester) async {
  final boton = find.text('Iniciar sesión').last;
  await tester.ensureVisible(boton);
  await tester.pump();
  await tester.tap(boton);

  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _llenarCredenciales(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextFormField).at(0),
    'paciente@correo.com',
  );
  await tester.enterText(find.byType(TextFormField).at(1), 'clave-123');
}

/// Avanza la interfaz en pasos cortos.
///
/// `pumpAndSettle` no sirve en estas pruebas: la animación de fondo del login
/// se repite indefinidamente.
Future<void> _pumpPasos(WidgetTester tester, [int pasos = 6]) async {
  for (var i = 0; i < pasos; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Abre el registro de cuenta nueva desde el login.
Future<void> _abrirRegistro(WidgetTester tester) async {
  final boton = find.text('Crear cuenta nueva');
  await tester.ensureVisible(boton);
  await tester.pump();
  await tester.tap(boton);
  await _pumpPasos(tester, 8);
}

/// Desplaza [finder] a la vista y lo toca.
///
/// El formulario de registro es más alto que la pantalla de prueba (800x600),
/// así que hay que desplazar los campos antes de pulsarlos.
Future<void> _toque(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _pumpPasos(tester, 2);
  await tester.tap(finder);
  await _pumpPasos(tester, 4);
}

/// Completa el formulario de `RegisterPage` con datos válidos.
///
/// Los campos se buscan dentro de `RegisterPage`: la página de login sigue en
/// el árbol del `Navigator` y también tiene `TextFormField`, así que buscar por
/// índice en todo el árbol desplazaría las posiciones.
Future<void> _llenarRegistro(WidgetTester tester) async {
  final campos = find.descendant(
    of: find.byType(RegisterPage),
    matching: find.byType(TextFormField),
  );

  await tester.enterText(campos.at(0), '12345678');
  await tester.enterText(campos.at(1), 'Ana');
  await tester.enterText(campos.at(2), 'Pérez');

  // Fecha de nacimiento: el selector abre con una fecha válida por defecto.
  await _toque(tester, campos.at(3));
  await _toque(tester, find.text('Aceptar'));

  await _toque(
    tester,
    find.descendant(
      of: find.byType(RegisterPage),
      matching: find.byType(DropdownButtonFormField<String>),
    ),
  );
  await _toque(tester, find.text('Femenino').last);

  await tester.enterText(campos.at(4), '70000000');
  await tester.enterText(campos.at(5), 'Familiar 71111111');
  await tester.enterText(campos.at(6), 'Av. Ejemplo 123');
  await tester.enterText(campos.at(7), 'ana@correo.com');
  await tester.enterText(campos.at(8), 'ClaveSegura123!');
  await tester.enterText(campos.at(9), 'ClaveSegura123!');
}

/// Envía el formulario de registro.
Future<void> _pulsarRegistro(WidgetTester tester) async {
  final boton = find.byKey(const Key('register-submit'));
  await tester.ensureVisible(boton);
  await tester.pump();
  await tester.tap(boton);
  await _pumpPasos(tester, 8);
}

void main() {
  testWidgets('muestra el estado de carga y luego el selector de clínica', (
    tester,
  ) async {
    _mockSecureStorage(<String, String>{});
    final completer = Completer<void>();
    final service = AuthService(client: _cliente(esperarEmpresas: completer));

    await tester.pumpWidget(MaterialApp(home: LoginPage(authService: service)));
    await tester.pump();

    expect(find.byKey(const Key('login-clinicas-cargando')), findsOneWidget);
    expect(find.text('Cargando clínicas disponibles…'), findsOneWidget);

    completer.complete();

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('login-clinicas-cargando')), findsNothing);
    expect(find.byKey(const Key('login-clinica-selector')), findsOneWidget);
    expect(find.text('Selecciona tu clínica'), findsOneWidget);
  });

  testWidgets('muestra el error de conexión y permite reintentar', (
    tester,
  ) async {
    _mockSecureStorage(<String, String>{});
    var intentos = 0;

    final client = MockClient((request) async {
      if (request.url.path == '/seguridad/tenant/empresas') {
        intentos++;

        if (intentos == 1) {
          return http.Response('{}', 503, headers: _jsonHeaders);
        }

        return http.Response(jsonEncode(_empresas), 200, headers: _jsonHeaders);
      }

      return http.Response('{}', 404, headers: _jsonHeaders);
    });

    await _pumpLogin(tester, AuthService(client: client));

    expect(find.byKey(const Key('login-clinicas-error')), findsOneWidget);
    expect(
      find.textContaining('servicio de clínicas no está disponible'),
      findsOneWidget,
    );

    final reintentar = find.byKey(const Key('login-clinicas-reintentar'));
    await tester.ensureVisible(reintentar);
    await tester.pump();
    await tester.tap(reintentar);

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(intentos, 2);
    expect(find.byKey(const Key('login-clinicas-error')), findsNothing);
    expect(find.byKey(const Key('login-clinica-selector')), findsOneWidget);
  });

  testWidgets('no inicia sesión sin seleccionar una clínica', (tester) async {
    _mockSecureStorage(<String, String>{});
    final peticiones = <String>[];
    final service = AuthService(client: _cliente(peticiones: peticiones));

    await _pumpLogin(tester, service);
    await _llenarCredenciales(tester);
    await _pulsarLogin(tester);

    expect(
      find.text('Selecciona la clínica donde tienes tu cuenta'),
      findsWidgets,
    );
    expect(peticiones, ['GET /seguridad/tenant/empresas']);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
    'guarda el JWT de la clínica elegida y descarta la sesión previa',
    (tester) async {
      final almacen = <String, String>{
        'access_token': 'jwt-legacy',
        'empresa_codigo': 'CLN-B',
        'empresa_nombre': 'Visión Clara Sur',
      };
      _mockSecureStorage(almacen);

      final token = _jwt(rolId: 91);
      final cuerpoLogin = <String, dynamic>{};
      final service = AuthService(
        client: _cliente(token: token, cuerpoLogin: cuerpoLogin),
      );

      await _pumpLogin(tester, service);
      await _seleccionarClinica(tester, 'CLN-A');
      await _llenarCredenciales(tester);
      await _pulsarLogin(tester);

      expect(cuerpoLogin, {
        'empresa_codigo': 'CLN-A',
        'correo': 'paciente@correo.com',
        'password': 'clave-123',
      });
      expect(almacen['access_token'], token);
      expect(almacen['empresa_codigo'], 'CLN-A');
      expect(almacen['empresa_nombre'], 'Visión Clara Norte');
      expect(find.byType(MainNavigationPage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    },
  );

  testWidgets('rechaza roles administrativos y elimina la sesión anterior', (
    tester,
  ) async {
    final almacen = <String, String>{'access_token': 'jwt-legacy'};
    _mockSecureStorage(almacen);

    final service = AuthService(
      client: _cliente(token: _jwt(rolId: 1, rolNombre: 'Administrador')),
    );

    await _pumpLogin(tester, service);
    await _seleccionarClinica(tester, 'CLN-A');
    await _llenarCredenciales(tester);
    await _pulsarLogin(tester);

    expect(find.text(AuthService.mensajeSoloParaPacientes), findsOneWidget);
    expect(almacen, isEmpty);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MainNavigationPage), findsNothing);
  });

  testWidgets(
    'rechaza un JWT legacy sin token_type tenant y borra la sesión anterior',
    (tester) async {
      final almacen = <String, String>{'access_token': 'jwt-legacy'};
      _mockSecureStorage(almacen);

      final service = AuthService(
        client: _cliente(token: _jwt(tokenType: null)),
      );

      await _pumpLogin(tester, service);
      await _seleccionarClinica(tester, 'CLN-A');
      await _llenarCredenciales(tester);
      await _pulsarLogin(tester);

      expect(find.text(AuthService.mensajeSesionNoTenant), findsOneWidget);
      expect(almacen, isEmpty);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(MainNavigationPage), findsNothing);
    },
  );

  testWidgets('rechaza un JWT sin empresa_codigo y muestra un mensaje claro', (
    tester,
  ) async {
    final almacen = <String, String>{};
    _mockSecureStorage(almacen);

    final service = AuthService(
      client: _cliente(token: _jwt(empresaCodigo: null)),
    );

    await _pumpLogin(tester, service);
    await _seleccionarClinica(tester, 'CLN-A');
    await _llenarCredenciales(tester);
    await _pulsarLogin(tester);

    expect(find.text(AuthService.mensajeClinicaNoIdentificada), findsOneWidget);
    expect(almacen, isEmpty);
    expect(find.byType(MainNavigationPage), findsNothing);
  });

  testWidgets('rechaza un JWT emitido para otra clínica', (tester) async {
    final almacen = <String, String>{};
    _mockSecureStorage(almacen);

    final service = AuthService(
      client: _cliente(token: _jwt(empresaCodigo: 'CLN-B')),
    );

    await _pumpLogin(tester, service);
    await _seleccionarClinica(tester, 'CLN-A');
    await _llenarCredenciales(tester);
    await _pulsarLogin(tester);

    expect(find.text(AuthService.mensajeClinicaDistinta), findsOneWidget);
    expect(almacen, isEmpty);
    expect(find.byType(MainNavigationPage), findsNothing);
  });

  testWidgets('pide elegir la clínica antes de abrir el registro', (
    tester,
  ) async {
    _mockSecureStorage(<String, String>{});

    await _pumpLogin(tester, AuthService(client: _cliente()));
    await _abrirRegistro(tester);

    expect(find.byType(RegisterPage), findsNothing);
    expect(
      find.text('Selecciona la clínica para crear tu cuenta'),
      findsWidgets,
    );
  });

  testWidgets('abre el registro en la clínica seleccionada', (tester) async {
    _mockSecureStorage(<String, String>{});
    final peticiones = <String>[];

    await _pumpLogin(
      tester,
      AuthService(client: _cliente(peticiones: peticiones)),
    );
    await _seleccionarClinica(tester, 'CLN-B');
    await _abrirRegistro(tester);

    expect(find.byType(RegisterPage), findsOneWidget);
    expect(find.text('Visión Clara Sur'), findsWidgets);
    expect(find.text('Código de clínica: CLN-B'), findsOneWidget);
    expect(peticiones.where((p) => p.contains('registro-paciente')), isEmpty);
  });

  testWidgets('tras crear la cuenta conserva la clínica y precarga el correo', (
    tester,
  ) async {
    // La ventana de prueba por defecto (800x600) es más baja que el formulario
    // de registro: se usa una ventana alta para pulsar todos sus campos.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final almacen = <String, String>{};
    _mockSecureStorage(almacen);

    final peticiones = <String>[];
    final cuerpoRegistro = <String, dynamic>{};
    final cuerpoLogin = <String, dynamic>{};

    await _pumpLogin(
      tester,
      AuthService(
        client: _cliente(
          peticiones: peticiones,
          cuerpoRegistro: cuerpoRegistro,
          cuerpoLogin: cuerpoLogin,
        ),
      ),
    );
    await _seleccionarClinica(tester, 'CLN-A');
    await _abrirRegistro(tester);

    await _llenarRegistro(tester);
    await _pulsarRegistro(tester);

    expect(find.text('Cuenta creada correctamente'), findsOneWidget);
    expect(cuerpoRegistro['empresa_codigo'], 'CLN-A');
    expect(cuerpoRegistro['correo'], 'ana@correo.com');
    expect(
      peticiones.where((p) => p.contains('/seguridad/registro-paciente')),
      isEmpty,
    );

    await tester.tap(find.text('Ir a iniciar sesión'));
    await _pumpPasos(tester, 10);

    expect(find.byType(RegisterPage), findsNothing);
    expect(find.byType(MainNavigationPage), findsNothing);
    expect(find.text('Visión Clara Norte'), findsWidgets);
    expect(find.text('Selecciona tu clínica'), findsNothing);

    final correo = tester.widget<TextFormField>(
      find.byType(TextFormField).at(0),
    );
    expect(correo.controller?.text, 'ana@correo.com');

    // El login sigue funcionando con la clínica conservada y el correo cargado.
    await tester.enterText(find.byType(TextFormField).at(1), 'ClaveSegura123!');
    await _pulsarLogin(tester);

    expect(cuerpoLogin['empresa_codigo'], 'CLN-A');
    expect(cuerpoLogin['correo'], 'ana@correo.com');
    expect(find.byType(MainNavigationPage), findsOneWidget);
    expect(almacen, isNotEmpty);
  });
}
