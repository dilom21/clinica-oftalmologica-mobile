/// Perfil real del paciente autenticado.
///
/// Corresponde exactamente a la respuesta de `GET /pacientes/me`.
/// NO mezclar con `LoginResponse` ni `RegistroPacienteResponse`.
class MiPerfilPaciente {
  const MiPerfilPaciente({
    required this.id,
    required this.correo,
    required this.nombres,
    required this.apellidos,
    required this.ci,
    required this.fechaNacimiento,
    required this.sexo,
    this.telefono,
    this.contactoEmergencia,
    this.direccion,
    required this.estado,
  });

  /// Identificador del paciente.
  final int id;

  /// Correo del usuario autenticado.
  final String correo;

  /// Nombres del paciente.
  final String nombres;

  /// Apellidos del paciente.
  final String apellidos;

  /// Carnet de identidad.
  final String ci;

  /// Fecha de nacimiento.
  final DateTime fechaNacimiento;

  /// Sexo (`M` o `F`).
  final String sexo;

  /// Teléfono (puede ser `null`).
  final String? telefono;

  /// Contacto de emergencia (puede ser `null`).
  final String? contactoEmergencia;

  /// Dirección (puede ser `null`).
  final String? direccion;

  /// Indica si el paciente está activo.
  final bool estado;

  /// Nombre completo: `nombres apellidos`.
  String get nombreCompleto => '$nombres $apellidos'.trim();

  /// Crea el modelo desde el JSON devuelto por el backend.
  ///
  /// El backend serializa `fecha_nacimiento` como `YYYY-MM-DD` y las claves
  /// usan snake_case (`contacto_emergencia`, etc.).
  factory MiPerfilPaciente.fromJson(Map<String, dynamic> json) {
    final fechaRaw = json['fecha_nacimiento'] as String?;
    final sexoRaw = json['sexo'] as String?;

    return MiPerfilPaciente(
      id: json['id'] as int,
      correo: json['correo'] as String? ?? '',
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      ci: json['ci'] as String? ?? '',
      fechaNacimiento: fechaRaw == null
          ? DateTime(1900)
          : DateTime.parse(fechaRaw),
      sexo: sexoRaw ?? '',
      telefono: json['telefono'] as String?,
      contactoEmergencia: json['contacto_emergencia'] as String?,
      direccion: json['direccion'] as String?,
      estado: json['estado'] as bool? ?? true,
    );
  }
}

class MiPerfilPacienteActualizar {
  const MiPerfilPacienteActualizar({
    required this.nombres,
    required this.apellidos,
    required this.fechaNacimiento,
    required this.sexo,
    this.telefono,
    this.contactoEmergencia,
    this.direccion,
  });

  final String nombres;
  final String apellidos;
  final DateTime fechaNacimiento;
  final String sexo;
  final String? telefono;
  final String? contactoEmergencia;
  final String? direccion;

  Map<String, dynamic> toJson() {
    return {
      'nombres': nombres,
      'apellidos': apellidos,
      'fecha_nacimiento': _fechaIso(fechaNacimiento),
      'sexo': sexo,
      'telefono': telefono,
      'contacto_emergencia': contactoEmergencia,
      'direccion': direccion,
    };
  }

  static String _fechaIso(DateTime fecha) {
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '${fecha.year}-$mes-$dia';
  }
}
