// Modelos de CU32 (consultar planes de pago) y CU33 (consultar y pagar
// cuotas) del módulo Pagos.
//
// Corresponden EXACTAMENTE a los schemas reales de FastAPI del módulo
// `gestion_pagos` (verificados en el backend, no inventados):
//
// - GET  /pagos/mis-planes                       -> PlanesPagoPagina
// - GET  /pagos/mis-planes/{plan_id}             -> PlanPagoRespuesta
// - POST /pagos/cuotas/{cuota_id}/stripe/intencion
//                                                -> IntencionCuotaStripeRespuesta
// - GET  /pagos/cuotas/{cuota_id}/intentos       -> IntentosCuotaRespuesta
// - GET  /pagos/stripe/pagos/{pago_id}/estado    -> EstadoPagoStripeRespuesta
//                                                   (modelo en `pago_models`)
//
// El backend NO calcula intereses, recargos ni abonos parciales: cada cuota se
// paga completa por su `monto_programado`. La app no recalcula ningún importe;
// solo muestra lo que devuelve FastAPI.

import 'pago_models.dart';

/// Convierte un valor JSON numérico o textual a `double`.
double? _aDouble(Object? valor) {
  if (valor is num) return valor.toDouble();
  if (valor is String) return double.tryParse(valor);
  return null;
}

/// Convierte un valor JSON numérico o textual a `int`.
int _aInt(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) return int.tryParse(valor) ?? 0;
  return 0;
}

/// Convierte una fecha ISO-8601 en [DateTime]; `null` si no es válida.
DateTime? _aFecha(Object? valor) {
  if (valor is String && valor.isNotEmpty) return DateTime.tryParse(valor);
  return null;
}

/// Devuelve los objetos JSON contenidos en [valor] (vacío si no es lista).
List<Map<String, dynamic>> _aMapas(Object? valor) {
  if (valor is! List) return const <Map<String, dynamic>>[];

  return <Map<String, dynamic>>[
    for (final item in valor)
      if (item is Map<String, dynamic>) item,
  ];
}

/// Estado del plan de pago (`estado`).
///
/// Valores reales del backend (`EstadoPlan`): `ACTIVO`, `COMPLETADO`,
/// `CANCELADO`. Solo un plan ACTIVO admite nuevos pagos de cuotas
/// (`_validar_cuota_cobrable` en el backend).
enum EstadoPlanPago {
  activo,
  completado,
  cancelado,
  desconocido;

  /// Interpreta el `estado` devuelto por el backend.
  static EstadoPlanPago desdeApi(String? valor) {
    switch (valor?.trim().toUpperCase()) {
      case 'ACTIVO':
        return EstadoPlanPago.activo;
      case 'COMPLETADO':
        return EstadoPlanPago.completado;
      case 'CANCELADO':
        return EstadoPlanPago.cancelado;
      default:
        return EstadoPlanPago.desconocido;
    }
  }

  /// Etiqueta legible para el paciente.
  String get etiqueta {
    switch (this) {
      case EstadoPlanPago.activo:
        return 'Activo';
      case EstadoPlanPago.completado:
        return 'Completado';
      case EstadoPlanPago.cancelado:
        return 'Cancelado';
      case EstadoPlanPago.desconocido:
        return 'Estado desconocido';
    }
  }

  /// Solo un plan ACTIVO permite pagar cuotas (regla del backend).
  bool get admiteNuevosPagos => this == EstadoPlanPago.activo;
}

/// Estado de una cuota (`estado`).
///
/// Valores reales del backend (`EstadoCuota`): `PENDIENTE`, `VENCIDA`,
/// `PAGADA`, `CANCELADA`. El backend deriva `VENCIDA` cuando la cuota sigue
/// PENDIENTE y su vencimiento ya pasó; una cuota VENCIDA sí es cobrable.
enum EstadoCuotaPlan {
  pendiente,
  vencida,
  pagada,
  cancelada,
  desconocida;

  /// Interpreta el `estado` devuelto por el backend.
  static EstadoCuotaPlan desdeApi(String? valor) {
    switch (valor?.trim().toUpperCase()) {
      case 'PENDIENTE':
        return EstadoCuotaPlan.pendiente;
      case 'VENCIDA':
        return EstadoCuotaPlan.vencida;
      case 'PAGADA':
        return EstadoCuotaPlan.pagada;
      case 'CANCELADA':
        return EstadoCuotaPlan.cancelada;
      default:
        return EstadoCuotaPlan.desconocida;
    }
  }

