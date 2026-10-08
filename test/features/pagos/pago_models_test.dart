import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/models/pago_models.dart';

ServicioRealizadoPago _servicio(
  int id,
  String nombre,
  double? precio,
  EstadoServicioPago estado,
) {
  return ServicioRealizadoPago(
    servicioRealizadoId: id,
    servicioId: id,
    nombreServicio: nombre,
    fechaRealizacion: null,
    precioAplicado: precio,
    estadoPago: estado,
  );
}

void main() {
  group('ConsultaPago.fromJson', () {
    test('parsea campos y arma el nombre del oftalmólogo', () {
      final consulta = ConsultaPago.fromJson(const {
        'consulta_id': 4,
        'fecha_consulta': '2026-09-01T10:30:00',
        'oftalmologo': {'id': 2, 'nombres': 'Carlos', 'apellidos': 'Ruiz'},
        'cantidad_servicios': 3,
        'cantidad_pendientes': 2,
        'total_pendiente': '210.00',
      });

      expect(consulta.consultaId, 4);
      expect(consulta.fechaConsulta, DateTime.parse('2026-09-01T10:30:00'));
      expect(consulta.oftalmologo, 'Carlos Ruiz');
      expect(consulta.cantidadServicios, 3);
      expect(consulta.cantidadPendientes, 2);
      expect(consulta.totalPendiente, 210.0);
      expect(consulta.tienePendientes, isTrue);
    });

    test('monto numérico, dates/imágenes ausentes', () {
      final consulta = ConsultaPago.fromJson(const {
        'consulta_id': 1,
        'cantidad_servicios': 0,
        'cantidad_pendientes': 0,
        'total_pendiente': 0,
      });

      expect(consulta.consultaId, 1);
      expect(consulta.fechaConsulta, isNull);
      expect(consulta.oftalmologo, isNull);
      expect(consulta.totalPendiente, 0);
      expect(consulta.tienePendientes, isFalse);
      expect(consulta.tieneServicios, isFalse);
    });
  });

  group('ServicioRealizadoPago.fromJson', () {
    test('interpreta PENDIENTE/PAGADO y precios como texto o número', () {
      final pendiente = ServicioRealizadoPago.fromJson(const {
        'servicio_realizado_id': 5,
        'servicio_id': 1,
        'nombre_servicio': 'Consulta General Oftalmológica',
        'fecha_realizacion': '2026-09-01T10:30:00',
        'precio_aplicado': '150.00',
        'estado_pago': 'PENDIENTE',
      });
      final pagado = ServicioRealizadoPago.fromJson(const {
        'servicio_realizado_id': 3,
        'servicio_id': 3,
        'nombre_servicio': 'Servicio pagado',
        'precio_aplicado': 100,
        'estado_pago': 'PAGADO',
      });

      expect(pendiente.estaPendiente, isTrue);
      expect(pendiente.estaPagado, isFalse);
      expect(pendiente.precio, 150.0);
      expect(pendiente.estadoPago, EstadoServicioPago.pendiente);
      expect(pendiente.estadoPago.etiqueta, 'Pendiente');

      expect(pagado.estaPagado, isTrue);
      expect(pagado.estaPendiente, isFalse);
      expect(pagado.precio, 100.0);
      expect(pagado.estadoPago.etiqueta, 'Pagado');
    });
  });

  group('selección y total', () {
    final servicios = [
      _servicio(5, 'Consulta General', 150, EstadoServicioPago.pendiente),
      _servicio(6, 'Refracción', 60, EstadoServicioPago.pendiente),
      _servicio(3, 'Ya pagado', 100, EstadoServicioPago.pagado),
      _servicio(7, 'Sin precio', null, EstadoServicioPago.pendiente),
    ];

    test('solo los pendientes con precio son seleccionables', () {
      expect(esServicioSeleccionable(servicios[0]), isTrue);
      expect(esServicioSeleccionable(servicios[1]), isTrue);
      expect(esServicioSeleccionable(servicios[2]), isFalse);
      expect(esServicioSeleccionable(servicios[3]), isFalse);
      expect(idsSeleccionables(servicios), {5, 6});
    });

    test('el total ignora pagados y no seleccionables', () {
      expect(totalSeleccionado(servicios, {5}), 150.0);
      expect(totalSeleccionado(servicios, {5, 6}), 210.0);
      // Un id pagado seleccionado por error nunca suma.
      expect(totalSeleccionado(servicios, {5, 3}), 150.0);
      expect(totalSeleccionado(servicios, <int>{}), 0.0);
    });
  });

  group('EstadoPagoApi / EstadoPago', () {
    test('mapea los estados reales del backend', () {
      expect(EstadoPagoApi.desdeApi('APROBADO'), EstadoPagoApi.aprobado);
      expect(EstadoPagoApi.desdeApi('pendiente'), EstadoPagoApi.pendiente);
      expect(EstadoPagoApi.desdeApi('RECHAZADO'), EstadoPagoApi.rechazado);
      expect(EstadoPagoApi.desdeApi('ANULADO'), EstadoPagoApi.anulado);
      expect(EstadoPagoApi.desdeApi('REEMBOLSADO'), EstadoPagoApi.reembolsado);
      expect(EstadoPagoApi.desdeApi('otro'), EstadoPagoApi.desconocido);
      expect(EstadoPagoApi.desdeApi(null), EstadoPagoApi.desconocido);
      expect(EstadoPagoApi.aprobado.esAprobado, isTrue);
      expect(EstadoPagoApi.pendiente.esPendiente, isTrue);
    });

    test('EstadoPago.aprobado solo es true si el backend confirma', () {
      final aprobado = EstadoPago.fromJson(const {
        'pago_id': 99,
        'consulta_clinica_id': 4,
        'estado_pago': 'APROBADO',
        'monto': '210.00',
        'moneda': 'BOB',
        'payment_intent_id': 'pi_123',
      });
      final pendiente = EstadoPago.fromJson(const {
        'pago_id': 99,
        'consulta_clinica_id': 4,
        'estado_pago': 'PENDIENTE',
        'monto': '210.00',
        'moneda': 'BOB',
      });

      expect(aprobado.aprobado, isTrue);
      expect(aprobado.monto, 210.0);
      expect(aprobado.paymentIntentId, 'pi_123');
      expect(pendiente.aprobado, isFalse);
      expect(pendiente.paymentIntentId, isNull);
    });
  });

  group('formato', () {
    test('formatearMonto y formatearFecha', () {
      expect(formatearMonto(210), '210.00');
      expect(formatearMonto(60.5), '60.50');
      expect(formatearFecha(DateTime(2026, 9, 1)), '01/09/2026');
      expect(formatearFecha(null), 'Fecha no disponible');
    });

    test('simboloMoneda y formatearMontoConMoneda', () {
      expect(simboloMoneda('BOB'), 'Bs');
      expect(simboloMoneda('usd'), 'US\$');
      expect(simboloMoneda('EUR'), '€');
      expect(simboloMoneda(null), 'Bs');
      expect(simboloMoneda('PEN'), 'PEN');
      expect(formatearMontoConMoneda('BOB', 210), 'Bs 210.00');
      expect(formatearMontoConMoneda('BOB', 60.5), 'Bs 60.50');
    });

    test('formatearFechaHoraBolivia aplica UTC-4', () {
      // 01:46 UTC => 21:46 del día anterior en Bolivia.
      expect(
        formatearFechaHoraBolivia(DateTime.utc(2026, 10, 8, 1, 46, 30)),
        '07/10/2026 21:46',
      );
      // Fecha ISO sin zona (el backend envía UTC): se interpreta como UTC.
      expect(
        formatearFechaHoraBolivia(DateTime.parse('2026-10-08T01:46:00')),
        '07/10/2026 21:46',
      );
      expect(formatearFechaHoraBolivia(null), 'Fecha no disponible');
    });
  });

  group('PagoHistorial.fromJson', () {
    test('mapea campos, servicios y campos opcionales', () {
      final pago = PagoHistorial.fromJson(const {
        'pago_id': 2,
        'consulta_clinica_id': 4,
        'fecha_creacion': '2026-10-08T01:44:29+00:00',
        'fecha_hora_pago': '2026-10-08T01:46:30+00:00',
        'monto': '210.00',
        'moneda': 'BOB',
        'metodo_pago': 'TARJETA',
        'estado_pago': 'APROBADO',
        'pasarela': 'STRIPE',
        'servicios': [
          {
            'servicio_realizado_id': 5,
            'nombre_servicio': 'Consulta General Oftalmológica',
            'monto_aplicado': '150.00',
          },
          {
            'servicio_realizado_id': 6,
            'nombre_servicio': 'Medición de Lentes',
            'monto_aplicado': '60.00',
          },
        ],
      });

      expect(pago.pagoId, 2);
      expect(pago.consultaClinicaId, 4);
      expect(pago.tieneConsulta, isTrue);
      expect(pago.monto, 210.0);
      expect(pago.moneda, 'BOB');
      expect(pago.metodoPagoEtiqueta, 'Tarjeta');
      expect(pago.estadoPago, EstadoPagoApi.aprobado);
      expect(pago.aprobado, isTrue);
      expect(pago.pasarela, 'STRIPE');
      expect(pago.servicios, hasLength(2));
      expect(pago.servicios.first.servicioRealizadoId, 5);
      expect(pago.servicios.first.montoAplicado, 150.0);
    });

    test('maneja nulls: consulta, fecha de pago y pasarela', () {
      final pago = PagoHistorial.fromJson(const {
        'pago_id': 1,
        'consulta_clinica_id': null,
        'fecha_creacion': '2026-10-06T10:00:00',
        'fecha_hora_pago': null,
        'monto': 210,
        'moneda': 'BOB',
        'metodo_pago': 'TARJETA',
        'estado_pago': 'PENDIENTE',
        'pasarela': null,
        'servicios': [],
      });

      expect(pago.consultaClinicaId, isNull);
      expect(pago.tieneConsulta, isFalse);
      expect(pago.fechaHoraPago, isNull);
      expect(pago.pasarela, isNull);
      expect(pago.aprobado, isFalse);
      expect(pago.servicios, isEmpty);
      expect(pago.fechaMostrar, DateTime.parse('2026-10-06T10:00:00'));
      expect(pago.estadoPago, EstadoPagoApi.pendiente);
    });

    test('interpreta todos los estados del backend', () {
      for (final estado in const [
        'PENDIENTE',
        'APROBADO',
        'RECHAZADO',
        'ANULADO',
        'REEMBOLSADO',
      ]) {
        final Map<String, dynamic> json = {
          'pago_id': 1,
          'fecha_creacion': '2026-10-06T10:00:00',
          'monto': '10.00',
          'moneda': 'BOB',
          'metodo_pago': 'TARJETA',
          'estado_pago': estado,
          'servicios': const <Object>[],
        };
        final pago = PagoHistorial.fromJson(json);

        expect(pago.estadoPago, EstadoPagoApi.desdeApi(estado));
        expect(pago.aprobado, estado == 'APROBADO');
      }
    });
  });

  group('ordenarHistorialPorFechaDesc', () {
    PagoHistorial pago(int id, String fecha) => PagoHistorial.fromJson({
      'pago_id': id,
      'consulta_clinica_id': 1,
      'fecha_creacion': fecha,
      'monto': '10.00',
      'moneda': 'BOB',
      'metodo_pago': 'TARJETA',
      'estado_pago': 'APROBADO',
      'servicios': const <Object>[],
    });

    test('ordena del más reciente al más antiguo', () {
      final ordenado = ordenarHistorialPorFechaDesc([
        pago(1, '2026-10-01T10:00:00'),
        pago(3, '2026-10-03T10:00:00'),
        pago(2, '2026-10-02T10:00:00'),
      ]);

      expect(ordenado.map((p) => p.pagoId).toList(), [3, 2, 1]);
    });

    test('usa el id como desempate y no muta la lista original', () {
      final original = [
        pago(1, '2026-10-01T10:00:00'),
        pago(2, '2026-10-01T10:00:00'),
      ];
      final ordenado = ordenarHistorialPorFechaDesc(original);

      expect(ordenado.map((p) => p.pagoId).toList(), [2, 1]);
      expect(original.map((p) => p.pagoId).toList(), [1, 2]);
    });
  });
}
