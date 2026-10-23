import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/core/storage/token_storage.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/models/auth_models.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/login/login_page.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/register/register_page.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/services/auth_service.dart';
import 'package:clinica_oftalmologica_mobile/features/home/pages/inicio_page.dart';
import 'package:clinica_oftalmologica_mobile/features/home/pages/main_navigation_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/stripe_payment_service.dart';
import 'package:clinica_oftalmologica_mobile/features/perfil_paciente/pages/perfil_page.dart';
import 'package:clinica_oftalmologica_mobile/features/perfil_paciente/services/paciente_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

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

/// Sesión segura de una clínica (código y nombre reales del backend).
Map<String, String> _sesionDe(String codigo, String nombre) => <String, String>{
  'access_token': 'jwt-$codigo',
  'empresa_codigo': codigo,
  'empresa_nombre': nombre,
};

/// Respuesta de `GET /pacientes/me` usada por el perfil.
const Map<String, dynamic> _perfilJson = <String, dynamic>{
  'id': 7,
  'correo': 'ana@correo.com',
  'nombres': 'Ana',
  'apellidos': 'Quispe',
  'ci': '1234567',
  'fecha_nacimiento': '1990-04-12',
  'sexo': 'F',
  'telefono': '70000000',
  'contacto_emergencia': null,
  'direccion': null,
  'estado': true,
};

/// Servicio de pagos sin red real (las pestañas no deben fallar en pruebas).
PagosService _pagosService() {
  return PagosService(
    client: MockClient((request) async {
      if (request.url.path == '/pagos/mis-consultas' ||
          request.url.path == '/pagos/mis-pagos') {
        return _json(const <Object>[], 200);
      }
      return _json({'detail': 'ruta no esperada'}, 500);
    }),
    leerToken: () async => 'jwt-tenant',
  );
}

/// Monta el área autenticada con una clave nueva para simular un login nuevo.
Future<void> _pumpApp(WidgetTester tester, {Key? key}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MainNavigationPage(
        key: key,
        pagosService: _pagosService(),
        stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Monta solo Inicio para comprobar cómo se pinta la identidad de la clínica
/// cuando no hay sesión identificada (sin disparar el área autenticada).
Future<void> _pumpInicio(WidgetTester tester, {ClinicaSesion? clinica}) async {
  await tester.pumpWidget(MaterialApp(home: InicioPage(clinica: clinica)));
  await tester.pumpAndSettle();
}

/// Avanza fotogramas sin `pumpAndSettle`: `LoginPage` anima su fondo sin parar,
/// así que `pumpAndSettle` nunca terminaría tras cerrar sesión.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('Inicio muestra el nombre real de la clínica de la sesión', (
    tester,
  ) async {
    _mockSecureStorage(_sesionDe('SAN_RAFAEL', 'Clínica San Rafael'));

    await _pumpApp(tester);

    expect(find.text('Bienvenido a Clínica San Rafael'), findsOneWidget);

    // No se usa el logotipo de una clínica concreta (el backend no lo expone).
    expect(
      find.descendant(
        of: find.byType(InicioPage),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    expect(find.textContaining('Visión Clara'), findsNothing);
  });

  testWidgets('dos clínicas distintas muestran cada una su propia identidad', (
    tester,
  ) async {
    // Sesión 1: clínica A.
    _mockSecureStorage(_sesionDe('SAN_RAFAEL', 'Clínica San Rafael'));
    await _pumpApp(tester, key: UniqueKey());

    expect(find.text('Bienvenido a Clínica San Rafael'), findsOneWidget);
    expect(find.textContaining('Centro Ocular Andino'), findsNothing);

    // Sesión 2: cierre de sesión y login en la clínica B.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await TokenStorage().deleteToken();
    await TokenStorage().saveTenantSession(
      token: 'jwt-clinica-b',
      empresaCodigo: 'CENTRO_OCULAR',
      empresaNombre: 'Centro Ocular Andino',
    );

    await _pumpApp(tester, key: UniqueKey());

    expect(find.text('Bienvenido a Centro Ocular Andino'), findsOneWidget);
    expect(find.textContaining('Clínica San Rafael'), findsNothing);
  });

  testWidgets('cerrar sesión elimina el nombre y los datos de la clínica', (
    tester,
  ) async {
    final almacen = _sesionDe('SAN_RAFAEL', 'Clínica San Rafael');
    _mockSecureStorage(almacen);

    await _pumpApp(tester, key: UniqueKey());
    expect(find.text('Bienvenido a Clínica San Rafael'), findsOneWidget);

    // Cierre de sesión: se borra el JWT junto al código y nombre de la clínica.
    await TokenStorage().deleteToken();
    expect(almacen, isEmpty);

    // La sesión ya no identifica ninguna clínica: al pintar Inicio se usa la
    // identidad genérica y no queda rastro de la clínica anterior.
    final sesion = SesionClinica();
    addTearDown(sesion.dispose);
    await sesion.cargar();
    expect(sesion.clinica, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpInicio(tester);

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.textContaining('Clínica San Rafael'), findsNothing);
  });

  testWidgets('sin sesión identificada se usa la identidad genérica', (
    tester,
  ) async {
    await _pumpInicio(tester);

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Portal del paciente'), findsOneWidget);
    expect(find.textContaining('Visión Clara'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(InicioPage),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
  });

  testWidgets('el perfil muestra la clínica y la olvida al cerrar sesión', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final almacen = _sesionDe('SAN_RAFAEL', 'Clínica San Rafael');
    _mockSecureStorage(almacen);

    final pacienteService = PacienteService(
      client: MockClient((request) async {
        if (request.url.path == '/pacientes/me') {
          return _json(_perfilJson, 200);
        }
        return _json({'detail': 'ruta no esperada'}, 500);
      }),
    );

    var identidadOlvidada = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PerfilPage(
          clinica: const ClinicaSesion(
            codigo: 'SAN_RAFAEL',
            nombre: 'Clínica San Rafael',
          ),
          pacienteService: pacienteService,
          alCerrarSesion: () => identidadOlvidada = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Información de tu cuenta'), findsOneWidget);
    expect(find.text('Clínica'), findsOneWidget);
    expect(find.text('Clínica San Rafael'), findsOneWidget);
    expect(find.text('Ana Quispe'), findsOneWidget);

    await tester.ensureVisible(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await _pumpFrames(tester);

    expect(identidadOlvidada, isTrue);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Clínica San Rafael'), findsNothing);
    expect(almacen, isEmpty);
  });

  testWidgets('el registro usa el nombre real de la clínica, no uno fijo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: RegisterPage(
          empresa: const EmpresaTenant(
            codigo: 'CENTRO_OCULAR',
            nombre: 'Centro Ocular Andino',
          ),
          authService: AuthService(
            client: MockClient((_) async => _json({'message': 'ok'}, 201)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Centro Ocular Andino'), findsWidgets);
    expect(find.textContaining('Visión Clara'), findsNothing);
  });
}

