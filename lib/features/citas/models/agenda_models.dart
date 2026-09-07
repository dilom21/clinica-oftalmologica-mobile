// Modelos del módulo Citas (CU09 - Consultar agenda y disponibilidad médica).
//
// Corresponden EXACTAMENTE a los schemas de FastAPI de CU09:
// - `GET /agenda-citas/oftalmologos`
// - `GET /agenda-citas/disponibilidad?oftalmologo_id={id}&fecha={YYYY-MM-DD}`
//
// El Paciente NO consume `/agenda-citas/oftalmologos/{id}/agenda`, por lo que
// no existe aquí ningún modelo de agenda interna con citas de pacientes.

/// Oftalmólogo activo listado para la consulta de disponibilidad.
///
/// Schema backend: `OftalmologoResumidoRespuesta`.
class OftalmologoAgenda {
  const OftalmologoAgenda({
    required this.id,
    required this.matricula,
    required this.nombres,
    required this.apellidos,
    this.especialidad,
  });

  /// Identificador del oftalmólogo.
  final int id;

  /// Matrícula profesional.
  final String matricula;

  /// Nombres del oftalmólogo.
  final String nombres;

  /// Apellidos del oftalmólogo.
  final String apellidos;

  /// Especialidad (puede ser `null`).
  final String? especialidad;

  /// Nombre completo: `nombres apellidos`.
  String get nombreCompleto => '$nombres $apellidos'.trim();

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory OftalmologoAgenda.fromJson(Map<String, dynamic> json) {
    return OftalmologoAgenda(
      id: _entero(json['id']) ?? 0,
      matricula: json['matricula'] as String? ?? '',
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      especialidad: _textoOpcional(json['especialidad']),
    );
  }
}

/// Intervalo horario (hora de inicio y fin) devuelto por el backend.
///
/// Schema backend: `IntervaloHorarioRespuesta`. FastAPI serializa `time`
/// como `HH:MM:SS` (ej. `08:00:00`). No se modela ni genera ninguna
/// duración/slot artificial.
class IntervaloHorario {
  const IntervaloHorario({required this.horaInicio, required this.horaFin});

  /// Hora de inicio (`hora_inicio`), p. ej. `08:00:00`.
  final String horaInicio;

  /// Hora de fin (`hora_fin`), p. ej. `08:30:00`.
  final String horaFin;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory IntervaloHorario.fromJson(Map<String, dynamic> json) {
    return IntervaloHorario(
      horaInicio: json['hora_inicio'] as String? ?? '',
      horaFin: json['hora_fin'] as String? ?? '',
    );
  }
}

/// Respuesta de `GET /agenda-citas/disponibilidad`.
///
/// Schema backend: `DisponibilidadRespuesta`.
class DisponibilidadRespuesta {
  const DisponibilidadRespuesta({
    required this.oftalmologo,
    required this.fecha,
    required this.tieneHorario,
    required this.horariosBase,
    required this.intervalosDisponibles,
  });

  /// Oftalmólogo consultado.
  final OftalmologoAgenda oftalmologo;

  /// Fecha consultada.
  final DateTime fecha;

  /// Indica si el oftalmólogo tiene horario base configurado para la fecha.
  final bool tieneHorario;

  /// Horario base del día (intervalos configurados, sin citas).
  final List<IntervaloHorario> horariosBase;

  /// Intervalos realmente libres calculados por el backend.
  final List<IntervaloHorario> intervalosDisponibles;

  /// Crea el modelo desde el JSON devuelto por el backend.
  factory DisponibilidadRespuesta.fromJson(Map<String, dynamic> json) {
    final oftalmologoJson = json['oftalmologo'];
    final fechaRaw = json['fecha'] as String?;

    return DisponibilidadRespuesta(
      oftalmologo: oftalmologoJson is Map<String, dynamic>
          ? OftalmologoAgenda.fromJson(oftalmologoJson)
          : const OftalmologoAgenda(
              id: 0,
              matricula: '',
              nombres: '',
              apellidos: '',
            ),
      fecha: fechaRaw == null || fechaRaw.isEmpty
          ? DateTime(1900)
          : DateTime.parse(fechaRaw),
      tieneHorario: json['tiene_horario'] as bool? ?? false,
      horariosBase: _intervalos(json['horarios_base']),
      intervalosDisponibles: _intervalos(json['intervalos_disponibles']),
    );
  }
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
  final texto = valor.trim();
  return texto.isEmpty ? null : texto;
}

/// Parsea una lista de intervalos desde JSON de forma tolerante.
List<IntervaloHorario> _intervalos(Object? valor) {
  if (valor is! List) return const [];
  return [
    for (final item in valor)
      if (item is Map<String, dynamic>) IntervaloHorario.fromJson(item),
  ];
}