  /// Etiqueta legible para el paciente.
  String get etiqueta {
    switch (this) {
      case EstadoCuotaPlan.pendiente:
        return 'Pendiente';
      case EstadoCuotaPlan.vencida:
        return 'Vencida';
      case EstadoCuotaPlan.pagada:
        return 'Pagada';
      case EstadoCuotaPlan.cancelada:
        return 'Cancelada';
      case EstadoCuotaPlan.desconocida:
        return 'Estado desconocido';
    }
  }

  /// Indica si la cuota ya está pagada.
  bool get estaPagada => this == EstadoCuotaPlan.pagada;

  /// Indica si la cuota admite cobro (PENDIENTE o VENCIDA, nunca PAGADA ni
  /// CANCELADA). El plan también debe estar ACTIVO.
  bool get esCobrable =>
      this == EstadoCuotaPlan.pendiente || this == EstadoCuotaPlan.vencida;
}

/// Intento de pago de una cuota (`PagoCuotaResumen`).
///
/// `estado` es el `estado_pago` real del pago (`PENDIENTE`, `APROBADO`,
/// `RECHAZADO`, `ANULADO`, `REEMBOLSADO`) y `aplicado_a_cuota` indica si el
/// backend ya lo aplicó a la cuota.
class PagoCuotaIntento {
  const PagoCuotaIntento({
    required this.pagoId,
    required this.metodoPago,
    required this.estado,
    required this.monto,
    required this.fechaCreacion,
    required this.aplicadoACuota,
  });

  /// Identificador del pago (`pago_id`).
  final int pagoId;

  /// Método de pago informado por el backend (`metodo_pago`).
  final String metodoPago;

  /// Estado del pago (`estado`).
  final EstadoPagoApi estado;

  /// Monto del intento (`monto`).
  final double monto;

  /// Fecha de creación del intento (`fecha_creacion`).
  final DateTime? fechaCreacion;

  /// Indica si el intento ya fue aplicado a la cuota (`aplicado_a_cuota`).
  final bool aplicadoACuota;

  /// Etiqueta legible del método de pago.
  String get metodoPagoEtiqueta {
    switch (metodoPago.trim().toUpperCase()) {
      case 'TARJETA':
        return 'Tarjeta';
      case 'EFECTIVO':
        return 'Efectivo';
      case 'TRANSFERENCIA':
        return 'Transferencia';
      case 'QR':
        return 'QR';
      case 'OTRO':
        return 'Otro';
      case '':
        return 'No especificado';
      default:
        return metodoPago;
    }
  }

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory PagoCuotaIntento.fromJson(Map<String, dynamic> json) {
    return PagoCuotaIntento(
      pagoId: _aInt(json['pago_id']),
      metodoPago: json['metodo_pago'] as String? ?? '',
      estado: EstadoPagoApi.desdeApi(json['estado'] as String?),
      monto: _aDouble(json['monto']) ?? 0,
      fechaCreacion: _aFecha(json['fecha_creacion']),
      aplicadoACuota: json['aplicado_a_cuota'] == true,
    );
  }
}

/// Cuota de un plan de pago (`CuotaRespuesta`).
class CuotaPlan {
  const CuotaPlan({
    required this.id,
    required this.numeroCuota,
    required this.montoProgramado,
    required this.fechaVencimiento,
    required this.estado,
    required this.pagos,
  });

  /// Identificador de la cuota (`id`), usado en los endpoints de cobro.
  final int id;

  /// Número de cuota dentro del plan (`numero_cuota`), desde 1.
  final int numeroCuota;

  /// Importe programado (`monto_programado`).
  final double montoProgramado;

  /// Fecha de vencimiento (`fecha_vencimiento`), puede ser `null`.
  final DateTime? fechaVencimiento;

  /// Estado de la cuota (`estado`).
  final EstadoCuotaPlan estado;

  /// Pagos e intentos anteriores registrados para esta cuota (`pagos`).
  final List<PagoCuotaIntento> pagos;

  /// Indica si la cuota ya fue pagada.
  bool get estaPagada => estado.estaPagada;

  /// Indica si existe al menos un intento registrado.
  bool get tieneIntentos => pagos.isNotEmpty;

