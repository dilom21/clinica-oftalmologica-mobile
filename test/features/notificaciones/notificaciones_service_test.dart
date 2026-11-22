import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/core/storage/token_storage.dart';
import 'package:clinica_oftalmologica_mobile/features/notificaciones/services/notificaciones_service.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> storage;

  setUp(() async {
    storage = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final key = call.arguments?['key'] as String?;
          if (call.method == 'read') {
            return storage[key];
          }
          if (call.method == 'write') {
            storage[key!] = call.arguments['value'] as String;
          }
          if (call.method == 'delete') {
            storage.remove(key);
          }
          return null;
        });
    await TokenStorage().saveToken('jwt-paciente');
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  test('registra dispositivo con contrato exacto y sin IDs tenant', () async {
    late Map<String, dynamic> body;
    final service = NotificacionesService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/notificaciones/dispositivos');
        expect(request.headers['Authorization'], 'Bearer jwt-paciente');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 8,
            'plataforma': 'ANDROID',
            'activo': true,
            'fecha_registro': '2026-11-21T12:00:00Z',
            'fecha_actualizacion': '2026-11-21T12:00:00Z',
          }),
          200,
        );
      }),
    );

    final device = await service.registrarDispositivo(
      tokenFcm: 'fcm-token-sintetico-00000000000000000001',
      plataforma: 'ANDROID',
    );
    expect(device.id, 8);
    expect(body.keys, {'token_fcm', 'plataforma'});
    expect(body, isNot(contains('usuario_id')));
    expect(body, isNot(contains('tenant_id')));
  });

  test('sin sesión no llama HTTP ni registra dispositivo', () async {
    await TokenStorage().deleteToken();
    var calls = 0;
    final service = NotificacionesService(
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.registrarDispositivo(
        tokenFcm: 'fcm-token-sintetico-00000000000000000001',
        plataforma: 'IOS',
      ),
      throwsA(
        isA<NotificacionesException>().having(
          (e) => e.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(calls, 0);
  });

  test('rechaza token vacío sin llamada HTTP', () async {
    var calls = 0;
    final service = NotificacionesService(
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.registrarDispositivo(tokenFcm: ' ', plataforma: 'ANDROID'),
      throwsA(isA<NotificacionesException>()),
    );
    expect(calls, 0);
  });

  test('lista bandeja paginada y conserva cita permitida', () async {
    final service = NotificacionesService(
      client: MockClient((request) async {
        expect(request.url.queryParameters, {'page': '2', 'page_size': '10'});
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 4,
                'tipo': 'CITA_CREADA',
                'titulo': 'Cita registrada',
                'cuerpo': 'Revisa tu cita.',
                'datos': {'cita_id': 17, 'ruta': '/citas/17'},
                'cita_id': 17,
                'leida': false,
                'fecha_lectura': null,
                'fecha_creacion': '2026-11-21T12:00:00Z',
              },
            ],
            'total': 11,
            'page': 2,
            'page_size': 10,
            'total_pages': 2,
          }),
          200,
        );
      }),
    );
    final result = await service.listar(page: 2, pageSize: 10);
    expect(result.total, 11);
    expect(result.items.single.citaIdNavegable, 17);
  });

  test('actualiza preferencias con booleanos reales y revoca por id', () async {
    final methods = <String>[];
    final service = NotificacionesService(
      client: MockClient((request) async {
        methods.add('${request.method} ${request.url.path}');
        if (request.method == 'DELETE') return http.Response('', 204);
        expect(jsonDecode(request.body), {'push_habilitado': false});
        return http.Response(
          jsonEncode({
            'push_habilitado': false,
            'citas_creadas': true,
            'citas_confirmadas': true,
            'citas_reprogramadas': true,
            'citas_canceladas': true,
            'recordatorios': true,
            'fecha_actualizacion': '2026-11-21T12:00:00Z',
          }),
          200,
        );
      }),
    );
    final prefs = await service.actualizarPreferencias({
      'push_habilitado': false,
    });
    await service.revocarDispositivo(8);
    expect(prefs.pushHabilitado, isFalse);
    expect(methods, [
      'PUT /notificaciones/preferencias',
      'DELETE /notificaciones/dispositivos/8',
    ]);
  });

  test('expone 403 sin filtrar token en el error', () async {
    const fcm = 'fcm-token-sintetico-00000000000000000001';
    final service = NotificacionesService(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({'detail': 'Se requiere el rol Paciente'}),
          403,
        ),
      ),
    );
    await expectLater(
      service.registrarDispositivo(tokenFcm: fcm, plataforma: 'ANDROID'),
      throwsA(
        isA<NotificacionesException>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.toString(), 'message', isNot(contains(fcm))),
      ),
    );
  });
}
