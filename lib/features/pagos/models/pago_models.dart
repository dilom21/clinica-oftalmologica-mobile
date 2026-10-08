// Modelos del módulo Pagos (ETAPA 7 + ETAPA 8.2).
//
// Corresponden EXACTAMENTE a los schemas reales de FastAPI del módulo
// `gestion_pagos` (verificados en el backend, no inventados):
//
// - GET  /pagos/mis-consultas                          -> list[ConsultaPagoResumen]
// - GET  /pagos/mis-consultas/{consulta_id}/servicios  -> list[ServicioPagoRespuesta]
// - POST /pagos/stripe/intencion                       -> IntencionPagoStripeRespuesta
// - GET  /pagos/stripe/pagos/{pago_id}/estado          -> EstadoPagoStripeRespuesta
// - GET  /pagos/mis-pagos                              -> list[PagoHistorialItem]
// - GET  /pagos/mis-pagos/{pago_id}/comprobante        -> application/pdf (bytes)
//
// Los nombres usan snake_case tal como los serializa el backend. Los montos
// llegan como `Decimal` (FastAPI puede serializarlo como número o como texto)
// por lo que se normalizan a `double` de forma tolerante.

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

/// Formatea un monto con dos decimales (sin símbolo de moneda).
String formatearMonto(double monto) => monto.toStringAsFixed(2);

/// Formatea una fecha como `dd/MM/yyyy`; texto claro si es `null`.
String formatearFecha(DateTime? fecha) {
  if (fecha == null) return 'Fecha no disponible';
  final dia = fecha.day.toString().padLeft(2, '0');
  final mes = fecha.month.toString().padLeft(2, '0');
  return '$dia/$mes/${fecha.year}';
}

/// Desplazamiento de Bolivia (América/La_Paz = UTC-4, sin horario de verano).
const Duration offsetBolivia = Duration(hours: -4);

/// Convierte una fecha del backend a hora de Bolivia (UTC-4).
///
/// El backend (FastAPI) serializa las fechas en UTC: con zona (`+00:00`) o sin
/// zona. Una fecha con zona se interpreta como UTC; una fecha sin zona se toma
/// como UTC de forma explícita. La conversión es determinista y NO depende de
/// la zona horaria del teléfono.
DateTime fechaEnHoraBolivia(DateTime fecha) {
  final DateTime utc = fecha.isUtc
      ? fecha
      : DateTime.utc(
          fecha.year,
          fecha.month,
          fecha.day,
          fecha.hour,
          fecha.minute,
          fecha.second,
          fecha.millisecond,
          fecha.microsecond,
        );
  return utc.add(offsetBolivia);
}

/// Formatea una fecha/hora como `dd/MM/yyyy HH:mm` en hora de Bolivia.
String formatearFechaHoraBolivia(DateTime? fecha) {
  if (fecha == null) return 'Fecha no disponible';
  final DateTime bolivia = fechaEnHoraBolivia(fecha);
  final dia = bolivia.day.toString().padLeft(2, '0');
  final mes = bolivia.month.toString().padLeft(2, '0');
  final hora = bolivia.hour.toString().padLeft(2, '0');
  final minuto = bolivia.minute.toString().padLeft(2, '0');
  return '$dia/$mes/${bolivia.year} $hora:$minuto';
}

/// Símbolo de la moneda tal como la entrega el backend (`BOB`, `USD`, ...).
String simboloMoneda(String? moneda) {
  switch ((moneda ?? '').trim().toUpperCase()) {
    case 'BOB':
      return 'Bs';
    case 'USD':
      return 'US\$';
    case 'EUR':
      return '€';
    case '':
      return 'Bs';
    default:
      return (moneda ?? '').trim();
  }
}

/// Formatea un importe con su moneda, p. ej. `Bs 210.00`.
String formatearMontoConMoneda(String? moneda, double monto) =>
    '${simboloMoneda(moneda)} ${formatearMonto(monto)}';

