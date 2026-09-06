import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/auth_models.dart';

/// Excepción lanzada cuando una petición de autenticación falla.
///
/// Contiene un [message] entendible para mostrarse al usuario.
class AuthException implements Exception {
  const AuthException(this.message);

  /// Mensaje legible que describe el error ocurrido.
  final String message;

  @override
  String toString() => message;
}

/// Servicio de autenticación de la aplicación móvil (exclusiva de pacientes).
///
/// Toda la comunicación HTTP vive aquí; las páginas nunca llaman HTTP directo.
class AuthService {
  AuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Tiempo máximo de espera para una respuesta del servidor.
  static const Duration _timeout = Duration(seconds: 20);

  /// Rol "Paciente" asignado por el backend en el JWT (`rol_id = 4`).
  ///
  /// La app móvil solo acepta sesiones cuyo token traiga este rol.
  static const int rolPaciente = 4;

  /// Mensaje que se muestra cuando quien se autentica no es un paciente.
  static const String mensajeSoloParaPacientes =
      'Esta aplicación móvil está disponible únicamente para pacientes.';

  /// Inicio de sesión contra el endpoint general del backend:
  ///
  /// `POST {ApiConfig.baseUrl}/seguridad/login`
  ///
  /// Como la app móvil es exclusiva de pacientes, se acepta la sesión
  /// únicamente si el payload del JWT devuelto trae `rol_id == 4`.
  ///
  /// Devuelve un [LoginResponse] solo cuando FastAPI responde 200 y el
  /// usuario autenticado es un paciente. En cualquier otro caso lanza
  /// [AuthException] y NO se devuelve token alguno.
  Future<LoginResponse> loginPaciente(LoginRequest request) async {
    final http.Response response = await _post(
      '/seguridad/login',
      request.toJson(),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = _decodificarObjeto(response);

      final LoginResponse login;
      try {
        login = LoginResponse.fromJson(body);
      } on TypeError {
        throw const AuthException(
          'La respuesta del servidor no contiene el access_token esperado.',
        );
      }

      final int? rolId = _rolIdDelJwt(login.accessToken);

      if (rolId == rolPaciente) {
        return login;
      }

      if (rolId == null) {
        throw const AuthException(
          'No se pudo verificar la sesión. Inténtalo de nuevo.',
        );
      }

      throw const AuthException(mensajeSoloParaPacientes);
    }

    throw AuthException(_mensajeError(response));
  }

  /// Registro de una cuenta de paciente desde la app móvil:
  ///
  /// `POST {ApiConfig.baseUrl}/seguridad/registro-paciente`
  ///
  /// Devuelve un [RegistroPacienteResponse] si FastAPI responde 201.
  Future<RegistroPacienteResponse> registrarPaciente(
    RegistroPacienteRequest request,
  ) async {
    final http.Response response = await _post(
      '/seguridad/registro-paciente',
      request.toJson(),
    );

    if (response.statusCode == 201) {
      final Map<String, dynamic> body = _decodificarObjeto(response);
      return RegistroPacienteResponse.fromJson(body);
    }

    throw AuthException(_mensajeError(response));
  }

  /// Envía un POST con cuerpo JSON a [ruta] usando [ApiConfig.baseUrl].
  Future<http.Response> _post(String ruta, Map<String, dynamic> cuerpo) async {
    try {
      return await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}$ruta'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(cuerpo),
          )
          .timeout(_timeout);
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

  /// Lee el claim `rol_id` del payload de un JWT.
  ///
  /// No se valida la firma aquí (el token llega del propio backend por
  /// HTTPS); solo se inspecciona el payload para decidir si el rol
  /// autenticado puede usar la app móvil. Devuelve `null` cuando el token
  /// no tiene un payload JSON decodificable o no expone `rol_id`.
  int? _rolIdDelJwt(String accessToken) {
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
        final Object? rolId = payload['rol_id'];

        if (rolId is int) {
          return rolId;
        }

        if (rolId is num) {
          return rolId.toInt();
        }
      }
    } on FormatException {
      // El payload no es base64/JSON válido: no se puede confirmar el rol.
    } on ArgumentError {
      // Longitud base64 inválida: no se puede confirmar el rol.
    }

    return null;
  }

  /// Convierte un error HTTP de FastAPI en un mensaje entendible.
  ///
  /// Cuando FastAPI incluye `detail`, se prefiere ese mensaje.
  String _mensajeError(http.Response response) {
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
      // El cuerpo no es JSON: se usa el mensaje genérico de abajo.
    }

    if (response.statusCode == 401) {
      return 'Correo o contraseña incorrectos';
    }

    if (response.statusCode == 403) {
      return 'No tienes permisos para realizar esta acción';
    }

    return 'No se pudo completar la solicitud '
        '(código ${response.statusCode}). Inténtalo de nuevo.';
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
