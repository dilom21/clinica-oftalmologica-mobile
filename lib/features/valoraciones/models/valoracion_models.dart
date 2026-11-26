// Modelos de datos del módulo CU40 — Valoración de la Clínica (Móvil).
//
// Reflejan exactamente los contratos JSON de `/seguridad/valoraciones/*`.

const int puntuacionMinimaValoracion = 1;
const int puntuacionMaximaValoracion = 5;
const int comentarioMaxLongitudValoracion = 1000;

/// Etiqueta legible para la escala de 1 a 5 estrellas.
String etiquetaParaPuntuacion(int puntuacion) {
  switch (puntuacion) {
    case 1:
      return 'Muy mala';
    case 2:
      return 'Mala';
    case 3:
      return 'Regular';
    case 4:
      return 'Buena';
    case 5:
      return 'Excelente';
    default:
      return 'Sin calificar';
  }
}

/// Resumen del médico que realizó la atención.
class OftalmologoValoracion {
  const OftalmologoValoracion({
    required this.id,
    required this.nombres,
    required this.apellidos,
    this.especialidad,
    required this.nombreCompleto,
  });

  final int id;
  final String nombres;
  final String apellidos;
  final String? especialidad;
  final String nombreCompleto;

  factory OftalmologoValoracion.fromJson(Map<String, dynamic> json) {
    final nombres = (json['nombres'] as String? ?? '').trim();
    final apellidos = (json['apellidos'] as String? ?? '').trim();
    final completo = (json['nombre_completo'] as String? ?? '').trim();

    return OftalmologoValoracion(
      id: (json['id'] as num).toInt(),
      nombres: nombres,
      apellidos: apellidos,
      especialidad: json['especialidad'] as String?,
      nombreCompleto: completo.isNotEmpty
          ? completo
          : '$nombres $apellidos'.trim(),
    );
  }
}

/// Valoración registrada o actualizada por el paciente sobre una atención.
class ValoracionClinica {
  const ValoracionClinica({
    required this.id,
    required this.pacienteId,
    required this.consultaClinicaId,
    required this.oftalmologoId,
    required this.puntuacion,
    required this.etiquetaPuntuacion,
    this.comentario,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    this.fechaConsulta,
    this.motivoConsulta,
    this.oftalmologo,
    this.empresaCodigo,
    this.empresaNombre,
    this.mensaje,
  });

  final int id;
  final int pacienteId;
  final int consultaClinicaId;
  final int oftalmologoId;
  final int puntuacion;
  final String etiquetaPuntuacion;
  final String? comentario;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;
  final DateTime? fechaConsulta;
  final String? motivoConsulta;
  final OftalmologoValoracion? oftalmologo;
  final String? empresaCodigo;
  final String? empresaNombre;
  final String? mensaje;

  factory ValoracionClinica.fromJson(Map<String, dynamic> json) {
    final puntuacion = (json['puntuacion'] as num).toInt();
    final oftJson = json['oftalmologo'];

    return ValoracionClinica(
      id: (json['id'] as num).toInt(),
      pacienteId: (json['paciente_id'] as num).toInt(),
      consultaClinicaId: (json['consulta_clinica_id'] as num).toInt(),
      oftalmologoId: (json['oftalmologo_id'] as num).toInt(),
      puntuacion: puntuacion,
      etiquetaPuntuacion:
          (json['etiqueta_puntuacion'] as String?)?.trim().isNotEmpty == true
          ? (json['etiqueta_puntuacion'] as String).trim()
          : etiquetaParaPuntuacion(puntuacion),
      comentario: json['comentario'] as String?,
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      fechaActualizacion: DateTime.parse(json['fecha_actualizacion'] as String),
      fechaConsulta: json['fecha_consulta'] != null
          ? DateTime.parse(json['fecha_consulta'] as String)
          : null,
      motivoConsulta: json['motivo_consulta'] as String?,
      oftalmologo: oftJson is Map<String, dynamic>
          ? OftalmologoValoracion.fromJson(oftJson)
          : null,
      empresaCodigo: json['empresa_codigo'] as String?,
      empresaNombre: json['empresa_nombre'] as String?,
      mensaje: json['mensaje'] as String?,
    );
  }
}

/// Aviso/mensaje in-app recibido tras finalizar una revisión o emitir receta.
class NotificacionValoracion {
  const NotificacionValoracion({
    this.id,
    required this.consultaClinicaId,
    required this.fechaConsulta,
    this.motivoConsulta,
    required this.tieneReceta,
    required this.oftalmologo,
    required this.motivoDisparo,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    required this.atendida,
    required this.fechaCreacion,
    this.empresaCodigo,
    this.empresaNombre,
  });

  final int? id;
  final int consultaClinicaId;
  final DateTime fechaConsulta;
  final String? motivoConsulta;
  final bool tieneReceta;
  final OftalmologoValoracion oftalmologo;
  final String motivoDisparo;
  final String titulo;
  final String mensaje;
  final bool leida;
  final bool atendida;
  final DateTime fechaCreacion;
  final String? empresaCodigo;
  final String? empresaNombre;

