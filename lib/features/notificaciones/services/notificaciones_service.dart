import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/notificacion.dart';

class NotificacionesException implements Exception {
  const NotificacionesException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class SesionCambiadaException implements Exception {
  const SesionCambiadaException();
}

class NotificacionesService {
  NotificacionesService({
    http.Client? client,
    Future<String?> Function()? leerToken,
  }) : _client = client ?? http.Client(),
       _leerToken = leerToken ?? (() => TokenStorage().getToken());

  final http.Client _client;
  final Future<String?> Function() _leerToken;
  static const Duration _timeout = Duration(seconds: 20);

  Future<PaginaNotificaciones> listar({
    int limite = 20,
    int desplazamiento = 0,
  }) async {
    final response = await _enviar(
      'GET',
      '/notificaciones/?limite=$limite&desplazamiento=$desplazamiento',
    );
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) throw const FormatException();
      return PaginaNotificaciones.fromJson(body);
    } on FormatException {
      throw const NotificacionesException(
        'La respuesta del servidor no es válida.',
      );
    } on TypeError {
      throw const NotificacionesException(
        'La respuesta del servidor no es válida.',
      );
    }
  }

  Future<Notificacion> marcarLeida(int id) async {
    final response = await _enviar('PATCH', '/notificaciones/$id/leida');
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) throw const FormatException();
      return Notificacion.fromJson(body);
    } on FormatException {
      throw const NotificacionesException(
        'La respuesta del servidor no es válida.',
      );
    } on TypeError {
      throw const NotificacionesException(
        'La respuesta del servidor no es válida.',
      );
    }
  }

  Future<http.Response> _enviar(String metodo, String ruta) async {
    final token = await _leerToken();
    if (token == null || token.isEmpty) {
      throw const NotificacionesException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
        statusCode: 401,
      );
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}$ruta');
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
    try {
      final response =
          await (metodo == 'PATCH'
                  ? _client.patch(uri, headers: headers)
                  : _client.get(uri, headers: headers))
              .timeout(_timeout);
      if (await _leerToken() != token) throw const SesionCambiadaException();
      if (response.statusCode == 401) {
        throw const NotificacionesException(
          'Tu sesión expiró. Inicia sesión nuevamente.',
          statusCode: 401,
        );
      }
      if (response.statusCode != 200) {
        throw NotificacionesException(
          'No se pudieron cargar las notificaciones. Inténtalo de nuevo.',
          statusCode: response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      throw const NotificacionesException(
        'El servidor tardó demasiado. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const NotificacionesException(
        'Sin conexión. Comprueba tu red e inténtalo de nuevo.',
      );
    }
  }
}
