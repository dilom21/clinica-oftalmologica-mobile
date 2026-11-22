/// Datos mínimos que el chatbot puede proponer para abrir el flujo CU10.
///
/// No contiene `paciente_id`, `servicio_id` ni datos que deban resolverse en
/// el formulario real. La disponibilidad SIEMPRE se vuelve a consultar antes
/// de habilitar la confirmación.
class PreseleccionCita {
  const PreseleccionCita({
    required this.oftalmologoId,
    required this.fecha,
    required this.horaInicio,
  });

  final int oftalmologoId;

  /// Fecha propuesta (sin hora).
  final DateTime fecha;

  /// Hora de inicio en formato `HH:MM:SS` (o `HH:MM`).
  final String horaInicio;

  @override
  bool operator ==(Object other) {
    return other is PreseleccionCita &&
        other.oftalmologoId == oftalmologoId &&
        other.fecha.year == fecha.year &&
        other.fecha.month == fecha.month &&
        other.fecha.day == fecha.day &&
        other.horaInicio == horaInicio;
  }

  @override
  int get hashCode => Object.hash(
    oftalmologoId,
    fecha.year,
    fecha.month,
    fecha.day,
    horaInicio,
  );
}
