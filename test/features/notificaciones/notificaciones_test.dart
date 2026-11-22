import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/notificaciones/models/notificacion.dart';
import 'package:clinica_oftalmologica_mobile/features/notificaciones/pages/notificaciones_page.dart';
import 'package:clinica_oftalmologica_mobile/features/notificaciones/services/notificaciones_service.dart';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _item(int id, {bool leida = false, String? fecha}) => {
  'id': id,
  'titulo': 'Aviso $id',
  'mensaje': 'Mensaje $id',
  'tipo': 'CITA_CONFIRMADA',
  'fecha_creacion': fecha ?? '2026-11-21T14:30:00Z',
  'fecha_envio': null,
  'leida': leida,
  'fecha_lectura': leida ? '2026-11-21T15:00:00Z' : null,
};

Map<String, dynamic> _pagina(List<Object> items, int total, int offset) => {
  'items': items,
  'total': total,
  'limite': 20,
  'desplazamiento': offset,
};

void main() {
  test('interpreta JSON y campos opcionales', () {
    final item = Notificacion.fromJson(_item(3, fecha: 'fecha-inválida'));
    expect(item.id, 3);
    expect(item.fechaCreacion, isNull);
    expect(item.fechaEnvio, isNull);
    expect(item.leida, isFalse);
    expect(PaginaNotificaciones.fromJson(_pagina([_item(3)], 1, 0)).total, 1);
    expect(
      () => PaginaNotificaciones.fromJson({'items': 'mal'}),
      throwsFormatException,
    );
  });

  test('GET usa JWT y PATCH devuelve estado de lectura', () async {
    final rutas = <String>[];
    final service = NotificacionesService(
      leerToken: () async => 'jwt-clinica',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer jwt-clinica');
        rutas.add('${request.method} ${request.url.path}?${request.url.query}');
        if (request.method == 'PATCH') return _json(_item(1, leida: true), 200);
        return _json(_pagina([_item(1)], 1, 0), 200);
      }),
    );
    expect((await service.listar()).items.single.leida, isFalse);
    expect((await service.marcarLeida(1)).leida, isTrue);
    expect(rutas.first, 'GET /notificaciones/?limite=20&desplazamiento=0');
    expect(rutas.last, 'PATCH /notificaciones/1/leida?');
  });

  test('descarta una respuesta de un JWT anterior', () async {
    var token = 'clinica-a';
    final pendiente = Completer<http.Response>();
    final service = NotificacionesService(
      leerToken: () async => token,
      client: MockClient((_) => pendiente.future),
    );
    final futuro = service.listar();
    await Future<void>.delayed(Duration.zero);
    token = 'clinica-b';
    pendiente.complete(_json(_pagina([_item(1)], 1, 0), 200));
    await expectLater(futuro, throwsA(isA<SesionCambiadaException>()));
  });

  testWidgets('lista vacía, error de red y reintento', (tester) async {
    var falla = true;
    final service = NotificacionesService(
      leerToken: () async => 'jwt',
      client: MockClient((_) async {
        if (falla) throw http.ClientException('sin red');
        return _json(_pagina([], 0, 0), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: NotificacionesPage(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    falla = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no tienes notificaciones.'), findsOneWidget);
  });

  testWidgets('paginación sin duplicados y lectura visual', (tester) async {
    final rutas = <int>[];
    final service = NotificacionesService(
      leerToken: () async => 'jwt',
      client: MockClient((request) async {
        if (request.method == 'PATCH') return _json(_item(2, leida: true), 200);
        final offset = int.parse(
          request.url.queryParameters['desplazamiento']!,
        );
        rutas.add(offset);
        return offset == 0
            ? _json(_pagina([_item(2), _item(1)], 3, 0), 200)
            : _json(_pagina([_item(1), _item(3)], 3, 2), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: NotificacionesPage(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notificacion-2')), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active), findsNWidgets(2));
    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(rutas, [0, 2]);
    expect(find.byKey(const Key('notificacion-1')), findsOneWidget);
    expect(find.byKey(const Key('notificacion-3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('notificacion-2')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
  });

  testWidgets('401 llama al flujo de sesión expirada', (tester) async {
    var invalidaciones = 0;
    final service = NotificacionesService(
      leerToken: () async => 'jwt',
      client: MockClient((_) async => _json({'detail': 'expirado'}, 401)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotificacionesPage(
          service: service,
          onSesionInvalida: () async {
            invalidaciones++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(invalidaciones, 1);
  });
}
