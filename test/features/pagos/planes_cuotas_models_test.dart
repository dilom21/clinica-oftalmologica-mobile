import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/models/pago_models.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/models/planes_cuotas_models.dart';

Map<String, dynamic> _cuotaJson({
  int id = 1,
  int numero = 1,
  Object monto = '400.00',
  String vencimiento = '2026-11-30',
  String estado = 'PENDIENTE',
  List<Map<String, dynamic>> pagos = const [],
}) => {
  'id': id,
  'numero_cuota': numero,
  'monto_programado': monto,
  'fecha_vencimiento': vencimiento,
  'estado': estado,
  'pagos': pagos,
};

Map<String, dynamic> _planJson({
  String estado = 'ACTIVO',
  List<Map<String, dynamic>>? cuotas,
  List<Map<String, dynamic>>? servicios,
}) => {
  'id': 12,
  'paciente_id': 7,
  'consulta_clinica_id': 9,
  'monto_total': '1200.00',
  'moneda': 'BOB',
  'cantidad_cuotas': 3,
  'fecha_creacion': '2026-10-01T12:00:00',
  'estado': estado,
  'observaciones': null,
  'creado_por': 2,
  'saldo_pendiente': 800,
  'monto_pagado': '400.00',
  'servicios':
      servicios ??
      [
        {
          'servicio_realizado_id': 5,
          'nombre_servicio': 'Consulta General',
          'monto_financiado': '1200.00',
          'activo': true,
        },
      ],
  'cuotas':
      cuotas ??
      [
        _cuotaJson(id: 1, numero: 1, estado: 'PAGADA'),
        _cuotaJson(id: 2, numero: 2, vencimiento: '2026-12-31'),
        _cuotaJson(id: 3, numero: 3, vencimiento: '2027-01-31'),
      ],
};

