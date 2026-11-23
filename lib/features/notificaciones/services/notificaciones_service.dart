import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/notificacion_models.dart';

class NotificacionesException implements Exception {
  const NotificacionesException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class NotificacionesService {
  NotificacionesService({http.Client? client, TokenStorage? tokenStorage})
    : _client = client ?? http.Client(),
      _tokenStorage = tokenStorage ?? TokenStorage();

  final http.Client _client;
  final TokenStorage _tokenStorage;
  static const _timeout = Duration(seconds: 20);

  Future<DispositivoPush> registrarDispositivo({
    required String tokenFcm,
    required String plataforma,
    String? instalacionId,
    String? appVersion,
    String? nombreDispositivo,
  }) async {
    final token = tokenFcm.trim();
    if (token.isEmpty) {
      throw const NotificacionesException(
        'Firebase no entregó un token válido.',
      );
    }
    final body = <String, Object?>{
      'token_fcm': token,
      'plataforma': plataforma,
      'instalacion_id': ?instalacionId,
      'app_version': ?appVersion,
      'nombre_dispositivo': ?nombreDispositivo,
    };
    final response = await _request(
      'POST',
      '/notificaciones/dispositivos',
      body: body,
    );
    return DispositivoPush.fromJson(_map(response));
  }

  Future<void> revocarDispositivo(int dispositivoId) async {
    await _request(
      'DELETE',
      '/notificaciones/dispositivos/$dispositivoId',
      expected: 204,
    );
  }

  Future<BandejaNotificaciones> listar({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _request(
      'GET',
      '/notificaciones?page=$page&page_size=$pageSize',
    );
    return BandejaNotificaciones.fromJson(_map(response));
  }

  Future<void> marcarLeida(int notificacionId) async {
    await _request('PATCH', '/notificaciones/$notificacionId/leida');
  }

  Future<PreferenciasNotificacion> obtenerPreferencias() async {
    final response = await _request('GET', '/notificaciones/preferencias');
    return PreferenciasNotificacion.fromJson(_map(response));
  }

  Future<PreferenciasNotificacion> actualizarPreferencias(
    Map<String, bool> cambios,
  ) async {
    final response = await _request(
      'PUT',
      '/notificaciones/preferencias',
      body: cambios,
    );
    return PreferenciasNotificacion.fromJson(_map(response));
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    int expected = 200,
  }) async {
    final jwt = await _tokenStorage.getToken();
    if (jwt == null || jwt.isEmpty) {
      throw const NotificacionesException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }
    final request = http.Request(method, Uri.parse('${ApiConfig.baseUrl}$path'))
      ..headers.addAll({
        'Authorization': 'Bearer $jwt',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != expected) throw _error(response);
      return response;
    } on NotificacionesException {
      rethrow;
    } on TimeoutException {
      throw const NotificacionesException(
        'El servidor tardó demasiado en responder.',
      );
    } on http.ClientException {
      throw const NotificacionesException(
        'No se pudo conectar con el servidor.',
      );
    }
  }

  Map<String, dynamic> _map(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Se transforma en un error seguro debajo.
    }
    throw const NotificacionesException(
      'El servidor devolvió una respuesta inesperada.',
    );
  }

  NotificacionesException _error(http.Response response) {
    String? detail;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        detail = (decoded['detail'] as String).trim();
      }
    } on FormatException {
      // Nunca se refleja el request ni los tokens.
    }
    return NotificacionesException(
      detail?.isNotEmpty == true
          ? detail!
          : 'No se pudo completar la operación.',
      statusCode: response.statusCode,
    );
  }
}