/// Resumen de una consulta clínica del paciente para el flujo de pagos.
///
/// Schema backend: `ConsultaPagoResumen`.
class ConsultaPago {
  const ConsultaPago({
    required this.consultaId,
    required this.fechaConsulta,
    required this.oftalmologo,
    required this.cantidadServicios,
    required this.cantidadPendientes,
    required this.totalPendiente,
  });

  /// Identificador de la consulta clínica (`consulta_id`).
  final int consultaId;

  /// Fecha/hora de la consulta (`fecha_consulta`).
  final DateTime? fechaConsulta;

  /// Nombre completo del oftalmólogo, si el backend lo entrega.
  final String? oftalmologo;

  /// Cantidad total de servicios realizados (`cantidad_servicios`).
  final int cantidadServicios;

  /// Cantidad de servicios aún pendientes (`cantidad_pendientes`).
  final int cantidadPendientes;

  /// Monto total pendiente de pago (`total_pendiente`).
  final double totalPendiente;

  /// Indica si la consulta tiene servicios registrados.
  bool get tieneServicios => cantidadServicios > 0;

  /// Indica si quedan servicios por pagar.
  bool get tienePendientes => cantidadPendientes > 0;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory ConsultaPago.fromJson(Map<String, dynamic> json) {
    final oftalmo = json['oftalmologo'];
    String? nombreOftalmologo;

    if (oftalmo is Map<String, dynamic>) {
      final nombres = oftalmo['nombres'] as String? ?? '';
      final apellidos = oftalmo['apellidos'] as String? ?? '';
      final completo = '$nombres $apellidos'.trim();
      nombreOftalmologo = completo.isEmpty ? null : completo;
    }

    return ConsultaPago(
      consultaId: _aInt(json['consulta_id']),
      fechaConsulta: _aFecha(json['fecha_consulta']),
      oftalmologo: nombreOftalmologo,
      cantidadServicios: _aInt(json['cantidad_servicios']),
      cantidadPendientes: _aInt(json['cantidad_pendientes']),
      totalPendiente: _aDouble(json['total_pendiente']) ?? 0,
    );
  }
}

/// Estado de pago de un servicio realizado.
enum EstadoServicioPago {
  pendiente,
  pagado;

  /// Interpreta el valor `estado_pago` del backend (`PENDIENTE`/`PAGADO`).
  static EstadoServicioPago desdeApi(String? valor) =>
      valor?.toUpperCase() == 'PAGADO'
      ? EstadoServicioPago.pagado
      : EstadoServicioPago.pendiente;

  /// Etiqueta legible para mostrar al paciente.
  String get etiqueta =>
      this == EstadoServicioPago.pagado ? 'Pagado' : 'Pendiente';
}

/// Servicio realizado de una consulta con su estado de pago.
///
/// Schema backend: `ServicioPagoRespuesta`.
class ServicioRealizadoPago {
  const ServicioRealizadoPago({
    required this.servicioRealizadoId,
    required this.servicioId,
    required this.nombreServicio,
    required this.fechaRealizacion,
    required this.precioAplicado,
    required this.estadoPago,
  });

  /// Identificador del servicio realizado (`servicio_realizado_id`).
  final int servicioRealizadoId;

  /// Identificador del catálogo de servicios (`servicio_id`).
  final int servicioId;

  /// Nombre del servicio (`nombre_servicio`).
  final String nombreServicio;

  /// Fecha de realización (`fecha_realizacion`), puede ser `null`.
  final DateTime? fechaRealizacion;

  /// Precio aplicado (`precio_aplicado`), puede ser `null`.
  final double? precioAplicado;

  /// Estado de pago (`estado_pago`).
  final EstadoServicioPago estadoPago;

  /// Indica si el servicio ya fue pagado.
  bool get estaPagado => estadoPago == EstadoServicioPago.pagado;

  /// Indica si el servicio sigue pendiente de pago.
  bool get estaPendiente => !estaPagado;

