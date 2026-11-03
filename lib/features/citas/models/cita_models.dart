// Modelos de CU10 (agendamiento y gestión de citas del paciente).
//
// Corresponden EXACTAMENTE a los schemas reales de FastAPI verificados en el
// `openapi.json` desplegado:
//
// - `POST   /agenda-citas/citas`                 -> `CitaCreate` / `CitaResponse` (201)
// - `GET    /agenda-citas/citas`                 -> `CitaResponse[]`
// - `GET    /agenda-citas/citas/{cita_id}`        -> `CitaResponse`
// - `PUT    /agenda-citas/citas/{cita_id}`        -> `CitaUpdate` / `CitaResponse`
// - `PATCH  /agenda-citas/citas/{cita_id}/estado` -> `CitaEstadoUpdate` / `CitaResponse`
//
// `CitaResponse` NO incluye el nombre del oftalmólogo: para mostrarlo se
// cruza `oftalmologo_id` con `GET /agenda-citas/oftalmologos` (dato real).

import 'agenda_models.dart';

/// Duración fija de una cita, en minutos.
///
/// Espeja `DURACION_CITA_MINUTOS` de FastAPI. La app NO envía la hora de fin
/// ni una duración: el backend la calcula. Este valor solo se usa para
/// proyectar los intervalos libres en turnos seleccionables de 30 minutos.
const int duracionCitaMinutos = 30;

/// Estados reales de una cita según FastAPI.
const String citaProgramada = 'PROGRAMADA';
const String citaConfirmada = 'CONFIRMADA';
const String citaEnEspera = 'EN_ESPERA';
const String citaAtendida = 'ATENDIDA';
const String citaCancelada = 'CANCELADA';
const String citaNoAsistio = 'NO_ASISTIO';

/// Cita médica del paciente autenticado.
///
/// Schema backend: `CitaResponse`.
class Cita {
  const Cita({
    required this.id,
    required this.pacienteId,
    required this.oftalmologoId,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
    this.motivo,
    this.observaciones,
    this.fechaRegistro,
    this.fechaActualizacion,
  });

  /// Identificador de la cita.
  final int id;

  /// Paciente dueño de la cita (el backend lo deduce del JWT).
  final int pacienteId;

  /// Oftalmólogo que atenderá la cita.
  final int oftalmologoId;

  /// Fecha de la cita (sin hora).
  final DateTime fecha;

  /// Hora de inicio (`HH:MM:SS` tal como la serializa FastAPI).
  final String horaInicio;

  /// Hora de fin calculada por el backend (`HH:MM:SS`).
  final String horaFin;

  /// Estado real de la cita.
  final String estado;

  /// Motivo de consulta (opcional).
  final String? motivo;

  /// Observaciones (opcional).
  final String? observaciones;

  /// Marca temporal de registro (opcional).
  final String? fechaRegistro;

  /// Marca temporal de la última actualización (opcional).
  final String? fechaActualizacion;

  /// Fecha y hora de inicio combinadas.
  DateTime get inicio => DateTime(
    fecha.year,
    fecha.month,
    fecha.day,
    minutosDe(horaInicio) ~/ 60,
    minutosDe(horaInicio) % 60,
  );

  /// Fecha y hora de fin combinadas.
  DateTime get fin => DateTime(
    fecha.year,
    fecha.month,
    fecha.day,
    minutosDe(horaFin) ~/ 60,
    minutosDe(horaFin) % 60,
  );

  /// Hora de inicio en formato `HH:mm`.
  String get horaInicioCorta => horaCorta(horaInicio);

  /// Hora de fin en formato `HH:mm`.
  String get horaFinCorta => horaCorta(horaFin);

  /// Franja horaria lista para mostrar: `08:00 – 08:30`.
  String get franja => '$horaInicioCorta – $horaFinCorta';

  /// Indica si la cita aún no ha ocurrido (incluye las de hoy más tarde).
  bool get esFutura => inicio.isAfter(DateTime.now());

  /// Indica si la cita pertenece al grupo de citas vigentes.
  ///
  /// El backend es la autoridad final sobre qué transiciones permite: la
  /// interfaz solo oculta acciones sobre citas cerradas y siempre maneja
  /// 403/409/422 del servidor.
  bool get estaVigente =>
      estado == citaProgramada || estado == citaConfirmada || estado == citaEnEspera;

