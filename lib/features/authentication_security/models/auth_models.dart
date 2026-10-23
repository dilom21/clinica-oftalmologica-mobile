/// Clínica (empresa) disponible para iniciar sesión, devuelta por
/// `GET /seguridad/tenant/empresas`.
///
/// El [codigo] lo genera el backend y se usa como `empresa_codigo` al
/// autenticarse; la app nunca lo escribe a mano ni deduce clínicas.
class EmpresaTenant {
  const EmpresaTenant({required this.codigo, required this.nombre});

  /// Código interno de la empresa (se envía a FastAPI en el login).
  final String codigo;

  /// Nombre comercial que se muestra al paciente.
  final String nombre;

  /// Crea una empresa a partir del JSON de FastAPI:
  ///
  /// ```json
  /// { "codigo": "CLINICA_CENTRAL", "nombre": "Clínica Central" }
  /// ```
  ///
  /// El nombre lo decide cada clínica en el backend: la app nunca lo escribe.
  /// Si `nombre` viene vacío se usa el código como etiqueta visible.
  factory EmpresaTenant.fromJson(Map<String, dynamic> json) {
    final codigo = (json['codigo'] ?? '').toString().trim();
    final nombre = (json['nombre'] ?? '').toString().trim();

    return EmpresaTenant(
      codigo: codigo,
      nombre: nombre.isEmpty ? codigo : nombre,
    );
  }

  /// Dos clínicas son la misma cuando comparten código.
  @override
  bool operator ==(Object other) {
    return other is EmpresaTenant && other.codigo == codigo;
  }

  @override
  int get hashCode => codigo.hashCode;
}

/// Modelo de la petición de inicio de sesión enviada a FastAPI.
class LoginRequest {
  const LoginRequest({
    required this.empresaCodigo,
    required this.correo,
    required this.password,
  });

  /// Código de la clínica elegida en el selector (viene de
  /// `GET /seguridad/tenant/empresas`).
  final String empresaCodigo;

  /// Correo electrónico del usuario.
  final String correo;

  /// Contraseña del usuario.
  final String password;

  /// Convierte el modelo a JSON para el cuerpo del POST.
  ///
  /// FastAPI espera exactamente:
  /// ```json
  /// { "empresa_codigo": "...", "correo": "...", "password": "..." }
  /// ```
  Map<String, dynamic> toJson() {
    return {
      'empresa_codigo': empresaCodigo,
      'correo': correo,
      'password': password,
    };
  }
}

/// Modelo de la respuesta de inicio de sesión devuelta por FastAPI.
class LoginResponse {
  const LoginResponse({required this.accessToken, required this.tokenType});

  /// Token JWT de acceso.
  final String accessToken;

  /// Tipo de token de la respuesta HTTP (FastAPI devuelve `bearer`).
  ///
  /// No confundir con el claim `token_type` del JWT tenant, que debe ser
  /// `tenant` y lo valida `AuthService.loginPaciente`.
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
    return {'access_token': accessToken, 'token_type': tokenType};
  }
}

/// Modelo de la petición de registro de paciente (app móvil).
///
/// Contiene EXACTAMENTE los campos que acepta
/// `POST /seguridad/tenant/registro-paciente`: los datos del paciente y el
/// `empresa_codigo` de la clínica elegida en el login. El backend resuelve la
/// base tenant a partir de ese código, por lo que la app nunca envía
/// `tenant_id`, `database_name`, `rol_id` ni `usuario_id`.
class RegistroPacienteRequest {
  const RegistroPacienteRequest({
    required this.empresaCodigo,
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

  /// Código de la clínica elegida en el login
  /// (`GET /seguridad/tenant/empresas`). La cuenta se crea en esa clínica y el
  /// backend resuelve su base tenant con este código.
  final String empresaCodigo;

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
  ///
  /// `empresa_codigo` viaja siempre en el cuerpo: sin él el backend no sabe en
  /// qué clínica crear la cuenta.
  Map<String, dynamic> toJson() {
    return {
      'empresa_codigo': empresaCodigo,
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
    return RegistroPacienteResponse(message: json['message'] as String? ?? '');
  }
}
