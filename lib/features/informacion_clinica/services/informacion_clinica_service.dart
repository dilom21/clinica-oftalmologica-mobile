import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/informacion_clinica_models.dart';

/// Error de la consulta de información clínica autorizada (CU25).
class InformacionClinicaException implements Exception {
  const InformacionClinicaException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Consume `GET /historial-clinico/mi-informacion`.
///
/// No envía `paciente_id`: el backend identifica al paciente con el JWT.
class InformacionClinicaService {
  InformacionClinicaService({
    http.Client? client,
    Future<String?> Function()? leerToken,
  }) : _client = client ?? http.Client(),
       _leerToken = leerToken ?? (() => TokenStorage().getToken());

  final http.Client _client;
  final Future<String?> Function() _leerToken;

  static const Duration _timeout = Duration(seconds: 20);

  /// Información clínica vigente del paciente autenticado.
  Future<InformacionClinicaAutorizada> consultar() async {
    final String token = await _token();
    final Uri uri = Uri.parse(
      '${ApiConfig.baseUrl}/historial-clinico/mi-informacion',
    );

    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const InformacionClinicaException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const InformacionClinicaException(
        'No se pudo conectar con el servidor. '
        'Verifica tu conexión e inténtalo de nuevo.',
      );
    } on Exception {
      throw const InformacionClinicaException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
      );
    }

    if (response.statusCode == 200) {
      try {
        final Object? body = jsonDecode(response.body);
        if (body is! Map<String, dynamic>) {
          throw const FormatException('Cuerpo de respuesta inesperado');
        }
        return InformacionClinicaAutorizada.fromJson(body);
      } on FormatException {
        throw const InformacionClinicaException(
          'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
        );
      } on TypeError {
        throw const InformacionClinicaException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw InformacionClinicaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  Future<String> _token() async {
    final String? token = await _leerToken();
    if (token == null || token.isEmpty) {
      throw const InformacionClinicaException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }
    return token;
  }

  String _mensajeError(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final Object? detail = body['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } on FormatException {
      // Se usa el mensaje genérico.
    }

    switch (response.statusCode) {
      case 401:
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 403:
        return 'No tienes autorización para consultar esta información clínica.';
      case 404:
        return 'No se encontró tu información clínica.';
      default:
        return 'No se pudo consultar tu información clínica. Inténtalo de nuevo.';
    }
  }
}