  /// Indica si la cita ya fue cancelada.
  bool get estaCancelada => estado == citaCancelada;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory Cita.fromJson(Map<String, dynamic> json) {
    return Cita(
      id: _entero(json['id']) ?? 0,
      pacienteId: _entero(json['paciente_id']) ?? 0,
      oftalmologoId: _entero(json['oftalmologo_id']) ?? 0,
      fecha: _fecha(json['fecha']),
      horaInicio: _hora(json['hora_inicio']),
      horaFin: _hora(json['hora_fin']),
      estado: (json['estado'] as String? ?? '').trim().toUpperCase(),
      motivo: _textoOpcional(json['motivo']),
      observaciones: _textoOpcional(json['observaciones']),
      fechaRegistro: _textoOpcional(json['fecha_registro']),
      fechaActualizacion: _textoOpcional(json['fecha_actualizacion']),
    );
  }
}

/// Cuerpo de `POST /agenda-citas/citas`.
///
/// Schema backend: `CitaCreate` (requeridos: `paciente_id`, `oftalmologo_id`,
/// `fecha`, `hora_inicio`). `motivo` y `observaciones` son OPCIONALES en el
/// contrato y se envían solo cuando el paciente escribió algo.
///
/// `paciente_id` siempre proviene de `GET /pacientes/me`: nunca se escribe a
/// mano ni se deduce del usuario autenticado (son identificadores distintos).
class CitaCreate {
  const CitaCreate({
    required this.pacienteId,
    required this.oftalmologoId,
    required this.fecha,
    required this.horaInicio,
    this.motivo,
    this.observaciones,
  });

  final int pacienteId;
  final int oftalmologoId;
  final DateTime fecha;

  /// Hora de inicio en formato `HH:MM:SS`.
  final String horaInicio;

  final String? motivo;
  final String? observaciones;

  /// JSON con los nombres exactos del contrato de FastAPI.
  Map<String, dynamic> toJson() {
    final String? motivoLimpio = motivo?.trim();
    final String? observacionesLimpias = observaciones?.trim();

    return <String, dynamic>{
      'paciente_id': pacienteId,
      'oftalmologo_id': oftalmologoId,
      'fecha': fechaIso(fecha),
      'hora_inicio': horaInicio,
      if (motivoLimpio != null && motivoLimpio.isNotEmpty) 'motivo': motivoLimpio,
      'observaciones': observacionesLimpias == null || observacionesLimpias.isEmpty
          ? null
          : observacionesLimpias,
    };
  }
}

/// Cuerpo de `PUT /agenda-citas/citas/{cita_id}` (reprogramación).
///
/// Schema backend: `CitaUpdate`. Todos los campos son opcionales; solo se
/// envían los que cambian. La hora de fin NUNCA se envía: la calcula el
/// backend.
class CitaUpdate {
  const CitaUpdate({
    this.fecha,
    this.horaInicio,
    this.motivo,
    this.observaciones,
  });

  final DateTime? fecha;
  final String? horaInicio;
  final String? motivo;
  final String? observaciones;

  /// Indica si no hay ningún cambio que enviar.
  bool get vacio =>
      fecha == null &&
      horaInicio == null &&
      motivo == null &&
      observaciones == null;

  /// JSON con los nombres exactos del contrato de FastAPI.
  Map<String, dynamic> toJson() {
    final String? motivoLimpio = motivo?.trim();
    final String? observacionesLimpias = observaciones?.trim();

    return <String, dynamic>{
      if (fecha != null) 'fecha': fechaIso(fecha!),
      if (horaInicio != null) 'hora_inicio': horaInicio,
      if (motivo != null)
        'motivo': motivoLimpio == null || motivoLimpio.isEmpty
            ? null
            : motivoLimpio,
      if (observaciones != null)
        'observaciones': observacionesLimpias == null ||
                observacionesLimpias.isEmpty
            ? null
            : observacionesLimpias,
    };
  }
}

/// Turno seleccionable de 30 minutos derivado de un intervalo libre real.
class RanuraDisponible {
  const RanuraDisponible({required this.horaInicio, required this.horaFin});

  /// Hora de inicio en formato `HH:MM:SS` (formato del contrato).
  final String horaInicio;

  /// Hora de fin en formato `HH:MM:SS`.
  final String horaFin;

  /// Hora de inicio en formato `HH:mm`.
  String get inicioCorto => horaCorta(horaInicio);

  /// Hora de fin en formato `HH:mm`.
  String get finCorto => horaCorta(horaFin);

  /// Franja lista para mostrar: `08:00 – 08:30`.
  String get etiqueta => '$inicioCorto – $finCorto';
}

