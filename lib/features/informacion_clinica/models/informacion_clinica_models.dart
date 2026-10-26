import '../../pagos/models/pago_models.dart';

/// Información clínica que el paciente autenticado está autorizado a ver.
///
/// Llega de `GET /historial-clinico/mi-informacion`. El backend ya excluye
/// registros inactivos y datos de otros pacientes.
class InformacionClinicaAutorizada {
  const InformacionClinicaAutorizada({
    required this.historialId,
    required this.fechaApertura,
    required this.observacionesGenerales,
    required this.antecedentes,
    required this.consultas,
    required this.controles,
  });

  final int? historialId;
  final DateTime? fechaApertura;
  final String? observacionesGenerales;
  final List<AntecedenteClinicoAutorizado> antecedentes;
  final List<ConsultaClinicaAutorizada> consultas;
  final List<ControlMedicoAutorizado> controles;

  bool get estaVacia =>
      historialId == null &&
      antecedentes.isEmpty &&
      consultas.isEmpty &&
      controles.isEmpty;

  factory InformacionClinicaAutorizada.fromJson(Map<String, dynamic> json) {
    return InformacionClinicaAutorizada(
      historialId: _entero(json['historial_id']),
      fechaApertura: _fecha(json['fecha_apertura']),
      observacionesGenerales: _texto(json['observaciones_generales']),
      antecedentes: _lista(
        json['antecedentes'],
        AntecedenteClinicoAutorizado.fromJson,
      ),
      consultas: _lista(json['consultas'], ConsultaClinicaAutorizada.fromJson),
      controles: _lista(json['controles'], ControlMedicoAutorizado.fromJson),
    );
  }
}

class OftalmologoClinico {
  const OftalmologoClinico({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.especialidad,
  });

  final int id;
  final String nombres;
  final String apellidos;
  final String? especialidad;

  String get nombreCompleto {
    final nombre = '$nombres $apellidos'.trim();
    return nombre.isEmpty ? 'Oftalmólogo' : nombre;
  }

  factory OftalmologoClinico.fromJson(Map<String, dynamic> json) {
    return OftalmologoClinico(
      id: _entero(json['id']) ?? 0,
      nombres: _texto(json['nombres']) ?? '',
      apellidos: _texto(json['apellidos']) ?? '',
      especialidad: _texto(json['especialidad']),
    );
  }
}

class AntecedenteClinicoAutorizado {
  const AntecedenteClinicoAutorizado({
    required this.id,
    required this.tipo,
    required this.descripcion,
    required this.fechaRegistro,
  });

  final int id;
  final String tipo;
  final String descripcion;
  final DateTime? fechaRegistro;

  factory AntecedenteClinicoAutorizado.fromJson(Map<String, dynamic> json) {
    return AntecedenteClinicoAutorizado(
      id: _entero(json['id']) ?? 0,
      tipo: _texto(json['tipo']) ?? 'OTRO',
      descripcion: _texto(json['descripcion']) ?? '',
      fechaRegistro: _fecha(json['fecha_registro']),
    );
  }
}

class ConsultaClinicaAutorizada {
  const ConsultaClinicaAutorizada({
    required this.id,
    required this.fechaConsulta,
    required this.motivoConsulta,
    required this.anamnesis,
    required this.observaciones,
    required this.oftalmologo,
    required this.diagnosticos,
    required this.tratamientos,
    required this.indicaciones,
    required this.recetas,
    required this.examenes,
  });

  final int id;
  final DateTime? fechaConsulta;
  final String? motivoConsulta;
  final String? anamnesis;
  final String? observaciones;
  final OftalmologoClinico oftalmologo;
  final List<DiagnosticoAutorizado> diagnosticos;
  final List<TratamientoAutorizado> tratamientos;
  final List<IndicacionAutorizada> indicaciones;
  final List<RecetaAutorizada> recetas;
  final List<ExamenAutorizado> examenes;

  String get titulo =>
      (motivoConsulta == null || motivoConsulta!.trim().isEmpty)
      ? 'Consulta clínica'
      : motivoConsulta!.trim();