  /// Precio del servicio (0 si no tiene precio aplicado).
  double get precio => precioAplicado ?? 0;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory ServicioRealizadoPago.fromJson(Map<String, dynamic> json) {
    return ServicioRealizadoPago(
      servicioRealizadoId: _aInt(json['servicio_realizado_id']),
      servicioId: _aInt(json['servicio_id']),
      nombreServicio: json['nombre_servicio'] as String? ?? '',
      fechaRealizacion: _aFecha(json['fecha_realizacion']),
      precioAplicado: _aDouble(json['precio_aplicado']),
      estadoPago: EstadoServicioPago.desdeApi(json['estado_pago'] as String?),
    );
  }
}

/// Indica si un servicio puede seleccionarse para pago.
///
/// Solo los servicios PENDIENTES y con precio mayor a cero son cobrables; los
/// PAGADOS nunca deben poder volver a seleccionarse.
bool esServicioSeleccionable(ServicioRealizadoPago servicio) =>
    servicio.estaPendiente && servicio.precio > 0;

/// Devuelve los ids de todos los servicios seleccionables.
Set<int> idsSeleccionables(List<ServicioRealizadoPago> servicios) => {
  for (final servicio in servicios)
    if (esServicioSeleccionable(servicio)) servicio.servicioRealizadoId,
};

/// Calcula el total de los servicios seleccionados.
///
/// Ignora cualquier id que no sea seleccionable (p. ej. servicios pagados),
/// para que el total visual nunca incluya algo no cobrable.
double totalSeleccionado(
  List<ServicioRealizadoPago> servicios,
  Set<int> seleccionados,
) {
  var total = 0.0;
  for (final servicio in servicios) {
    if (seleccionados.contains(servicio.servicioRealizadoId) &&
        esServicioSeleccionable(servicio)) {
      total += servicio.precio;
    }
  }
  return total;
}

/// Respuesta de `POST /pagos/stripe/intencion`.
///
/// Schema backend: `IntencionPagoStripeRespuesta`.
class PagoIntencion {
  const PagoIntencion({
    required this.pagoId,
    required this.consultaClinicaId,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.monto,
    required this.moneda,
    required this.estadoPago,
  });

  /// Identificador del pago (`pago_id`).
  final int pagoId;

  /// Consulta clínica a la que pertenece el pago (`consulta_clinica_id`).
  final int consultaClinicaId;

  /// Identificador del PaymentIntent en Stripe (`payment_intent_id`).
  final String paymentIntentId;

  /// Secreto de cliente (`client_secret`) para inicializar el PaymentSheet.
  final String clientSecret;

  /// Monto total (`monto`).
  final double monto;

  /// Moneda (`moneda`).
  final String moneda;

  /// Estado devuelto por el backend (`estado_pago`).
  final String estadoPago;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory PagoIntencion.fromJson(Map<String, dynamic> json) {
    return PagoIntencion(
      pagoId: _aInt(json['pago_id']),
      consultaClinicaId: _aInt(json['consulta_clinica_id']),
      paymentIntentId: json['payment_intent_id'] as String? ?? '',
      clientSecret: json['client_secret'] as String? ?? '',
      monto: _aDouble(json['monto']) ?? 0,
      moneda: json['moneda'] as String? ?? 'BOB',
      estadoPago: json['estado_pago'] as String? ?? '',
    );
  }
}

/// Estados de pago posibles del backend.
///
/// Coincide con el CHECK de la tabla `pago`:
/// `PENDIENTE`, `APROBADO`, `RECHAZADO`, `ANULADO`, `REEMBOLSADO`.
enum EstadoPagoApi {
  pendiente,
  aprobado,
  rechazado,
  anulado,
  reembolsado,
  desconocido;

  /// Interpreta el `estado_pago` del backend.
  static EstadoPagoApi desdeApi(String? valor) {
    switch (valor?.toUpperCase()) {
      case 'PENDIENTE':
        return EstadoPagoApi.pendiente;
      case 'APROBADO':
        return EstadoPagoApi.aprobado;
      case 'RECHAZADO':
        return EstadoPagoApi.rechazado;
      case 'ANULADO':
        return EstadoPagoApi.anulado;
      case 'REEMBOLSADO':
        return EstadoPagoApi.reembolsado;
      default:
        return EstadoPagoApi.desconocido;
    }
  }

