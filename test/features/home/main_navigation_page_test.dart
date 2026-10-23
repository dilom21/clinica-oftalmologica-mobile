import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/home/pages/main_navigation_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/stripe_payment_service.dart';

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

/// Pago tal como lo devuelve `GET /pagos/mis-pagos`.
Map<String, dynamic> _pago({
  required int id,
  String fecha = '2026-10-07T08:15:00',
}) => {
  'pago_id': id,
  'consulta_clinica_id': 4,
  'fecha_creacion': fecha,
  'fecha_hora_pago': fecha,
  'monto': '60.00',
  'moneda': 'BOB',
  'metodo_pago': 'EFECTIVO',
  'estado_pago': 'APROBADO',
  'pasarela': null,
  'servicios': const <Object>[],
};

int _llamadas(List<String> rutas, String ruta) =>
    rutas.where((r) => r == ruta).length;

/// Toca una pestaña de la barra inferior por su etiqueta.
Future<void> _irAPestana(WidgetTester tester, String etiqueta) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(etiqueta),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'al volver a la pestaña Pagos se actualiza el historial sin duplicar',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      _mockSecureStorage(<String, String>{'access_token': 'jwt-tenant'});

      final rutas = <String>[];
      final metodos = <String>[];
      var pagos = <Map<String, dynamic>>[_pago(id: 4)];

      final service = PagosService(
        client: MockClient((request) async {
          rutas.add(request.url.path);
          metodos.add(request.method);

          if (request.url.path == '/pagos/mis-consultas') {
            return _json(const <Object>[], 200);
          }
          if (request.url.path == '/pagos/mis-pagos') {
            return _json(pagos, 200);
          }
          return _json({'detail': 'ruta no esperada'}, 500);
        }),
        leerToken: () async => 'jwt-tenant',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MainNavigationPage(
            pagosService: service,
            stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _irAPestana(tester, 'Pagos');
      expect(_llamadas(rutas, '/pagos/mis-consultas'), 1);
      expect(
        _llamadas(rutas, '/pagos/mis-pagos'),
        0,
        reason: 'abrir la pestaña no consulta el historial todavía',
      );

      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.text('Pago #4'), findsOneWidget);
      expect(_llamadas(rutas, '/pagos/mis-pagos'), 1);

      // Recepción registra un pago mientras el paciente está en otra pestaña.
      pagos = <Map<String, dynamic>>[
        _pago(id: 5, fecha: '2026-10-09T10:00:00'),
      ];

      await _irAPestana(tester, 'Inicio');
      await _irAPestana(tester, 'Pagos');

      expect(find.text('Pago #5'), findsOneWidget);
      expect(find.text('Pago #4'), findsNothing);
      expect(
        _llamadas(rutas, '/pagos/mis-pagos'),
        2,
        reason: 'al volver a la pestaña se refresca una sola vez',
      );
      expect(
        _llamadas(rutas, '/pagos/mis-consultas'),
        1,
        reason: 'los datos frescos no se vuelven a pedir',
      );
      expect(rutas.any((r) => r.contains('/pagos/stripe/intencion')), isFalse);
      expect(metodos.toSet(), {'GET'});

      // Tocar de nuevo la pestaña ya seleccionada no genera peticiones.
      await _irAPestana(tester, 'Pagos');
      expect(_llamadas(rutas, '/pagos/mis-pagos'), 2);
    },
  );
}