  /// Indica si el paciente puede pagar esta cuota dentro de un plan.
  ///
  /// Respeta la validación del backend: plan ACTIVO y cuota PENDIENTE o
  /// VENCIDA. Nunca se habilita el cobro de cuotas pagadas ni canceladas.
  bool esPagableEn(EstadoPlanPago plan) =>
      plan.admiteNuevosPagos && estado.esCobrable;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory CuotaPlan.fromJson(Map<String, dynamic> json) {
    return CuotaPlan(
      id: _aInt(json['id']),
      numeroCuota: _aInt(json['numero_cuota']),
      montoProgramado: _aDouble(json['monto_programado']) ?? 0,
      fechaVencimiento: _aFecha(json['fecha_vencimiento']),
      estado: EstadoCuotaPlan.desdeApi(json['estado'] as String?),
      pagos: <PagoCuotaIntento>[
        for (final item in _aMapas(json['pagos']))
          PagoCuotaIntento.fromJson(item),
      ],
    );
  }
}

/// Servicio financiado por un plan (`ServicioPlanRespuesta`).
class ServicioPlan {
  const ServicioPlan({
    required this.servicioRealizadoId,
    required this.nombreServicio,
    required this.montoFinanciado,
    required this.activo,
  });

  /// Identificador del servicio realizado (`servicio_realizado_id`).
  final int servicioRealizadoId;

  /// Nombre del servicio (`nombre_servicio`).
  final String nombreServicio;

  /// Monto financiado (`monto_financiado`).
  final double montoFinanciado;

  /// Indica si el servicio sigue activo dentro del plan (`activo`).
  final bool activo;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory ServicioPlan.fromJson(Map<String, dynamic> json) {
    return ServicioPlan(
      servicioRealizadoId: _aInt(json['servicio_realizado_id']),
      nombreServicio: json['nombre_servicio'] as String? ?? '',
      montoFinanciado: _aDouble(json['monto_financiado']) ?? 0,
      activo: json['activo'] == true,
    );
  }
}

/// Plan de pago del paciente con su cronograma completo
/// (`PlanPagoRespuesta`, `GET /pagos/mis-planes/{plan_id}`).
class PlanPago {
  const PlanPago({
    required this.id,
    required this.pacienteId,
    required this.consultaClinicaId,
    required this.montoTotal,
    required this.moneda,
    required this.cantidadCuotas,
    required this.fechaCreacion,
    required this.estado,
    required this.observaciones,
    required this.creadoPor,
    required this.saldoPendiente,
    required this.montoPagado,
    required this.servicios,
    required this.cuotas,
  });

  /// Identificador del plan (`id`).
  final int id;

  /// Paciente dueño del plan (`paciente_id`).
  final int pacienteId;

  /// Consulta clínica asociada (`consulta_clinica_id`).
  final int consultaClinicaId;

  /// Monto total financiado (`monto_total`).
  final double montoTotal;

  /// Moneda del plan (`moneda`), p. ej. `BOB`.
  final String moneda;

  /// Cantidad de cuotas programadas (`cantidad_cuotas`).
  final int cantidadCuotas;

  /// Fecha de creación del plan (`fecha_creacion`).
  final DateTime? fechaCreacion;

  /// Estado del plan (`estado`).
  final EstadoPlanPago estado;

  /// Observaciones registradas por la clínica (`observaciones`).
  final String? observaciones;

  /// Usuario administrativo que creó el plan (`creado_por`).
  final int creadoPor;

  /// Saldo pendiente calculado por el backend (`saldo_pendiente`).
  final double saldoPendiente;

  /// Monto efectivamente pagado según el backend (`monto_pagado`).
  final double montoPagado;

  /// Servicios financiados (`servicios`).
  final List<ServicioPlan> servicios;

  /// Cuotas del plan ordenadas por `numero_cuota` (`cuotas`).
  final List<CuotaPlan> cuotas;

  /// Cantidad de cuotas pagadas.
  int get cuotasPagadas => cuotas.where((cuota) => cuota.estaPagada).length;

  /// Cantidad de cuotas aún no pagadas.
  int get cuotasRestantes {
    final int restantes = cantidadCuotas - cuotasPagadas;
    return restantes < 0 ? 0 : restantes;
  }

  /// Avance del plan entre 0 y 1 (cuotas pagadas / total de cuotas).
  double get progreso {
    if (cantidadCuotas <= 0) return 0;
    return (cuotasPagadas / cantidadCuotas).clamp(0.0, 1.0);
  }

  /// Avance del plan en porcentaje entero (0 a 100).
  int get porcentaje => (progreso * 100).round();

  /// Indica si alguna cuota está vencida y sin pagar.
  bool get tieneCuotasVencidas =>
      cuotas.any((cuota) => cuota.estado == EstadoCuotaPlan.vencida);

