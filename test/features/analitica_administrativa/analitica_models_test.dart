import 'package:flutter_test/flutter_test.dart';
import 'package:clinica_oftalmologica_mobile/features/analitica_administrativa/models/analitica_models.dart';

void main() {
  test('preserva SUPPRESSED y null sin convertirlos a cero', () {
    final value = ValorAgregado.fromJson(<String, dynamic>{
      'valor': null,
      'estado_dato': 'SUPPRESSED',
    });
    expect(value.valor, isNull);
    expect(value.estado, EstadoDato.suppressed);
  });

  test('filtros serializan contrato exacto y no incluyen tenant', () {
    final filtros = FiltrosProgresivos(
      fechaDesde: DateTime(2026, 1, 1),
      fechaHasta: DateTime(2026, 1, 31),
      granularidad: Granularidad.semana,
      estado: 'ATENDIDA',
    );
    expect(filtros.toQuery(), <String, String>{
      'fecha_desde': '2026-01-01',
      'fecha_hasta': '2026-01-31',
      'granularidad': 'semana',
      'estado': 'ATENDIDA',
    });
    expect(
      filtros.toJson(indicador: 'citas_creadas').keys,
      isNot(contains(anyOf('tenant_id', 'empresa_id'))),
    );
  });

  test('rechaza rangos mayores a 366 días', () {
    final filtros = FiltrosProgresivos(
      fechaDesde: DateTime(2025, 1, 1),
      fechaHasta: DateTime(2026, 1, 3),
    );
    expect(filtros.toQuery, throwsFormatException);
  });

  test('pronóstico contiene solo puntos proyectados del contrato', () {
    final model = PronosticoDemanda.fromJson(<String, dynamic>{
      'estado': 'READY',
      'horizonte_semanas': 4,
      'metodo': 'SEASONAL_NAIVE',
      'intervalo': 'EMPIRICO',
      'metricas': null,
      'rango_historico_inicio': '2026-01-01',
      'rango_historico_fin': '2026-08-01',
      'calidad_historica': <String, dynamic>{
        'semanas_ok': 20,
        'semanas_zero': 1,
        'semanas_suppressed': 2,
        'semanas_partial': 0,
        'semanas_not_covered': 0,
      },
      'pronosticos': <Object>[
        <String, dynamic>{
          'inicio_semana': '2026-08-03',
          'fin_semana': '2026-08-09',
          'valor_pronosticado': 8,
          'limite_inferior': 5,
          'limite_superior': 11,
          'calidad_datos': 'FORECAST',
        },
      ],
      'advertencias': <String>[],
    });
    expect(model.listo, isTrue);
    expect(model.pronosticos.single.valor, 8);
  });

  test('ML bloqueado conserva variables y no expone probabilidades', () {
    final model = EstadoModeloInasistencia.fromJson(<String, dynamic>{
      'estado': 'TRAINING_DISABLED',
      'calidad': 'BLOQUEADO_POR_DATOS',
      'modelo_habilitado': false,
      'prediccion_habilitada': false,
      'algoritmos_disponibles': <String>['BASELINE'],
      'variables_permitidas': <String>['dia_semana'],
      'variables_excluidas': <String>['diagnostico'],
      'razones_bloqueo': <String>['Q09'],
      'advertencias': <String>[],
    });
    expect(model.prediccionHabilitada, isFalse);
    expect(model.variablesExcluidas, contains('diagnostico'));
  });
}