void main() {
  group('Estados', () {
    test('interpreta los estados reales del backend', () {
      expect(EstadoPlanPago.desdeApi('ACTIVO'), EstadoPlanPago.activo);
      expect(EstadoPlanPago.desdeApi('completado'), EstadoPlanPago.completado);
      expect(EstadoPlanPago.desdeApi('CANCELADO'), EstadoPlanPago.cancelado);
      expect(EstadoPlanPago.desdeApi('OTRO'), EstadoPlanPago.desconocido);

      expect(EstadoCuotaPlan.desdeApi('PENDIENTE').etiqueta, 'Pendiente');
      expect(EstadoCuotaPlan.desdeApi('VENCIDA').etiqueta, 'Vencida');
      expect(EstadoCuotaPlan.desdeApi('PAGADA').etiqueta, 'Pagada');
      expect(EstadoCuotaPlan.desdeApi('CANCELADA').etiqueta, 'Cancelada');
      expect(EstadoCuotaPlan.desdeApi(null).etiqueta, 'Estado desconocido');
    });

    test('solo un plan ACTIVO admite nuevos pagos', () {
      expect(EstadoPlanPago.activo.admiteNuevosPagos, isTrue);
      expect(EstadoPlanPago.completado.admiteNuevosPagos, isFalse);
      expect(EstadoPlanPago.cancelado.admiteNuevosPagos, isFalse);
      expect(EstadoPlanPago.desconocido.admiteNuevosPagos, isFalse);
    });

    test('una cuota VENCIDA sigue siendo cobrable', () {
      expect(EstadoCuotaPlan.pendiente.esCobrable, isTrue);
      expect(EstadoCuotaPlan.vencida.esCobrable, isTrue);
      expect(EstadoCuotaPlan.pagada.esCobrable, isFalse);
      expect(EstadoCuotaPlan.cancelada.esCobrable, isFalse);
    });
  });

  group('PlanPagoResumen', () {
    test('mapea montos como texto o número y calcula el avance', () {
      final resumen = PlanPagoResumen.fromJson({
        'id': 12,
        'paciente_id': 7,
        'consulta_clinica_id': 9,
        'monto_total': '1200.00',
        'monto_pagado': 400,
        'saldo_pendiente': '800.00',
        'moneda': 'BOB',
        'cantidad_cuotas': 3,
        'cuotas_pagadas': 1,
        'fecha_creacion': '2026-10-01T12:00:00',
        'estado': 'ACTIVO',
        'tiene_cuotas_vencidas': true,
      });

      expect(resumen.id, 12);
      expect(resumen.montoTotal, 1200);
      expect(resumen.montoPagado, 400);
      expect(resumen.saldoPendiente, 800);
      expect(resumen.estado, EstadoPlanPago.activo);
      expect(resumen.tieneCuotasVencidas, isTrue);
      expect(resumen.cuotasRestantes, 2);
      expect(resumen.porcentaje, 33);
      expect(resumen.tieneSaldo, isTrue);
    });

    test('evita divisiones inválidas cuando no hay cuotas', () {
      final resumen = PlanPagoResumen.fromJson({
        'id': 1,
        'cantidad_cuotas': 0,
        'cuotas_pagadas': 0,
        'estado': 'CANCELADO',
      });

      expect(resumen.progreso, 0);
      expect(resumen.porcentaje, 0);
      expect(resumen.cuotasRestantes, 0);
      expect(resumen.tieneSaldo, isFalse);
    });
  });

  test('PaginaPlanes mapea items y metadatos de paginación', () {
    final pagina = PaginaPlanes.fromJson({
      'items': [
        {
          'id': 12,
          'paciente_id': 7,
          'consulta_clinica_id': 9,
          'monto_total': 1200,
          'monto_pagado': 0,
          'saldo_pendiente': 1200,
          'moneda': 'BOB',
          'cantidad_cuotas': 3,
          'cuotas_pagadas': 0,
          'fecha_creacion': '2026-10-01T12:00:00',
          'estado': 'ACTIVO',
          'tiene_cuotas_vencidas': false,
        },
      ],
      'total': 1,
      'page': 1,
      'page_size': 50,
      'total_pages': 1,
    });

    expect(pagina.items, hasLength(1));
    expect(pagina.items.single.id, 12);
    expect(pagina.total, 1);
    expect(pagina.pageSize, 50);
    expect(pagina.totalPages, 1);
  });

  group('PlanPago', () {
    test('ordena las cuotas y calcula pagadas, avance y próxima cuota', () {
      final plan = PlanPago.fromJson(
        _planJson(
          cuotas: [
            _cuotaJson(id: 3, numero: 3, vencimiento: '2027-01-31'),
            _cuotaJson(id: 1, numero: 1, estado: 'PAGADA'),
            _cuotaJson(id: 2, numero: 2, vencimiento: '2026-12-31'),
          ],
        ),
      );

      expect(plan.cuotas.map((c) => c.numeroCuota), [1, 2, 3]);
      expect(plan.cuotasPagadas, 1);
      expect(plan.cuotasRestantes, 2);
      expect(plan.porcentaje, 33);
      expect(plan.admiteNuevosPagos, isTrue);
      expect(plan.proximaCuota?.numeroCuota, 2);
      expect(plan.servicios.single.nombreServicio, 'Consulta General');
      expect(plan.servicios.single.activo, isTrue);
    });

    test('detecta cuotas vencidas y planes sin nuevos pagos', () {
      final plan = PlanPago.fromJson(
        _planJson(
          estado: 'CANCELADO',
          cuotas: [
            _cuotaJson(id: 1, numero: 1, estado: 'VENCIDA'),
            _cuotaJson(id: 2, numero: 2, estado: 'CANCELADA'),
          ],
        ),
      );

      expect(plan.tieneCuotasVencidas, isTrue);
      expect(plan.admiteNuevosPagos, isFalse);
      expect(plan.cuotas.every((c) => !c.esPagableEn(plan.estado)), isTrue);
    });

    test('sin cuotas no hay próxima cuota', () {
      final plan = PlanPago.fromJson({'id': 3, 'cuotas': const []});

      expect(plan.proximaCuota, isNull);
      expect(plan.progreso, 0);
    });
  });

  group('CuotaPlan', () {
    test('solo se puede pagar con plan ACTIVO y cuota cobrable', () {
      final pendiente = CuotaPlan.fromJson(_cuotaJson());
      final vencida = CuotaPlan.fromJson(_cuotaJson(estado: 'VENCIDA'));
      final pagada = CuotaPlan.fromJson(_cuotaJson(estado: 'PAGADA'));
      final cancelada = CuotaPlan.fromJson(_cuotaJson(estado: 'CANCELADA'));

      expect(pendiente.esPagableEn(EstadoPlanPago.activo), isTrue);
      expect(vencida.esPagableEn(EstadoPlanPago.activo), isTrue);
      expect(pagada.esPagableEn(EstadoPlanPago.activo), isFalse);
      expect(cancelada.esPagableEn(EstadoPlanPago.activo), isFalse);
      expect(pendiente.esPagableEn(EstadoPlanPago.completado), isFalse);
    });

    test('mapea los intentos de pago registrados', () {
      final cuota = CuotaPlan.fromJson(
        _cuotaJson(
          pagos: [
            {
              'pago_id': 99,
              'metodo_pago': 'TARJETA',
              'estado': 'APROBADO',
              'monto': '400.00',
              'fecha_creacion': '2026-10-31T18:00:00',
              'aplicado_a_cuota': true,
            },
            {
              'pago_id': 98,
              'metodo_pago': 'TARJETA',
              'estado': 'RECHAZADO',
              'monto': 400,
              'fecha_creacion': '2026-10-30T10:00:00',
              'aplicado_a_cuota': false,
            },
          ],
        ),
      );

      expect(cuota.tieneIntentos, isTrue);
      expect(cuota.pagos, hasLength(2));
      expect(cuota.pagos.first.estado, EstadoPagoApi.aprobado);
      expect(cuota.pagos.first.aplicadoACuota, isTrue);
      expect(cuota.pagos.first.metodoPagoEtiqueta, 'Tarjeta');
      expect(cuota.pagos.last.estado, EstadoPagoApi.rechazado);
      expect(cuota.montoProgramado, 400);
      expect(cuota.fechaVencimiento, DateTime(2026, 11, 30));
    });
  });

  test('IntencionCuotaStripe mapea el contrato real', () {
    final intencion = IntencionCuotaStripe.fromJson({
      'pago_id': 99,
      'cuota_id': 2,
      'plan_pago_id': 12,
      'payment_intent_id': 'pi_123',
      'client_secret': 'pi_123_secret_abc',
      'monto': '400.00',
      'moneda': 'BOB',
      'estado_pago': 'PENDIENTE',
    });

    expect(intencion.pagoId, 99);
    expect(intencion.cuotaId, 2);
    expect(intencion.planPagoId, 12);
    expect(intencion.clientSecret, 'pi_123_secret_abc');
    expect(intencion.monto, 400);
    expect(intencion.moneda, 'BOB');
  });

  test('IntentosCuota soporta listas vacías', () {
    final intentos = IntentosCuota.fromJson({
      'cuota_id': 2,
      'estado_cuota': 'PENDIENTE',
      'intentos': const [],
    });

    expect(intentos.cuotaId, 2);
    expect(intentos.estadoCuota, EstadoCuotaPlan.pendiente);
    expect(intentos.intentos, isEmpty);
    expect(intentos.estaPagada, isFalse);
  });
}
