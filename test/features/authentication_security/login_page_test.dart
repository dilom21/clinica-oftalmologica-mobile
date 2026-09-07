import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/login/login_page.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/services/auth_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// Canal real de `flutter_secure_storage`.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Construye un JWT de prueba con el `rol_id` indicado.
String _jwtConRol(int rolId) {
  final encabezado = base64Url.encode(
    utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})),
  );
  final carga = base64Url.encode(
    utf8.encode(jsonEncode({'sub': '1', 'rol_id': rolId, 'exp': 4102444800})),
  );
  return '$encabezado.$carga.firma';
}

/// Sustituye la plataforma de `flutter_secure_storage` por un mapa en
/// memoria para poder verificar qué tokens se guardan o eliminan.
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
  testWidgets('LoginPage no inicia sesión y elimina el token cuando el usuario '
      'autenticado no es paciente', (WidgetTester tester) async {
    final almacen = <String, String>{'access_token': 'sesion-anterior'};
    _mockSecureStorage(almacen);

    final client = MockClient((request) async {
      expect(request.url.path, '/seguridad/login');
      return http.Response(
        jsonEncode({'access_token': _jwtConRol(1), 'token_type': 'bearer'}),
        200,
        headers: _jsonHeaders,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(authService: AuthService(client: client)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'medico@clinica.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-123');

    // Hay un título y un botón con el mismo texto; se pulsa el botón.
    final boton = find.text('Iniciar sesión').last;
    await tester.ensureVisible(boton);
    await tester.pump();
    await tester.tap(boton);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text(AuthService.mensajeSoloParaPacientes), findsOneWidget);
    expect(almacen, isNot(contains('access_token')));
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
