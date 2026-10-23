import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/auth_models.dart';

/// Excepción lanzada cuando una petición de autenticación falla.
///
/// Contiene un [message] entendible para mostrarse al usuario.
class AuthException implements Exception {
  const AuthException(this.message, {this.sesionRechazada = false});

  /// Mensaje legible que describe el error ocurrido.
  final String message;

  /// Indica que el fallo proviene de un JWT que no cumple el contrato tenant
  /// (token legacy, rol no permitido, claims obligatorios ausentes o clínica
  /// distinta a la elegida).
  ///
  /// La pantalla de login usa esta marca para descartar cualquier sesión
  /// anterior: un token que la app no pudo validar nunca se reutiliza.
  final bool sesionRechazada;

  @override
  String toString() => message;
}

/// Servicio de autenticación de la aplicación móvil (exclusiva de pacientes).
///
/// Usa el login multitenant del backend:
///
/// - `GET  /seguridad/tenant/empresas`: clínicas disponibles.
/// - `POST /seguridad/tenant/login`: autenticación contra la clínica elegida
///   (`empresa_codigo`).
///
/// Toda la comunicación HTTP vive aquí; las páginas nunca llaman HTTP directo.
/// La contraseña y el JWT nunca se escriben en logs.
///
/// Antes de aceptar una sesión se inspecciona el JWT (sin verificar la firma,
/// que sigue siendo responsabilidad de FastAPI) para exigir el contrato
/// tenant: `token_type = "tenant"`, `rol_nombre = "Paciente"` y
/// `empresa_codigo` igual a la clínica elegida.
class AuthService {
  AuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Tiempo máximo de espera para una respuesta del servidor.
  static const Duration _timeout = Duration(seconds: 20);

  /// Valor obligatorio del claim `token_type` en un JWT tenant.
  ///
  /// Un token sin este claim (o con `bearer` u otro valor) es legacy y la app
  /// móvil no lo acepta.
  static const String tokenTypeTenant = 'tenant';

  /// Nombre del rol aceptado por la app (claim `rol_nombre`).
  ///
  /// Es el ÚNICO criterio de rol: cada clínica tiene su propia tabla de roles,
  /// por lo que los ids NO son universales entre bases tenant y no se usan.
  static const String nombreRolPaciente = 'Paciente';

  /// Mensaje que se muestra cuando quien se autentica no es un paciente.
  static const String mensajeSoloParaPacientes =
      'Esta aplicación móvil está disponible únicamente para pacientes.';

  /// Mensaje cuando el JWT no declara `token_type = tenant`.
  static const String mensajeSesionNoTenant =
      'La sesión recibida no es una sesión tenant válida. '
      'Vuelve a iniciar sesión.';

  /// Mensaje cuando el JWT no declara el nombre del rol (`rol_nombre`).
  static const String mensajeRolNoIdentificado =
      'La sesión no indica el rol del usuario. Vuelve a iniciar sesión.';

  /// Mensaje cuando el JWT no declara la clínica (`empresa_codigo`).
  static const String mensajeClinicaNoIdentificada =
      'La sesión no indica la clínica de la cuenta. Vuelve a iniciar sesión.';

  /// Mensaje cuando no se seleccionó una clínica válida.
  static const String mensajeClinicaRequerida =
      'Selecciona la clínica donde tienes tu cuenta.';

  /// Mensaje cuando el JWT no corresponde a la clínica seleccionada.
  static const String mensajeClinicaDistinta =
      'La sesión no corresponde a la clínica seleccionada. Inténtalo de nuevo.';

  /// Mensaje cuando el backend responde 409 porque el paciente ya existe en la
  /// clínica y la app no puede vincular la cuenta automáticamente.
  ///
  /// La vinculación exige verificar la identidad en la clínica: la app nunca
  /// la ofrece por su cuenta.
  static const String mensajePacienteExistente =
      'Ya existe un registro con estos datos. Para vincular tu cuenta, debes '
      'verificar tu identidad directamente con la clínica.';