  /// Indica si el pago está aprobado (única fuente: el backend).
  bool get esAprobado => this == EstadoPagoApi.aprobado;

  /// Indica si el pago sigue pendiente (webhook aún no procesado).
  bool get esPendiente => this == EstadoPagoApi.pendiente;

  /// Etiqueta legible para mostrar al paciente.
  String get etiqueta {
    switch (this) {
      case EstadoPagoApi.pendiente:
        return 'Pendiente';
      case EstadoPagoApi.aprobado:
        return 'Aprobado';
      case EstadoPagoApi.rechazado:
        return 'Rechazado';
      case EstadoPagoApi.anulado:
        return 'Anulado';
      case EstadoPagoApi.reembolsado:
        return 'Reembolsado';
      case EstadoPagoApi.desconocido:
        return 'Estado desconocido';
    }
  }
}

/// Respuesta de `GET /pagos/stripe/pagos/{pago_id}/estado`.
///
/// Schema backend: `EstadoPagoStripeRespuesta`.
class EstadoPago {
  const EstadoPago({
    required this.pagoId,
    required this.consultaClinicaId,
    required this.estado,
    required this.monto,
    required this.moneda,
    required this.paymentIntentId,
  });

  /// Identificador del pago (`pago_id`).
  final int pagoId;

  /// Consulta clínica asociada (`consulta_clinica_id`).
  final int consultaClinicaId;

  /// Estado del pago (`estado_pago`).
  final EstadoPagoApi estado;

  /// Monto (`monto`).
  final double monto;

  /// Moneda (`moneda`).
  final String moneda;

  /// Referencia del PaymentIntent (`payment_intent_id`), puede ser `null`.
  final String? paymentIntentId;

  /// Indica si el backend confirma el pago como APROBADO.
  bool get aprobado => estado.esAprobado;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory EstadoPago.fromJson(Map<String, dynamic> json) {
    return EstadoPago(
      pagoId: _aInt(json['pago_id']),
      consultaClinicaId: _aInt(json['consulta_clinica_id']),
      estado: EstadoPagoApi.desdeApi(json['estado_pago'] as String?),
      monto: _aDouble(json['monto']) ?? 0,
      moneda: json['moneda'] as String? ?? 'BOB',
      paymentIntentId: json['payment_intent_id'] as String?,
    );
  }
}

/// Servicio aplicado a un pago del historial.
///
/// Schema backend: `ServicioPagoHistorial` (dentro de `PagoHistorialItem`).
/// El importe es el precio histórico de `pago_detalle.monto_aplicado`, NO el
/// precio actual del catálogo.
class ServicioPagoHistorial {
  const ServicioPagoHistorial({
    required this.servicioRealizadoId,
    required this.nombreServicio,
    required this.montoAplicado,
  });

  /// Identificador del servicio realizado (`servicio_realizado_id`).
  final int servicioRealizadoId;

  /// Nombre del servicio (`nombre_servicio`).
  final String nombreServicio;

  /// Importe aplicado en el pago (`monto_aplicado`).
  final double montoAplicado;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory ServicioPagoHistorial.fromJson(Map<String, dynamic> json) {
    return ServicioPagoHistorial(
      servicioRealizadoId: _aInt(json['servicio_realizado_id']),
      nombreServicio: json['nombre_servicio'] as String? ?? '',
      montoAplicado: _aDouble(json['monto_aplicado']) ?? 0,
    );
  }
}

/// Pago del historial del paciente autenticado.
///
/// Schema backend: `PagoHistorialItem` (`GET /pagos/mis-pagos`).
///
/// Campos opcionales según el backend: `consulta_clinica_id` (null cuando los
/// servicios del pago provienen de consultas distintas), `fecha_hora_pago`
/// (null mientras el pago no se ha confirmado) y `pasarela`.
class PagoHistorial {
  const PagoHistorial({
    required this.pagoId,
    required this.consultaClinicaId,
    required this.fechaCreacion,
    required this.fechaHoraPago,
    required this.monto,
    required this.moneda,
    required this.metodoPago,
    required this.estadoPago,
    required this.pasarela,
    required this.servicios,
  });

