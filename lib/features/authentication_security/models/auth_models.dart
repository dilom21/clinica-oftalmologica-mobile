/// Modelo de la petición de inicio de sesión enviada a FastAPI.
class LoginRequest {
  const LoginRequest({
    required this.correo,
    required this.password,
  });

  /// Correo electrónico del usuario.
  final String correo;

  /// Contraseña del usuario.
  final String password;

  /// Convierte el modelo a JSON para el cuerpo del POST.
  ///
  /// FastAPI espera exactamente:
  /// ```json
  /// { "correo": "...", "password": "..." }
  /// ```
  Map<String, dynamic> toJson() {
    return {
      'correo': correo,
      'password': password,
    };
  }
}

/// Modelo de la respuesta de inicio de sesión devuelta por FastAPI.
class LoginResponse {
  const LoginResponse({
    required this.accessToken,
    required this.tokenType,
  });

  /// Token JWT de acceso.
  final String accessToken;

  /// Tipo de token (FastAPI devuelve `bearer`).
  final String tokenType;

  /// Crea un [LoginResponse] desde el JSON devuelto por FastAPI:
  ///
  /// ```json
  /// { "access_token": "...", "token_type": "bearer" }
  /// ```
  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'token_type': tokenType,
    };
  }
}

/// Modelo de la petición de registro de paciente (app móvil).
///
/// Contiene EXACTAMENTE los campos que acepta
/// `POST /seguridad/registro-paciente`. El backend decide si el paciente ya
/// existía o debe crearse; Flutter solo envía los datos.
class RegistroPacienteRequest {
  const RegistroPacienteRequest({
    required this.ci,
    required this.nombres,
    required this.apellidos,
    required this.fechaNacimiento,
    required this.sexo,
    required this.telefono,
    this.contactoEmergencia,
    this.direccion,
    required this.correo,
    required this.password,
  });

  /// Carnet de identidad del paciente.
  final String ci;

  /// Nombres del paciente.
  final String nombres;

  /// Apellidos del paciente.
  final String apellidos;

  /// Fecha de nacimiento (se envía como `YYYY-MM-DD`).
  final DateTime fechaNacimiento;

  /// Sexo del paciente (`M` o `F`, según lo que acepta el backend).
  final String sexo;

  /// Teléfono del paciente.
  final String telefono;

  /// Contacto de emergencia (opcional en el backend).
  final String? contactoEmergencia;

  /// Dirección (opcional en el backend).
  final String? direccion;

  /// Correo electrónico con el que iniciará sesión.
  final String correo;

  /// Contraseña de acceso.
  final String password;

  /// Convierte el modelo al JSON exacto que espera FastAPI.
  Map<String, dynamic> toJson() {
    return {
      'ci': ci,
      'nombres': nombres,
      'apellidos': apellidos,
      'fecha_nacimiento': _fechaIso(fechaNacimiento),
      'sexo': sexo,
      'telefono': telefono,
      'contacto_emergencia': contactoEmergencia,
      'direccion': direccion,
      'correo': correo,
      'password': password,
    };
  }

  static String _fechaIso(DateTime fecha) {
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '${fecha.year}-$mes-$dia';
  }
}

/// Modelo de la respuesta de `POST /seguridad/registro-paciente`.
class RegistroPacienteResponse {
  const RegistroPacienteResponse({required this.message});

  /// Mensaje devuelto por el backend, p. ej. "Cuenta creada correctamente".
  final String message;

  factory RegistroPacienteResponse.fromJson(Map<String, dynamic> json) {
    return RegistroPacienteResponse(
      message: json['message'] as String? ?? '',
    );
  }
}