  /// Indica si el plan admite nuevos pagos (estado ACTIVO).
  bool get admiteNuevosPagos => estado.admiteNuevosPagos;

  /// Cuota pagable más próxima (menor `numero_cuota` cobrable).
  CuotaPlan? get proximaCuota {
    final List<CuotaPlan> ordenadas = [...cuotas]
      ..sort((a, b) => a.numeroCuota.compareTo(b.numeroCuota));

    for (final cuota in ordenadas) {
      if (cuota.estado.esCobrable) return cuota;
    }
    return null;
  }

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory PlanPago.fromJson(Map<String, dynamic> json) {
    final List<CuotaPlan> cuotas = <CuotaPlan>[
      for (final item in _aMapas(json['cuotas'])) CuotaPlan.fromJson(item),
    ]..sort((a, b) => a.numeroCuota.compareTo(b.numeroCuota));

    return PlanPago(
      id: _aInt(json['id']),
      pacienteId: _aInt(json['paciente_id']),
      consultaClinicaId: _aInt(json['consulta_clinica_id']),
      montoTotal: _aDouble(json['monto_total']) ?? 0,
      moneda: json['moneda'] as String? ?? 'BOB',
      cantidadCuotas: _aInt(json['cantidad_cuotas']),
      fechaCreacion: _aFecha(json['fecha_creacion']),
      estado: EstadoPlanPago.desdeApi(json['estado'] as String?),
      observaciones: json['observaciones'] as String?,
      creadoPor: _aInt(json['creado_por']),
      saldoPendiente: _aDouble(json['saldo_pendiente']) ?? 0,
      montoPagado: _aDouble(json['monto_pagado']) ?? 0,
      servicios: <ServicioPlan>[
        for (final item in _aMapas(json['servicios']))
          ServicioPlan.fromJson(item),
      ],
      cuotas: cuotas,
    );
  }
}

/// Resumen de un plan del paciente (`PlanPagoListadoItem`).
class PlanPagoResumen {
  const PlanPagoResumen({
    required this.id,
    required this.pacienteId,
    required this.consultaClinicaId,
    required this.montoTotal,
    required this.montoPagado,
    required this.saldoPendiente,
    required this.moneda,
    required this.cantidadCuotas,
    required this.cuotasPagadas,
    required this.fechaCreacion,
    required this.estado,
    required this.tieneCuotasVencidas,
  });

  /// Identificador del plan (`id`).
  final int id;

  /// Paciente dueño del plan (`paciente_id`).
  final int pacienteId;

  /// Consulta clínica asociada (`consulta_clinica_id`).
  final int consultaClinicaId;

  /// Monto total financiado (`monto_total`).
  final double montoTotal;

  /// Monto pagado calculado por el backend (`monto_pagado`).
  final double montoPagado;

  /// Saldo pendiente calculado por el backend (`saldo_pendiente`).
  final double saldoPendiente;

  /// Moneda del plan (`moneda`).
  final String moneda;

  /// Cantidad de cuotas programadas (`cantidad_cuotas`).
  final int cantidadCuotas;

  /// Cantidad de cuotas pagadas (`cuotas_pagadas`).
  final int cuotasPagadas;

  /// Fecha de creación del plan (`fecha_creacion`).
  final DateTime? fechaCreacion;

  /// Estado del plan (`estado`).
  final EstadoPlanPago estado;

  /// Indica si el backend detectó cuotas vencidas (`tiene_cuotas_vencidas`).
  final bool tieneCuotasVencidas;

  /// Cantidad de cuotas aún no pagadas.
  int get cuotasRestantes {
    final int restantes = cantidadCuotas - cuotasPagadas;
    return restantes < 0 ? 0 : restantes;
  }

  /// Avance del plan entre 0 y 1 (cuotas pagadas / total de cuotas).
  double get progreso {
    if (cantidadCuotas <= 0) return 0;
    return (cuotasPagadas / cantidadCuotas).clamp(0.0, 1.0);
  }

  /// Avance del plan en porcentaje entero (0 a 100).
  int get porcentaje => (progreso * 100).round();

