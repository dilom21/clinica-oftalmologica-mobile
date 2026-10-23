import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/core/storage/token_storage.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/login/login_page.dart';
import 'package:clinica_oftalmologica_mobile/features/perfil_paciente/pages/perfil_page.dart';
import 'package:clinica_oftalmologica_mobile/features/perfil_paciente/services/paciente_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

/// Canal real de `flutter_secure_storage`.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Sustituye la plataforma de `flutter_secure_storage` por un mapa en memoria
/// (el perfil y el cierre de sesión usan `TokenStorage`).
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
Map<String, dynamic> _perfilJson() => {
  'id': 7,
  'correo': 'ana@correo.com',
  'nombres': 'Ana',
  'apellidos': 'Pérez',
  'ci': '12345678',
  'fecha_nacimiento': '1990-05-14',
  'sexo': 'F',
  'telefono': '70011223',
  'contacto_emergencia': null,
  'direccion': 'Av. Siempre Viva 123',
  'estado': true,
};

const ClinicaSesion _clinicaSanRafael = ClinicaSesion(
  codigo: 'SAN_RAFAEL',
  nombre: 'Clínica San Rafael',
);

/// Monta el perfil con un cliente HTTP simulado.
Future<void> _pump(
  WidgetTester tester, {
  required MockClient client,
  ClinicaSesion? clinica = _clinicaSanRafael,
  VoidCallback? alCerrarSesion,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: PerfilPage(
        clinica: clinica,
        pacienteService: PacienteService(client: client),
        alCerrarSesion: alCerrarSesion,
      ),
    ),
  );
}

/// Avanza fotogramas sin `pumpAndSettle`: `LoginPage` anima su fondo sin parar,
/// así que `pumpAndSettle` nunca terminaría tras salir del perfil.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> almacen;

  setUp(() async {
    almacen = _mockSecureStorage();
    await TokenStorage().saveTenantSession(
      token: 'jwt-paciente',
      empresaCodigo: 'SAN_RAFAEL',
      empresaNombre: 'Clínica San Rafael',
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('muestra el perfil real y la clínica de la sesión', (
    tester,
  ) async {
    await _pump(
      tester,
      client: MockClient((request) async {
        expect(request.url.path, '/pacientes/me');
        expect(request.headers['Authorization'], 'Bearer jwt-paciente');
        return _json(_perfilJson(), 200);
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('ana@correo.com'), findsOneWidget);
    expect(find.text('12345678'), findsOneWidget);
    expect(find.text('Clínica San Rafael'), findsOneWidget);
    expect(find.text('Información de tu cuenta'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('sin clínica identificada no inventa el nombre de otra clínica', (
    tester,
  ) async {
    await _pump(
      tester,
      clinica: null,
      client: MockClient((r) async => _json(_perfilJson(), 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Clínica'), findsNothing);
    expect(find.textContaining('San Rafael'), findsNothing);
  });

  testWidgets('un 401 borra la sesión, olvida la clínica y vuelve al Login', (
    tester,
  ) async {
    var cerroSesion = false;

    await _pump(
      tester,
      alCerrarSesion: () => cerroSesion = true,
      client: MockClient(
        (r) async => _json({'detail': 'Token inválido o expirado'}, 401),
      ),
    );
    await _pumpFrames(tester);

    expect(cerroSesion, isTrue);
    expect(almacen, isEmpty);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Ana Pérez'), findsNothing);
  });

  testWidgets('un error de red permite reintentar y recarga el perfil', (
    tester,
  ) async {
    var fallo = true;

    await _pump(
      tester,
      client: MockClient((r) async {
        if (fallo) {
          fallo = false;
          throw http.ClientException('sin red');
        }
        return _json(_perfilJson(), 200);
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('No se pudo cargar tu perfil'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('No se pudo cargar tu perfil'), findsNothing);
  });
}