  factory ConsultaClinicaAutorizada.fromJson(Map<String, dynamic> json) {
    final oftalmologo = json['oftalmologo'];
    return ConsultaClinicaAutorizada(
      id: _entero(json['id']) ?? 0,
      fechaConsulta: _fecha(json['fecha_consulta']),
      motivoConsulta: _texto(json['motivo_consulta']),
      anamnesis: _texto(json['anamnesis']),
      observaciones: _texto(json['observaciones']),
      oftalmologo: oftalmologo is Map<String, dynamic>
          ? OftalmologoClinico.fromJson(oftalmologo)
          : const OftalmologoClinico(
              id: 0,
              nombres: '',
              apellidos: '',
              especialidad: null,
            ),
      diagnosticos: _lista(json['diagnosticos'], DiagnosticoAutorizado.fromJson),
      tratamientos: _lista(
        json['tratamientos'],
        TratamientoAutorizado.fromJson,
      ),
      indicaciones: _lista(json['indicaciones'], IndicacionAutorizada.fromJson),
      recetas: _lista(json['recetas'], RecetaAutorizada.fromJson),
      examenes: _lista(json['examenes'], ExamenAutorizado.fromJson),
    );
  }
}

class DiagnosticoAutorizado {
  const DiagnosticoAutorizado({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.fechaDiagnostico,
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final DateTime? fechaDiagnostico;

  factory DiagnosticoAutorizado.fromJson(Map<String, dynamic> json) {
    return DiagnosticoAutorizado(
      id: _entero(json['id']) ?? 0,
      nombre: _texto(json['nombre']) ?? 'Diagnóstico',
      descripcion: _texto(json['descripcion']),
      fechaDiagnostico: _fecha(json['fecha_diagnostico']),
    );
  }
}

class TratamientoAutorizado {
  const TratamientoAutorizado({
    required this.id,
    required this.descripcion,
    required this.observaciones,
    required this.fechaInicio,
    required this.fechaFin,
  });

  final int id;
  final String descripcion;
  final String? observaciones;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  factory TratamientoAutorizado.fromJson(Map<String, dynamic> json) {
    return TratamientoAutorizado(
      id: _entero(json['id']) ?? 0,
      descripcion: _texto(json['descripcion']) ?? '',
      observaciones: _texto(json['observaciones']),
      fechaInicio: _fecha(json['fecha_inicio']),
      fechaFin: _fecha(json['fecha_fin']),
    );
  }
}

class IndicacionAutorizada {
  const IndicacionAutorizada({
    required this.id,
    required this.descripcion,
    required this.fechaRegistro,
  });

  final int id;
  final String descripcion;
  final DateTime? fechaRegistro;

  factory IndicacionAutorizada.fromJson(Map<String, dynamic> json) {
    return IndicacionAutorizada(
      id: _entero(json['id']) ?? 0,
      descripcion: _texto(json['descripcion']) ?? '',
      fechaRegistro: _fecha(json['fecha_registro']),
    );
  }
}

class RecetaAutorizada {
  const RecetaAutorizada({
    required this.id,
    required this.fechaEmision,
    required this.observaciones,
    required this.detalles,
  });

  final int id;
  final DateTime? fechaEmision;
  final String? observaciones;
  final List<DetalleRecetaAutorizado> detalles;

  factory RecetaAutorizada.fromJson(Map<String, dynamic> json) {
    return RecetaAutorizada(
      id: _entero(json['id']) ?? 0,
      fechaEmision: _fecha(json['fecha_emision']),
      observaciones: _texto(json['observaciones']),
      detalles: _lista(json['detalles'], DetalleRecetaAutorizado.fromJson),
    );
  }
}

class DetalleRecetaAutorizado {
  const DetalleRecetaAutorizado({
    required this.id,
    required this.medicamento,
    required this.presentacion,
    required this.dosis,
    required this.frecuencia,
    required this.duracion,
    required this.indicaciones,
  });

  final int id;
  final String medicamento;
  final String? presentacion;
  final String? dosis;
  final String? frecuencia;
  final String? duracion;
  final String? indicaciones;

  factory DetalleRecetaAutorizado.fromJson(Map<String, dynamic> json) {
    return DetalleRecetaAutorizado(
      id: _entero(json['id']) ?? 0,
      medicamento: _texto(json['medicamento']) ?? '',
      presentacion: _texto(json['presentacion']),
      dosis: _texto(json['dosis']),
      frecuencia: _texto(json['frecuencia']),
      duracion: _texto(json['duracion']),
      indicaciones: _texto(json['indicaciones']),
    );
  }
}

class ExamenAutorizado {
  const ExamenAutorizado({
    required this.id,
    required this.nombreExamen,
    required this.fechaSolicitud,
    required this.observaciones,
    required this.resultados,
  });

  final int id;
  final String nombreExamen;
  final DateTime? fechaSolicitud;
  final String? observaciones;
  final List<ResultadoExamenAutorizado> resultados;

  factory ExamenAutorizado.fromJson(Map<String, dynamic> json) {
    return ExamenAutorizado(
      id: _entero(json['id']) ?? 0,
      nombreExamen: _texto(json['nombre_examen']) ?? 'Examen',
      fechaSolicitud: _fecha(json['fecha_solicitud']),
      observaciones: _texto(json['observaciones']),
      resultados: _lista(json['resultados'], ResultadoExamenAutorizado.fromJson),
    );
  }
}

class ResultadoExamenAutorizado {
  const ResultadoExamenAutorizado({
    required this.id,
    required this.fechaResultado,
    required this.resultado,
  });

  final int id;
  final DateTime? fechaResultado;
  final String resultado;

  factory ResultadoExamenAutorizado.fromJson(Map<String, dynamic> json) {
    return ResultadoExamenAutorizado(
      id: _entero(json['id']) ?? 0,
      fechaResultado: _fecha(json['fecha_resultado']),
      resultado: _texto(json['resultado']) ?? '',
    );
  }
}

class ControlMedicoAutorizado {
  const ControlMedicoAutorizado({
    required this.id,
    required this.fechaProgramada,
    required this.motivo,
    required this.observaciones,
    required this.estado,
    required this.oftalmologo,
  });

  final int id;
  final DateTime? fechaProgramada;
  final String? motivo;
  final String? observaciones;
  final String? estado;
  final OftalmologoClinico oftalmologo;

  factory ControlMedicoAutorizado.fromJson(Map<String, dynamic> json) {
    final oftalmologo = json['oftalmologo'];
    return ControlMedicoAutorizado(
      id: _entero(json['id']) ?? 0,
      fechaProgramada: _fecha(json['fecha_programada']),
      motivo: _texto(json['motivo']),
      observaciones: _texto(json['observaciones']),
      estado: _texto(json['estado']),
      oftalmologo: oftalmologo is Map<String, dynamic>
          ? OftalmologoClinico.fromJson(oftalmologo)
          : const OftalmologoClinico(
              id: 0,
              nombres: '',
              apellidos: '',
              especialidad: null,
            ),
    );
  }
}

/// Etiqueta visible de un tipo de antecedente clínico.
String etiquetaTipoAntecedente(String tipo) {
  switch (tipo) {
    case 'ALERGIA':
      return 'Alergia';
    case 'ENFERMEDAD':
      return 'Enfermedad';
    case 'CIRUGIA':
      return 'Cirugía';
    case 'MEDICAMENTO':
      return 'Medicamento';
    case 'ANTECEDENTE_FAMILIAR':
      return 'Antecedente familiar';
    case 'OTRO':
      return 'Otro';
    default:
      return tipo;
  }
}

/// Etiqueta visible del estado de un control médico.
String etiquetaEstadoControl(String? estado) {
  switch (estado) {
    case 'REALIZADO':
      return 'Realizado';
    case 'PROGRAMADO':
    case null:
    case '':
      return 'Programado';
    default:
      return estado;
  }
}

int? _entero(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return null;
}

String? _texto(Object? valor) {
  if (valor is! String) return null;
  final limpio = valor.trim();
  return limpio.isEmpty ? null : limpio;
}

DateTime? _fecha(Object? valor) {
  if (valor is String && valor.isNotEmpty) return DateTime.tryParse(valor);
  return null;
}

List<T> _lista<T>(Object? valor, T Function(Map<String, dynamic>) mapear) {
  if (valor is! List) return <T>[];
  return [
    for (final item in valor)
      if (item is Map<String, dynamic>) mapear(item),
  ];
}

/// Fecha de calendario (`dd/MM/yyyy`) sin convertir zona horaria.
String fechaClinica(DateTime? fecha) => formatearFecha(fecha);

/// Fecha y hora de un registro clínico, en hora de Bolivia.
String fechaHoraClinica(DateTime? fecha) => formatearFechaHoraBolivia(fecha);