  /// Identificador del pago (`pago_id`).
  final int pagoId;

  /// Consulta clínica asociada (`consulta_clinica_id`), puede ser `null`.
  final int? consultaClinicaId;

  /// Fecha de creación del pago (`fecha_creacion`).
  final DateTime? fechaCreacion;

  /// Fecha/hora del pago (`fecha_hora_pago`), puede ser `null`.
  final DateTime? fechaHoraPago;

  /// Monto total (`monto`).
  final double monto;

  /// Moneda (`moneda`), p. ej. `BOB`.
  final String moneda;

  /// Método de pago (`metodo_pago`), p. ej. `TARJETA`.
  final String metodoPago;

  /// Estado del pago según el backend (`estado_pago`).
  final EstadoPagoApi estadoPago;

  /// Pasarela utilizada (`pasarela`), puede ser `null`.
  final String? pasarela;

  /// Servicios realmente pagados con su importe aplicado.
  final List<ServicioPagoHistorial> servicios;

  /// Solo un pago APROBADO por el backend habilita el comprobante.
  bool get aprobado => estadoPago.esAprobado;

  /// Indica si el pago tiene una consulta clínica asociada.
  bool get tieneConsulta => consultaClinicaId != null;

  /// Fecha a mostrar: la del pago confirmado o, si aún no existe, la creación.
  DateTime? get fechaMostrar => fechaHoraPago ?? fechaCreacion;

  /// Etiqueta legible del método de pago (sin inventar datos: si el backend
  /// envía un valor desconocido se muestra tal cual).
  String get metodoPagoEtiqueta {
    switch (metodoPago.trim().toUpperCase()) {
      case 'TARJETA':
        return 'Tarjeta';
      case 'EFECTIVO':
        return 'Efectivo';
      case 'TRANSFERENCIA':
        return 'Transferencia';
      case '':
        return 'No especificado';
      default:
        return metodoPago;
    }
  }

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory PagoHistorial.fromJson(Map<String, dynamic> json) {
    final Object? servicios = json['servicios'];
    final Object? consulta = json['consulta_clinica_id'];

    return PagoHistorial(
      pagoId: _aInt(json['pago_id']),
      consultaClinicaId: consulta == null ? null : _aInt(consulta),
      fechaCreacion: _aFecha(json['fecha_creacion']),
      fechaHoraPago: _aFecha(json['fecha_hora_pago']),
      monto: _aDouble(json['monto']) ?? 0,
      moneda: json['moneda'] as String? ?? 'BOB',
      metodoPago: json['metodo_pago'] as String? ?? '',
      estadoPago: EstadoPagoApi.desdeApi(json['estado_pago'] as String?),
      pasarela: json['pasarela'] as String?,
      servicios: <ServicioPagoHistorial>[
        if (servicios is List)
          for (final item in servicios)
            if (item is Map<String, dynamic>)
              ServicioPagoHistorial.fromJson(item),
      ],
    );
  }
}

/// Ordena el historial del pago más reciente al más antiguo.
///
/// El backend ya lo entrega ordenado (`fecha_creacion` desc, `id` desc); este
/// comparador refuerza ese orden de forma determinista en la interfaz y usa
/// `pago_id` como desempate.
List<PagoHistorial> ordenarHistorialPorFechaDesc(List<PagoHistorial> pagos) {
  final List<PagoHistorial> copia = [...pagos];
  copia.sort((a, b) {
    final fa = a.fechaCreacion;
    final fb = b.fechaCreacion;

    if (fa == null && fb == null) return b.pagoId.compareTo(a.pagoId);
    if (fa == null) return 1;
    if (fb == null) return -1;

    final comparacion = fb.compareTo(fa);
    return comparacion != 0 ? comparacion : b.pagoId.compareTo(a.pagoId);
  });
  return copia;
}