  /// Mensaje neutro para un 409 sin detalle del backend.
  ///
  /// No afirma que exista un expediente clínico: solo informa del conflicto.
  static const String mensajeConflictoRegistro =
      'No se pudo crear la cuenta por un conflicto con datos ya registrados. '
      'Verifica tus datos o comunícate directamente con la clínica.';

  /// Mensaje cuando la clínica no tiene una suscripción vigente (403).
  static const String mensajeClinicaSinSuscripcion =
      'La clínica no tiene una suscripción vigente. Contacta con la clínica '
      'para poder crear tu cuenta.';

  /// Mensaje cuando la clínica no existe o está inactiva (404).
  static const String mensajeClinicaNoDisponible =
      'La clínica seleccionada no existe o no está activa. '
      'Vuelve al inicio y elige otra clínica.';

  /// Lista las clínicas disponibles para iniciar sesión:
  ///
  /// `GET {ApiConfig.baseUrl}/seguridad/tenant/empresas`
  ///
  /// Devuelve los elementos tal como los entrega FastAPI (`codigo` y
  /// `nombre`). El código se conserva solo para enviarlo en el login; la
  /// interfaz muestra el nombre comercial. Una lista vacía es una respuesta
  /// válida (la pantalla muestra el estado "sin clínicas").
  Future<List<EmpresaTenant>> listarEmpresas() async {
    final http.Response response = await _get('/seguridad/tenant/empresas');

    if (response.statusCode != 200) {
      throw AuthException(_mensajeErrorListado(response));
    }

    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const AuthException(
        'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
      );
    }

    final Object? items = body is List
        ? body
        : body is Map<String, dynamic> && body['empresas'] is List
        ? body['empresas']
        : null;

    if (items is! List) {
      throw const AuthException(
        'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
      );
    }

    final empresas = <EmpresaTenant>[];
    final codigos = <String>{};

    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final empresa = EmpresaTenant.fromJson(item);

      // Se ignoran entradas sin código y duplicados.
      if (empresa.codigo.isEmpty || !codigos.add(empresa.codigo)) {
        continue;
      }

