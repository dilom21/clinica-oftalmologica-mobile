import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/analitica_models.dart';

class AnaliticaException implements Exception {
  const AnaliticaException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get sesionExpirada => statusCode == 401;
  bool get accesoDenegado => statusCode == 403;
  @override
  String toString() => message;
}

class ArchivoExportado {
  const ArchivoExportado({
    required this.bytes,
    required this.nombre,
    required this.mime,
  });
  final Uint8List bytes;
  final String nombre;
  final String mime;
}

class AnaliticaService {
  AnaliticaService({http.Client? client, Future<String?> Function()? leerToken})
    : _client = client ?? http.Client(),
      _leerToken = leerToken ?? (() => TokenStorage().getToken());
  final http.Client _client;
  final Future<String?> Function() _leerToken;
  static const _timeout = Duration(seconds: 20);

  Future<CatalogoProgresivo> catalogo() async => CatalogoProgresivo.fromJson(
    await _getJson('/reportes/progresivos/catalogo'),
  );
  Future<RespuestaKpis> kpis(FiltrosProgresivos filtros) async =>
      RespuestaKpis.fromJson(
        await _getJson('/reportes/progresivos/kpis', filtros.toQuery()),
      );
  Future<RespuestaSerie> serie(
    String indicador,
    FiltrosProgresivos filtros,
  ) async => RespuestaSerie.fromJson(
    await _getJson(
      '/reportes/progresivos/series/${Uri.encodeComponent(indicador)}',
      filtros.toQuery(),
    ),
  );
  Future<RespuestaComparacion> comparacion(
    String indicador,
    FiltrosProgresivos filtros,
  ) async => RespuestaComparacion.fromJson(
    await _getJson(
      '/reportes/progresivos/comparaciones/${Uri.encodeComponent(indicador)}',
      filtros.toQuery(),
    ),
  );

  Future<PronosticoDemanda> pronostico({
    required int horizonte,
    DateTime? fechaCorte,
  }) async {
    if (horizonte < 4 || horizonte > 12) {
      throw const FormatException(
        'El horizonte debe estar entre 4 y 12 semanas.',
      );
    }
    return PronosticoDemanda.fromJson(
      await _getJson('/ia-predictiva/demanda/semanal', <String, String>{
        'horizonte': '$horizonte',
        if (fechaCorte != null) 'fecha_corte': fechaCorte.toIso8601String(),
      }),
    );
  }

  Future<EstadoModeloInasistencia> estadoInasistencia() async =>
      EstadoModeloInasistencia.fromJson(
        await _getJson('/ia-predictiva/inasistencia/estado'),
      );

  Future<ArchivoExportado> exportar(
    String formato,
    String indicador,
    FiltrosProgresivos filtros,
  ) async {
    if (!const {'csv', 'xlsx', 'pdf'}.contains(formato)) {
      throw const FormatException('Formato de exportación inválido.');
    }
    final response = await _request(
      'POST',
      '/reportes/progresivos/exportar/$formato',
      body: filtros.toJson(indicador: indicador),
      accept: '*/*',
    );
    _validar(response);
    return ArchivoExportado(
      bytes: response.bodyBytes,
      nombre: _nombre(response, '$indicador.$formato'),
      mime: response.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _request('GET', path, query: query);
    _validar(response);
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
    } on FormatException {
      /* traducido abajo */
    }
    throw const AnaliticaException(
      'El servidor devolvió una respuesta inesperada.',
    );
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    String accept = 'application/json',
  }) async {
    final token = await _leerToken();
    if (token == null || token.isEmpty) {
      throw const AnaliticaException(
        'La sesión administrativa no es válida.',
        statusCode: 401,
      );
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}$path')
        .replace(queryParameters: query);
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': accept,
      if (body != null) 'Content-Type': 'application/json',
    };
    try {
      final future = method == 'POST'
          ? _client.post(uri, headers: headers, body: jsonEncode(body))
          : _client.get(uri, headers: headers);
      return await future.timeout(_timeout);
    } on TimeoutException {
      throw const AnaliticaException(
        'El servidor tardó demasiado en responder.',
      );
    } on http.ClientException {
      throw const AnaliticaException('No se pudo conectar con el servidor.');
    }
  }

  void _validar(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String? detail;
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['detail'] is String) {
        detail = body['detail'] as String;
      }
    } on FormatException {
      /* usa mensaje controlado */
    }
    final message =
        detail ??
        switch (response.statusCode) {
          401 => 'La sesión expiró. Vuelve a iniciar sesión.',
          403 => 'Acceso denegado: se requiere rol administrador y permiso Generar reportes.',
          422 => 'Los filtros enviados no son válidos.',
          429 => 'Hay demasiadas solicitudes. Inténtalo más tarde.',
          _ =>
            'No se pudo completar la solicitud (código ${response.statusCode}).',
        };
    throw AnaliticaException(message, statusCode: response.statusCode);
  }

  String _nombre(http.Response response, String fallback) {
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp(
      r'''filename\*?=(?:UTF-8''|"?)([^";]+)''',
      caseSensitive: false,
    ).firstMatch(disposition);
    return Uri.decodeComponent(
      match?.group(1)?.trim().replaceAll('"', '') ?? fallback,
    );
  }
}