  /// Indica si queda saldo pendiente.
  bool get tieneSaldo => saldoPendiente > 0;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory PlanPagoResumen.fromJson(Map<String, dynamic> json) {
    return PlanPagoResumen(
      id: _aInt(json['id']),
      pacienteId: _aInt(json['paciente_id']),
      consultaClinicaId: _aInt(json['consulta_clinica_id']),
      montoTotal: _aDouble(json['monto_total']) ?? 0,
      montoPagado: _aDouble(json['monto_pagado']) ?? 0,
      saldoPendiente: _aDouble(json['saldo_pendiente']) ?? 0,
      moneda: json['moneda'] as String? ?? 'BOB',
      cantidadCuotas: _aInt(json['cantidad_cuotas']),
      cuotasPagadas: _aInt(json['cuotas_pagadas']),
      fechaCreacion: _aFecha(json['fecha_creacion']),
      estado: EstadoPlanPago.desdeApi(json['estado'] as String?),
      tieneCuotasVencidas: json['tiene_cuotas_vencidas'] == true,
    );
  }
}

/// Página de planes del paciente (`PlanesPagoPagina`).
class PaginaPlanes {
  const PaginaPlanes({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  /// Planes de la página actual.
  final List<PlanPagoResumen> items;

  /// Total de planes del paciente en el backend.
  final int total;

  /// Página devuelta.
  final int page;

  /// Tamaño de página usado por el backend.
  final int pageSize;

  /// Total de páginas disponibles.
  final int totalPages;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory PaginaPlanes.fromJson(Map<String, dynamic> json) {
    return PaginaPlanes(
      items: <PlanPagoResumen>[
        for (final item in _aMapas(json['items']))
          PlanPagoResumen.fromJson(item),
      ],
      total: _aInt(json['total']),
      page: _aInt(json['page']),
      pageSize: _aInt(json['page_size']),
      totalPages: _aInt(json['total_pages']),
    );
  }
}

/// Intención de pago de una cuota creada por el backend
/// (`IntencionCuotaStripeRespuesta`).
///
/// El `client_secret` es lo único que necesita el PaymentSheet; el monto y la
/// moneda los decide FastAPI (el paciente nunca escribe importes).
class IntencionCuotaStripe {
  const IntencionCuotaStripe({
    required this.pagoId,
    required this.cuotaId,
    required this.planPagoId,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.monto,
    required this.moneda,
    required this.estadoPago,
  });

  /// Pago creado (o reutilizado) por el backend (`pago_id`).
  final int pagoId;

  /// Cuota a pagar (`cuota_id`).
  final int cuotaId;

  /// Plan al que pertenece la cuota (`plan_pago_id`).
  final int planPagoId;

  /// Identificador del PaymentIntent (`payment_intent_id`).
  final String paymentIntentId;

  /// Secreto de cliente para el PaymentSheet (`client_secret`).
  final String clientSecret;

  /// Importe exacto a cobrar (`monto`).
  final double monto;

  /// Moneda del cobro (`moneda`).
  final String moneda;

  /// Estado del pago al crear la intención (`estado_pago`).
  final String estadoPago;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory IntencionCuotaStripe.fromJson(Map<String, dynamic> json) {
    return IntencionCuotaStripe(
      pagoId: _aInt(json['pago_id']),
      cuotaId: _aInt(json['cuota_id']),
      planPagoId: _aInt(json['plan_pago_id']),
      paymentIntentId: json['payment_intent_id'] as String? ?? '',
      clientSecret: json['client_secret'] as String? ?? '',
      monto: _aDouble(json['monto']) ?? 0,
      moneda: json['moneda'] as String? ?? 'BOB',
      estadoPago: json['estado_pago'] as String? ?? '',
    );
  }
}

/// Intentos de pago de una cuota (`IntentosCuotaRespuesta`).
class IntentosCuota {
  const IntentosCuota({
    required this.cuotaId,
    required this.estadoCuota,
    required this.intentos,
  });

  /// Cuota consultada (`cuota_id`).
  final int cuotaId;

  /// Estado actual de la cuota (`estado_cuota`).
  final EstadoCuotaPlan estadoCuota;

  /// Intentos registrados en el backend.
  final List<PagoCuotaIntento> intentos;

  /// Indica si la cuota ya está pagada según el backend.
  bool get estaPagada => estadoCuota.estaPagada;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory IntentosCuota.fromJson(Map<String, dynamic> json) {
    return IntentosCuota(
      cuotaId: _aInt(json['cuota_id']),
      estadoCuota: EstadoCuotaPlan.desdeApi(json['estado_cuota'] as String?),
      intentos: <PagoCuotaIntento>[
        for (final item in _aMapas(json['intentos']))
          PagoCuotaIntento.fromJson(item),
      ],
    );
  }
}