      empresas.add(empresa);
    }

    return empresas;
  }

  /// Inicio de sesión móvil contra la clínica seleccionada:
  ///
  /// `POST {ApiConfig.baseUrl}/seguridad/tenant/login`
  ///
  /// Envía exactamente `empresa_codigo`, `correo` y `password`. El backend
  /// resuelve la base tenant de la clínica; la app nunca envía nombres de
  /// bases PostgreSQL ni un `tenant_id` propio.
  ///
  /// Devuelve un [LoginResponse] solo cuando FastAPI responde 200 y el JWT
  /// cumple el contrato tenant completo:
  ///
  /// - `token_type` es `tenant` (un token legacy se rechaza).
  /// - `rol_nombre` existe y es `Paciente` (no se deduce de `rol` ni de
  ///   `rol_id`: los ids de rol cambian entre clínicas).
  /// - `empresa_codigo` existe y coincide con la clínica seleccionada.
  ///
  /// Si falta cualquiera de esos claims, o no coinciden, se lanza
  /// [AuthException] con [AuthException.sesionRechazada] y NO se devuelve
  /// token alguno.
  Future<LoginResponse> loginPaciente(LoginRequest request) async {
    final String empresaCodigo = request.empresaCodigo.trim();

    if (empresaCodigo.isEmpty) {
      throw const AuthException(mensajeClinicaRequerida);
    }

    final http.Response response = await _post(
      '/seguridad/tenant/login',
      request.toJson(),
    );

    if (response.statusCode != 200) {
      throw AuthException(_mensajeError(response));
    }

    final Map<String, dynamic> body = _decodificarObjeto(response);

    final LoginResponse login;
    try {
      login = LoginResponse.fromJson(body);
    } on TypeError {
      throw const AuthException(
        'La respuesta del servidor no contiene el access_token esperado.',
      );
    }

    final Map<String, dynamic>? claims = _claimsDelJwt(login.accessToken);

    if (claims == null) {
      throw const AuthException(
        'No se pudo verificar la sesión. Inténtalo de nuevo.',
      );
    }

    _validarSesionTenant(claims, empresaCodigo);

    return login;
  }

  /// Registro de una cuenta de paciente dentro de una clínica:
  ///
  /// `POST {ApiConfig.baseUrl}/seguridad/tenant/registro-paciente`
  ///
  /// Envía los datos del formulario más el `empresa_codigo` de la clínica
  /// elegida en el login. El backend resuelve la base tenant con ese código y
  /// crea la cuenta únicamente allí; la app nunca envía `tenant_id`,
  /// `database_name`, `rol_id` ni `usuario_id`.
  ///
  /// Devuelve un [RegistroPacienteResponse] cuando FastAPI responde 201. El
  /// endpoint legacy (`/seguridad/registro-paciente`) ya no se usa: no conoce
  /// las clínicas y podría crear la cuenta en la base equivocada.
  ///
  /// Los errores se traducen a [AuthException] con mensajes entendibles (ver
  /// `_mensajeErrorRegistro`). La contraseña nunca se escribe en logs.
  Future<RegistroPacienteResponse> registrarPaciente(
    RegistroPacienteRequest request,
  ) async {
    final String empresaCodigo = request.empresaCodigo.trim();

    // Sin clínica no se envía nada: la cuenta debe crearse en una clínica
    // concreta y el backend no puede adivinarla.
    if (empresaCodigo.isEmpty) {
      throw const AuthException(mensajeClinicaRequerida);
    }

    final Map<String, dynamic> cuerpo = request.toJson();
    cuerpo['empresa_codigo'] = empresaCodigo;

    final http.Response response = await _post(
      '/seguridad/tenant/registro-paciente',
      cuerpo,
    );

    if (response.statusCode == 201) {
      final Map<String, dynamic> body = _decodificarObjeto(response);
      return RegistroPacienteResponse.fromJson(body);
    }

    throw AuthException(_mensajeErrorRegistro(response));
  }

  /// Envía un GET a [ruta] usando [ApiConfig.baseUrl].
  Future<http.Response> _get(String ruta) {
    return _enviar(
      () => _client.get(
        Uri.parse('${ApiConfig.baseUrl}$ruta'),
        headers: const {'Accept': 'application/json'},
      ),
    );
  }

  /// Envía un POST con cuerpo JSON a [ruta] usando [ApiConfig.baseUrl].
  Future<http.Response> _post(String ruta, Map<String, dynamic> cuerpo) {
    return _enviar(
      () => _client.post(
        Uri.parse('${ApiConfig.baseUrl}$ruta'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(cuerpo),
      ),
    );
  }

  /// Ejecuta [peticion] con el tiempo máximo de espera configurado.
  ///
  /// Traduce los fallos de red/tiempo a [AuthException] con un mensaje
  /// entendible (nunca expone la contraseña ni el token).
  Future<http.Response> _enviar(
    Future<http.Response> Function() peticion,
  ) async {
    try {
      return await peticion().timeout(_timeout);
    } on TimeoutException {
      throw const AuthException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const AuthException(
        'No se pudo conectar con el servidor. '
        'Verifica que FastAPI esté en ejecución y vuelve a intentarlo.',
      );
    } on Exception {
      throw const AuthException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
      );
    }
  }

  /// Decodifica el cuerpo JSON de una respuesta como objeto.
  Map<String, dynamic> _decodificarObjeto(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);

      if (body is Map<String, dynamic>) {
        return body;
      }
    } on FormatException {
      // Se maneja abajo con un mensaje entendible.
    }

    throw const AuthException(
      'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
    );
  }

  /// Decodifica el payload de un JWT para comprobar el contrato tenant.
  ///
  /// Esto NO es una autorización: la firma, el rol y los permisos los valida
  /// FastAPI en cada endpoint. Aquí solo se descartan sesiones que la app
  /// móvil no debe usar (rol distinto de Paciente, token legacy o de otra
  /// clínica). Devuelve `null` cuando el token no tiene un payload JSON
  /// decodificable.
  Map<String, dynamic>? _claimsDelJwt(String accessToken) {
    try {
      final List<String> partes = accessToken.split('.');

      if (partes.length != 3) {
        return null;
      }

      final String payloadJson = utf8.decode(
        base64Url.decode(base64Url.normalize(partes[1])),
      );
      final Object? payload = jsonDecode(payloadJson);

      if (payload is Map<String, dynamic>) {
        return payload;
      }
    } on FormatException {
      // El payload no es base64/JSON válido: no se puede confirmar la sesión.
    } on ArgumentError {
      // Longitud base64 inválida: no se puede confirmar la sesión.
    }

    return null;
  }

  /// Comprueba que [claims] cumpla el contrato del JWT tenant.
  ///
  /// Lanza [AuthException] (con `sesionRechazada = true`) cuando:
  ///
  /// - `token_type` no es `tenant` (token legacy o de otro sistema),
  /// - `rol_nombre` falta o no es `Paciente`,
  /// - `empresa_codigo` falta o no coincide con la clínica elegida.
  ///
  /// No se deduce el rol de ningún otro claim: `rol_nombre` lo genera FastAPI
  /// a partir del rol real de la base PostgreSQL de la clínica.
  void _validarSesionTenant(Map<String, dynamic> claims, String empresaCodigo) {
    final Object? tokenType = claims['token_type'];

    if (tokenType is! String ||
        tokenType.trim().toLowerCase() != tokenTypeTenant) {
      throw const AuthException(mensajeSesionNoTenant, sesionRechazada: true);
    }

    final Object? rolNombre = claims['rol_nombre'];

    if (rolNombre is! String || rolNombre.trim().isEmpty) {
      throw const AuthException(
        mensajeRolNoIdentificado,
        sesionRechazada: true,
      );
    }

    if (!_esRolPaciente(rolNombre)) {
      throw const AuthException(
        mensajeSoloParaPacientes,
        sesionRechazada: true,
      );
    }

    final Object? empresa = claims['empresa_codigo'];

    if (empresa is! String || empresa.trim().isEmpty) {
      throw const AuthException(
        mensajeClinicaNoIdentificada,
        sesionRechazada: true,
      );
    }

    if (empresa.trim().toUpperCase() != empresaCodigo.toUpperCase()) {
      throw const AuthException(mensajeClinicaDistinta, sesionRechazada: true);
    }
  }

  /// Indica si el nombre de rol corresponde a un paciente.
  ///
  /// La comparación ignora mayúsculas y espacios sobrantes, pero exige que el
  /// valor sea exactamente `Paciente`: no se aceptan ids de rol ni otros
  /// roles.
  bool _esRolPaciente(String rolNombre) {
    return rolNombre.trim().toLowerCase() ==
        nombreRolPaciente.trim().toLowerCase();
  }

  /// Convierte un error HTTP de FastAPI en un mensaje entendible.
  ///
  /// Cuando FastAPI incluye `detail`, se prefiere ese mensaje.
  String _mensajeError(http.Response response) {
    final String? detalle = _detalleDeRespuesta(response);

    if (detalle != null) {
      return detalle;
    }

    if (response.statusCode == 401) {
      return 'Correo o contraseña incorrectos';
    }

    if (response.statusCode == 403) {
      return 'No tienes permisos para iniciar sesión en esta clínica';
    }

    if (response.statusCode == 422) {
      return 'Revisa los datos ingresados: no tienen el formato esperado.';
    }

    if (response.statusCode == 503) {
      return 'La clínica no está disponible en este momento. '
          'Inténtalo más tarde.';
    }

    return 'No se pudo completar la solicitud '
        '(código ${response.statusCode}). Inténtalo de nuevo.';
  }

  /// Extrae el mensaje `detail` de una respuesta de FastAPI, si lo hay.
  ///
  /// Devuelve el texto de `detail` cuando es un string, o une los `msg` de los
  /// errores de validación 422. Devuelve `null` si el cuerpo no es JSON o no
  /// trae `detail`.
  String? _detalleDeRespuesta(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);

      if (body is Map<String, dynamic> && body['detail'] != null) {
        final Object? detail = body['detail'];

        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }

        // Errores de validación 422 de FastAPI llegan como lista de objetos.
        if (detail is List && detail.isNotEmpty) {
          final mensajes = <String>[
            for (final item in detail)
              if (item is Map<String, dynamic> && item['msg'] is String)
                item['msg'] as String,
          ];

          if (mensajes.isNotEmpty) {
            return mensajes.map(_limpiarMensajeValidacion).join('\n');
          }
        }
      }
    } on FormatException {
      // El cuerpo no es JSON: no hay detalle que mostrar.
    }

    return null;
  }

  /// Convierte un error del registro tenant en un mensaje entendible.
  ///
  /// El 409 puede significar varias cosas (correo duplicado, paciente que ya
  /// existe en la clínica o un conflicto concurrente). Para no afirmar algo
  /// incorrecto se usa el detalle del backend; solo cuando ese detalle indica
  /// que el paciente ya existe se muestra [mensajePacienteExistente], que pide
  /// verificar la identidad en la clínica.
  String _mensajeErrorRegistro(http.Response response) {
    final String? detalle = _detalleDeRespuesta(response);

    switch (response.statusCode) {
      case 409:
        if (detalle == null) {
          return mensajeConflictoRegistro;
        }

        return _esRegistroPacienteExistente(detalle)
            ? mensajePacienteExistente
            : detalle;
      case 403:
        return detalle ?? mensajeClinicaSinSuscripcion;
      case 404:
        return detalle ?? mensajeClinicaNoDisponible;
      case 422:
        return detalle ??
            'Revisa los datos ingresados: no tienen el formato esperado.';
      case 503:
        return detalle ??
            'La clínica no está disponible en este momento. '
                'Inténtalo más tarde.';
      default:
        return detalle ??
            'No se pudo crear la cuenta '
                '(código ${response.statusCode}). Inténtalo de nuevo.';
    }
  }

  /// Indica si el detalle de un 409 describe un paciente que ya existe en la
  /// clínica.
  ///
  /// Se exige que el mensaje hable de algo que ya existe Y de un paciente,
  /// identidad o expediente; así no se muestra el aviso de verificación
  /// presencial ante otros conflictos (por ejemplo, un correo duplicado).
  bool _esRegistroPacienteExistente(String detalle) {
    final String texto = detalle.toLowerCase();

    final bool yaExiste =
        texto.contains('ya existe') ||
        texto.contains('ya está') ||
        texto.contains('ya esta') ||
        texto.contains('existente');

    final bool hablaDePaciente =
        texto.contains('paciente') ||
        texto.contains('identidad') ||
        texto.contains('expediente') ||
        texto.contains('vincul');

    return yaExiste && hablaDePaciente;
  }

  /// Mensaje para los errores al listar clínicas.
  ///
  /// El listado es público (no requiere credenciales), por lo que 401/403 se
  /// tratan como un fallo del servicio y no como credenciales inválidas.
  String _mensajeErrorListado(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'No se pudieron obtener las clínicas disponibles. '
          'Inténtalo de nuevo.';
    }

    if (response.statusCode == 503) {
      return 'El servicio de clínicas no está disponible en este momento. '
          'Inténtalo más tarde.';
    }

    return _mensajeError(response);
  }

  /// Quita el prefijo "Value error, " de los mensajes de validación de Pydantic.
  String _limpiarMensajeValidacion(String mensaje) {
    const prefijo = 'Value error, ';
    if (mensaje.startsWith(prefijo)) {
      return mensaje.substring(prefijo.length);
    }

    return mensaje;
  }
}
