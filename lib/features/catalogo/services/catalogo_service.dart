import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/servicio_catalogo.dart';

class CatalogoException implements Exception {
  const CatalogoException(this.mensaje, {this.statusCode});
  final String mensaje;
  final int? statusCode;
  @override
  String toString() => mensaje;
}

// Cada petición obtiene el JWT actual; no se envía empresa_id ni hay caché global.
class CatalogoService {
  CatalogoService({http.Client? client, Future<String?> Function()? leerToken})
    : _client = client ?? http.Client(),
      _propio = client == null,
      _leerToken = leerToken ?? (() => TokenStorage().getToken());
  final http.Client _client;
  final bool _propio;
  final Future<String?> Function() _leerToken;
  void dispose() {
    if (_propio) _client.close();
  }

  Future<Object?> _get(String ruta, [Map<String, String>? query]) async {
    final token = await _leerToken();
    if (token == null || token.trim().isEmpty) {
      throw const CatalogoException(
        'Tu sesión no es válida. Inicia sesión nuevamente.',
        statusCode: 401,
      );
    }
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/servicios-oftalmologicos/catalogo/$ruta',
    ).replace(queryParameters: query);
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
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const CatalogoException(
        'El servidor tardó demasiado. Inténtalo nuevamente.',
      );
    } on http.ClientException {
      throw const CatalogoException(
        'No se pudo conectar. Revisa tu conexión e inténtalo nuevamente.',
      );
    }
    if (response.statusCode != 200) {
      final mensaje = switch (response.statusCode) {
        401 => 'Tu sesión expiró. Inicia sesión nuevamente.',
        403 => 'No tienes autorización para consultar el catálogo.',
        404 => 'Este servicio ya no está disponible.',
        _ => 'No se pudo consultar el catálogo. Inténtalo nuevamente.',
      };
      throw CatalogoException(mensaje, statusCode: response.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const CatalogoException('La respuesta del servidor no es válida.');
    }
  }

  Future<List<ServicioCatalogo>> listar({
    String busqueda = '',
    int offset = 0,
    int limite = 20,
  }) async {
    final body = await _get('', {
      'busqueda': busqueda.trim(),
      'offset': '$offset',
      'limite': '$limite',
    });
    try {
      return (body as List)
          .map((e) => ServicioCatalogo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object {
      throw const CatalogoException(
        'El catálogo recibido no tiene el formato esperado.',
      );
    }
  }

  Future<ServicioCatalogo> detalle(int id) async {
    final body = await _get('$id');
    try {
      return ServicioCatalogo.fromJson(body as Map<String, dynamic>);
    } on Object {
      throw const CatalogoException(
        'El detalle recibido no tiene el formato esperado.',
      );
    }
  }
}
