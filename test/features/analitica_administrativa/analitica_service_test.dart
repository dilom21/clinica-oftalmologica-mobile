import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:clinica_oftalmologica_mobile/features/analitica_administrativa/models/analitica_models.dart';
import 'package:clinica_oftalmologica_mobile/features/analitica_administrativa/services/analitica_service.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

void main() {
  test('GET kpis envía JWT y filtros sin IDs tenant', () async {
    late http.Request captured;
    final service = AnaliticaService(
      client: MockClient((request) async {
        captured = request;
        return jsonResponse(<String, dynamic>{
          'fecha_desde': '2026-01-01',
          'fecha_hasta': '2026-01-31',
          'zona_horaria': 'America/La_Paz',
          'indicadores': <Object>[],
          'distribucion_estados': <Object>[],
          'advertencias': <String>[],
        });
      }),
      leerToken: () async => 'admin-jwt',
    );
    await service.kpis(
      FiltrosProgresivos(
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 1, 31),
      ),
    );
    expect(captured.url.path, '/reportes/progresivos/kpis');
    expect(captured.headers['Authorization'], 'Bearer admin-jwt');
    expect(
      captured.url.queryParameters.keys,
      isNot(contains(anyOf('tenant_id', 'empresa_id'))),
    );
  });

  test('exportación usa body real, MIME y filename', () async {
    late http.Request captured;
    final service = AnaliticaService(
      client: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          <int>[1, 2, 3],
          200,
          headers: <String, String>{
            'content-type': 'text/csv; charset=utf-8',
            'content-disposition': 'attachment; filename="citas_creadas.csv"',
          },
        );
      }),
      leerToken: () async => 'admin-jwt',
    );
    final result = await service.exportar(
      'csv',
      'citas_creadas',
      FiltrosProgresivos(
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 1, 31),
      ),
    );
    expect(captured.method, 'POST');
    expect(jsonDecode(captured.body), <String, dynamic>{
      'fecha_desde': '2026-01-01',
      'fecha_hasta': '2026-01-31',
      'granularidad': 'dia',
      'indicador': 'citas_creadas',
    });
    expect(result.nombre, 'citas_creadas.csv');
    expect(result.mime, contains('text/csv'));
  });

  test('403 es acceso denegado y no lista vacía', () async {
    final service = AnaliticaService(
      client: MockClient(
        (_) async =>
            jsonResponse(<String, dynamic>{'detail': 'Sin permiso'}, 403),
      ),
      leerToken: () async => 'jwt',
    );
    expect(
      service.catalogo(),
      throwsA(
        isA<AnaliticaException>().having(
          (e) => e.accesoDenegado,
          'accesoDenegado',
          true,
        ),
      ),
    );
  });

  test('valida horizonte antes de llamar HTTP', () async {
    var calls = 0;
    final service = AnaliticaService(
      client: MockClient((_) async {
        calls++;
        return jsonResponse(<String, dynamic>{});
      }),
      leerToken: () async => 'jwt',
    );
    await expectLater(service.pronostico(horizonte: 13), throwsFormatException);
    expect(calls, 0);
  });
}
