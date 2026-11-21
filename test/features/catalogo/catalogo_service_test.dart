import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:clinica_oftalmologica_mobile/features/catalogo/services/catalogo_service.dart';

void main() {
  Map<String, dynamic> servicio(String nombre) => {
    'id': 1,
    'nombre': nombre,
    'descripcion': 'Detalle',
    'precio_base': 100.5,
    'duracion_estimada': 30,
    'estado': true,
  };
  test(
    'usa JWT actual y no manda empresa ni conserva catalogos anteriores',
    () async {
      String token = 'ALPHA';
      final service = CatalogoService(
        leerToken: () async => token,
        client: MockClient((r) async {
          expect(r.url.queryParameters.containsKey('empresa_id'), false);
          final empresa = r.headers['Authorization']!.split(' ').last;
          return http.Response.bytes(
            utf8.encode(jsonEncode([servicio(empresa)])),
            200,
          );
        }),
      );
      expect((await service.listar()).single.nombre, 'ALPHA');
      token = 'BETA';
      expect((await service.listar()).single.nombre, 'BETA');
    },
  );
  test('busqueda y paginacion', () async {
    final service = CatalogoService(
      leerToken: () async => 'token',
      client: MockClient((r) async {
        expect(r.url.path, '/servicios-oftalmologicos/catalogo/');
        expect(r.url.queryParameters['busqueda'], 'Consulta');
        expect(r.url.queryParameters['offset'], '20');
        return http.Response('[]', 200);
      }),
    );
    expect(await service.listar(busqueda: ' Consulta ', offset: 20), isEmpty);
  });
  test('detalle y campos opcionales', () async {
    final service = CatalogoService(
      leerToken: () async => 'token',
      client: MockClient((r) async {
        expect(r.url.path.endsWith('/1'), true);
        return http.Response(jsonEncode({'id': 1, 'nombre': 'Consulta'}), 200);
      }),
    );
    final dto = await service.detalle(1);
    expect(dto.precio, isNull);
    expect(dto.duracion, isNull);
    expect(dto.precioTexto, 'Precio por consultar');
  });
  for (final status in [401, 403, 404, 500]) {
    test('error HTTP $status', () async {
      final service = CatalogoService(
        leerToken: () async => 'token',
        client: MockClient((_) async => http.Response('', status)),
      );
      expect(
        service.listar(),
        throwsA(
          isA<CatalogoException>().having(
            (e) => e.statusCode,
            'status',
            status,
          ),
        ),
      );
    });
  }
  test('sin sesion no consulta la red', () async {
    final service = CatalogoService(
      leerToken: () async => null,
      client: MockClient((_) async => throw StateError('No debe llamar')),
    );
    expect(service.listar(), throwsA(isA<CatalogoException>()));
  });
  test('JSON malformado', () async {
    final service = CatalogoService(
      leerToken: () async => 'token',
      client: MockClient((_) async => http.Response('html', 200)),
    );
    expect(service.listar(), throwsA(isA<CatalogoException>()));
  });
}