/// Proyecta los intervalos libres del backend en turnos de 30 minutos.
///
/// Reglas:
/// - Solo se generan turnos COMPLETOS de [duracionCitaMinutos] dentro de cada
///   intervalo devuelto por FastAPI (no se inventan horarios).
/// - Un intervalo menor a 30 minutos no produce turnos.
/// - Los turnos repetidos entre intervalos se descartan.
///
/// Así el paciente nunca elige una hora que el servidor no considere válida,
/// aunque el backend devuelva intervalos más largos.
List<RanuraDisponible> generarRanurasDisponibles(
  Iterable<IntervaloHorario> intervalos,
) {
  final List<RanuraDisponible> ranuras = <RanuraDisponible>[];
  final Set<String> vistas = <String>{};

  for (final IntervaloHorario intervalo in intervalos) {
    int cursor = minutosDe(intervalo.horaInicio);
    final int fin = minutosDe(intervalo.horaFin);
    if (cursor < 0 || fin <= cursor) continue;

    while (cursor + duracionCitaMinutos <= fin) {
      final RanuraDisponible ranura = RanuraDisponible(
        horaInicio: horaDesdeMinutos(cursor),
        horaFin: horaDesdeMinutos(cursor + duracionCitaMinutos),
      );

      if (vistas.add(ranura.horaInicio)) {
        ranuras.add(ranura);
      }

      cursor += duracionCitaMinutos;
    }
  }

  ranuras.sort((a, b) => a.horaInicio.compareTo(b.horaInicio));
  return ranuras;
}

/// Etiqueta legible de un estado real de la cita.
String etiquetaEstadoCita(String estado) {
  switch (estado.trim().toUpperCase()) {
    case citaProgramada:
      return 'Programada';
    case citaConfirmada:
      return 'Confirmada';
    case citaEnEspera:
      return 'En espera';
    case citaAtendida:
      return 'Atendida';
    case citaCancelada:
      return 'Cancelada';
    case citaNoAsistio:
      return 'No asistió';
    default:
      return estado.trim().isEmpty ? 'Sin estado' : estado.trim();
  }
}

/// Convierte una fecha a `YYYY-MM-DD` (formato del contrato).
String fechaIso(DateTime fecha) {
  final String mes = fecha.month.toString().padLeft(2, '0');
  final String dia = fecha.day.toString().padLeft(2, '0');
  return '${fecha.year}-$mes-$dia';
}

/// Fecha larga en español: `lunes 3 de noviembre de 2026`.
String fechaLargaEspanol(DateTime fecha) {
  const List<String> dias = <String>[
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  const List<String> meses = <String>[
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  final String diaSemana = dias[(fecha.weekday - 1).clamp(0, 6)];
  final String mes = meses[(fecha.month - 1).clamp(0, 11)];
  return '$diaSemana ${fecha.day} de $mes de ${fecha.year}';
}

/// Fecha corta en español: `03/11/2026`.
String fechaCorta(DateTime fecha) {
  final String dia = fecha.day.toString().padLeft(2, '0');
  final String mes = fecha.month.toString().padLeft(2, '0');
  return '$dia/$mes/${fecha.year}';
}

/// Convierte el valor `num`/`String` de una clave JSON a `int`.
int? _entero(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) return int.tryParse(valor);
  return null;
}

/// Normaliza un texto opcional: `null` o vacío se conserva como `null`.
String? _textoOpcional(Object? valor) {
  if (valor is! String) return null;
  final String texto = valor.trim();
  return texto.isEmpty ? null : texto;
}

/// Parsea `YYYY-MM-DD` de forma tolerante.
DateTime _fecha(Object? valor) {
  if (valor is String && valor.trim().isNotEmpty) {
    return DateTime.tryParse(valor.trim()) ?? DateTime(1900);
  }
  return DateTime(1900);
}

/// Normaliza una hora del backend (`HH:MM:SS`).
String _hora(Object? valor) {
  if (valor is! String) return '';
  return valor.trim();
}

/// Convierte `HH:MM[:SS]` a minutos desde la medianoche (`-1` si no es válida).
int minutosDe(String hora) {
  final List<String> partes = hora.trim().split(':');
  if (partes.length < 2) return -1;

  final int? hh = int.tryParse(partes[0]);
  final int? mm = int.tryParse(partes[1]);
  if (hh == null || mm == null) return -1;
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return -1;

  return hh * 60 + mm;
}

/// Convierte minutos desde la medianoche a `HH:MM:SS`.
String horaDesdeMinutos(int minutos) {
  final String hh = (minutos ~/ 60).toString().padLeft(2, '0');
  final String mm = (minutos % 60).toString().padLeft(2, '0');
  return '$hh:$mm:00';
}

/// Convierte `HH:MM:SS` (u `HH:MM`) en `HH:mm` para mostrar.
String horaCorta(String hora) {
  final List<String> partes = hora.trim().split(':');
  if (partes.length < 2) {
    return hora.trim().isEmpty ? '--:--' : hora.trim();
  }
  final String hh = partes[0].padLeft(2, '0');
  final String mm = partes[1].padLeft(2, '0');
  return '$hh:$mm';
}
