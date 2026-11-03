import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/informacion_clinica/services/informacion_clinica_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

InformacionClinicaService _servicio(MockClient client) =>
    InformacionClinicaService(
      client: client,
      leerToken: () async => 'token-de-prueba',
    );

Map<String, dynamic> _respuesta() => {
  'historial_id': 10,
  'fecha_apertura': '2026-09-01T10:00:00',
  'observaciones_generales': 'Usa lentes desde 2018',
  'antecedentes': [
    {
      'id': 1,
      'tipo': 'ALERGIA',
      'descripcion': 'Penicilina',
      'fecha_registro': '2026-09-01T10:00:00',
    },
  ],
  'consultas': [
    {
      'id': 100,
      'fecha_consulta': '2026-10-01T15:00:00',
      'motivo_consulta': 'Control de glaucoma',
      'anamnesis': 'Presión ocular elevada',
      'observaciones': 'Continuar tratamiento',
      'oftalmologo': {
        'id': 1,
        'nombres': 'Salet',
        'apellidos': 'Ejemplo',
        'especialidad': 'Glaucoma',
      },
      'diagnosticos': [
        {
          'id': 1,
          'nombre': 'Glaucoma',
          'descripcion': 'Ojo derecho',
          'fecha_diagnostico': '2026-10-01T16:00:00',
        },
      ],
      'tratamientos': [
        {
          'id': 1,
          'descripcion': 'Timolol 0.5%',
          'observaciones': 'Una gota cada 12 horas',
          'fecha_inicio': '2026-10-01',
          'fecha_fin': '2026-11-01',
        },
      ],
      'indicaciones': [
        {
          'id': 1,
          'descripcion': 'No frotar los ojos',
          'fecha_registro': '2026-10-01T16:10:00',
        },
      ],
      'recetas': [
        {
          'id': 1,
          'fecha_emision': '2026-10-01T16:20:00',
          'observaciones': 'Receta vigente',
          'detalles': [
            {
              'id': 1,
              'medicamento': 'Timolol',
              'presentacion': 'Colirio',
              'dosis': '0.5%',
              'frecuencia': 'cada 12 horas',
              'duracion': '30 días',
              'indicaciones': 'Ojo derecho',
            },
          ],
        },
      ],
      'examenes': [
        {
          'id': 1,
          'nombre_examen': 'Tonometría',
          'fecha_solicitud': '2026-10-01T15:30:00',
          'observaciones': null,
          'resultados': [
            {
              'id': 1,
              'fecha_resultado': '2026-10-01T17:00:00',
              'resultado': 'PIO 22 mmHg',
            },
          ],
        },
      ],
    },
  ],
  'controles': [
    {
      'id': 1,
      'fecha_programada': '2026-11-01',
      'motivo': 'Control de presión',
      'observaciones': null,
      'estado': 'PROGRAMADO',
      'oftalmologo': {
        'id': 1,
        'nombres': 'Salet',
        'apellidos': 'Ejemplo',
        'especialidad': 'Glaucoma',
      },
    },
  ],
};

void main() {
  test('pide la ruta del paciente y mapea la información autorizada', () async {
    String? auth;
    final client = MockClient((request) async {
      auth = request.headers['Authorization'];
      expect(request.method, 'GET');
      expect(request.url.path, '/historial-clinico/mi-informacion');
      expect(request.url.query, isEmpty);
      return _json(_respuesta(), 200);
    });

    final info = await _servicio(client).consultar();

    expect(auth, 'Bearer token-de-prueba');
    expect(info.historialId, 10);
    expect(info.observacionesGenerales, 'Usa lentes desde 2018');
    expect(info.antecedentes.single.descripcion, 'Penicilina');
    expect(info.consultas.single.titulo, 'Control de glaucoma');
    expect(info.consultas.single.diagnosticos.single.nombre, 'Glaucoma');
    expect(info.consultas.single.recetas.single.detalles.single.medicamento, 'Timolol');
    expect(info.consultas.single.examenes.single.resultados.single.resultado, 'PIO 22 mmHg');
    expect(info.controles.single.motivo, 'Control de presión');
    expect(info.estaVacia, isFalse);
  });

  test('un historial vacío se reconoce como vacío', () async {
    final client = MockClient(
      (request) async => _json({
        'historial_id': null,
        'fecha_apertura': null,
        'observaciones_generales': null,
        'antecedentes': [],
        'consultas': [],
        'controles': [],
      }, 200),
    );

    final info = await _servicio(client).consultar();

    expect(info.estaVacia, isTrue);
  });

  test('401 conserva el mensaje y el código', () async {
    final client = MockClient(
      (request) async => _json({
        'detail': 'Tu sesión expiró. Vuelve a iniciar sesión.',
      }, 401),
    );

    await expectLater(
      _servicio(client).consultar(),
      throwsA(
        isA<InformacionClinicaException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('sesión')),
      ),
    );
  });

  test('sin token no llama al servidor', () async {
    var llamadas = 0;
    final client = MockClient((request) async {
      llamadas++;
      return _json(const {}, 200);
    });
    final service = InformacionClinicaService(
      client: client,
      leerToken: () async => null,
    );

    await expectLater(
      service.consultar(),
      throwsA(
        isA<InformacionClinicaException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    expect(llamadas, 0);
  });
}