  factory NotificacionValoracion.fromJson(Map<String, dynamic> json) {
    return NotificacionValoracion(
      id: (json['id'] as num?)?.toInt(),
      consultaClinicaId: (json['consulta_clinica_id'] as num).toInt(),
      fechaConsulta: DateTime.parse(json['fecha_consulta'] as String),
      motivoConsulta: json['motivo_consulta'] as String?,
      tieneReceta: json['tiene_receta'] as bool? ?? false,
      oftalmologo: OftalmologoValoracion.fromJson(
        json['oftalmologo'] as Map<String, dynamic>,
      ),
      motivoDisparo: json['motivo_disparo'] as String? ?? 'CONSULTA_FINALIZADA',
      titulo: json['titulo'] as String? ?? '¿Cómo fue tu atención médica?',
      mensaje: json['mensaje'] as String? ?? '',
      leida: json['leida'] as bool? ?? false,
      atendida: json['atendida'] as bool? ?? false,
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      empresaCodigo: json['empresa_codigo'] as String?,
      empresaNombre: json['empresa_nombre'] as String?,
    );
  }
}

/// Atención clínica del paciente con su estado de valoración.
class AtencionValorable {
  const AtencionValorable({
    required this.consultaClinicaId,
    required this.fechaConsulta,
    this.motivoConsulta,
    required this.tieneReceta,
    required this.oftalmologo,
    this.notificacion,
    this.valoracion,
    required this.puedeActualizar,
  });

  final int consultaClinicaId;
  final DateTime fechaConsulta;
  final String? motivoConsulta;
  final bool tieneReceta;
  final OftalmologoValoracion oftalmologo;
  final NotificacionValoracion? notificacion;
  final ValoracionClinica? valoracion;
  final bool puedeActualizar;

  bool get estaValorada => valoracion != null;

  factory AtencionValorable.fromJson(Map<String, dynamic> json) {
    final notifJson = json['notificacion'];
    final valJson = json['valoracion'];

    return AtencionValorable(
      consultaClinicaId: (json['consulta_clinica_id'] as num).toInt(),
      fechaConsulta: DateTime.parse(json['fecha_consulta'] as String),
      motivoConsulta: json['motivo_consulta'] as String?,
      tieneReceta: json['tiene_receta'] as bool? ?? false,
      oftalmologo: OftalmologoValoracion.fromJson(
        json['oftalmologo'] as Map<String, dynamic>,
      ),
      notificacion: notifJson is Map<String, dynamic>
          ? NotificacionValoracion.fromJson(notifJson)
          : null,
      valoracion: valJson is Map<String, dynamic>
          ? ValoracionClinica.fromJson(valJson)
          : null,
      puedeActualizar: json['puede_actualizar'] as bool? ?? (valJson != null),
    );
  }
}

/// Respuesta agregada de `GET /seguridad/valoraciones/resumen`.
class ResumenValoracionesPaciente {
  const ResumenValoracionesPaciente({
    this.empresaCodigo,
    this.empresaNombre,
    this.escalaMinima = puntuacionMinimaValoracion,
    this.escalaMaxima = puntuacionMaximaValoracion,
    required this.pendientes,
    required this.atenciones,
    required this.valoraciones,
  });

  final String? empresaCodigo;
  final String? empresaNombre;
  final int escalaMinima;
  final int escalaMaxima;
  final List<NotificacionValoracion> pendientes;
  final List<AtencionValorable> atenciones;
  final List<ValoracionClinica> valoraciones;

  factory ResumenValoracionesPaciente.fromJson(Map<String, dynamic> json) {
    final pendientesRaw = json['pendientes'] as List<dynamic>? ?? const [];
    final atencionesRaw = json['atenciones'] as List<dynamic>? ?? const [];
    final valoracionesRaw = json['valoraciones'] as List<dynamic>? ?? const [];

    return ResumenValoracionesPaciente(
      empresaCodigo: json['empresa_codigo'] as String?,
      empresaNombre: json['empresa_nombre'] as String?,
      escalaMinima:
          (json['escala_minima'] as num?)?.toInt() ?? puntuacionMinimaValoracion,
      escalaMaxima:
          (json['escala_maxima'] as num?)?.toInt() ?? puntuacionMaximaValoracion,
      pendientes: [
        for (final item in pendientesRaw)
          if (item is Map<String, dynamic>)
            NotificacionValoracion.fromJson(item),
      ],
      atenciones: [
        for (final item in atencionesRaw)
          if (item is Map<String, dynamic>) AtencionValorable.fromJson(item),
      ],
      valoraciones: [
        for (final item in valoracionesRaw)
          if (item is Map<String, dynamic>) ValoracionClinica.fromJson(item),
      ],
    );
  }
}
