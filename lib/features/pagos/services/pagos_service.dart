import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/pago_models.dart';

/// Excepción lanzada cuando falla una petición del módulo Pagos.
class PagosException implements Exception {
  const PagosException(this.message, {this.statusCode});

  /// Mensaje entendible para mostrar al usuario.
  final String message;

  /// Código HTTP cuando el backend respondió (ej. 401, 403, 409, 502).
  final int? statusCode;

  @override
  String toString() => message;
}

/// Comprobante PDF devuelto por el backend.
///
/// El PDF se recibe como bytes binarios (`application/pdf`). NUNCA se
/// reconstruye ni se recalcula en la app: FastAPI es la única fuente del
/// comprobante.
class ComprobantePago {
  const ComprobantePago({
    required this.bytes,
    required this.nombreArchivo,
    required this.contentType,
  });

  /// Contenido binario del PDF.
  final Uint8List bytes;

  /// Nombre de archivo sugerido por el backend.
  final String nombreArchivo;

  /// Tipo MIME informado por el backend.
  final String contentType;

  /// Tamaño del comprobante en bytes.
  int get tamanoBytes => bytes.length;

  /// Indica si el contenido recibido es realmente un PDF.
  ///
  /// Se acepta por `Content-Type` o por la firma `%PDF` del archivo, de forma
  /// que una respuesta 200 con contenido inválido se detecte igualmente.
  bool get esPdf {
    if (contentType.toLowerCase().contains('pdf')) return true;

    return bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }
}

/// Servicio del módulo Pagos (ETAPA 7 + ETAPA 8.2).
///
/// Toda la comunicación HTTP con FastAPI vive aquí; las páginas nunca llaman
/// HTTP directo. Reutiliza el JWT del paciente autenticado ([TokenStorage]) y
/// NUNCA envía `paciente_id`: el backend lo deduce del token.
///
/// Endpoints consumidos:
/// - `GET  /pagos/mis-consultas`
/// - `GET  /pagos/mis-consultas/{consulta_id}/servicios`
/// - `POST /pagos/stripe/intencion`
/// - `GET  /pagos/stripe/pagos/{pago_id}/estado`
/// - `GET  /pagos/mis-pagos`                          (historial)
/// - `GET  /pagos/mis-pagos/{pago_id}/comprobante`    (PDF binario)
class PagosService {
  PagosService({http.Client? client, Future<String?> Function()? leerToken})
    : _client = client ?? http.Client(),
      _leerToken = leerToken ?? (() => TokenStorage().getToken());

  final http.Client _client;

  /// Fuente del JWT (por defecto [TokenStorage], inyectable en pruebas).
  final Future<String?> Function() _leerToken;

  /// Tiempo máximo de espera para una respuesta del servidor.
  static const Duration _timeout = Duration(seconds: 20);

  /// Lista las consultas clínicas del paciente con su resumen de pagos.
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/mis-consultas`
  Future<List<ConsultaPago>> listarMisConsultas() async {
    final http.Response response = await _get('/pagos/mis-consultas');

    if (response.statusCode == 200) {
      return _lista(response, (json) => ConsultaPago.fromJson(json));
    }

    throw PagosException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Lista los servicios realizados de una consulta con su estado de pago.
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/mis-consultas/{consultaId}/servicios`
  Future<List<ServicioRealizadoPago>> listarServiciosDeConsulta(
    int consultaId,
  ) async {
    final http.Response response = await _get(
      '/pagos/mis-consultas/$consultaId/servicios',
    );

    if (response.statusCode == 200) {
      return _lista(response, (json) => ServicioRealizadoPago.fromJson(json));
    }

    throw PagosException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Crea o reutiliza un PaymentIntent de Stripe para los servicios elegidos.
  ///
  /// `POST {ApiConfig.baseUrl}/pagos/stripe/intencion` con
  /// `{ "servicio_realizado_ids": [...] }`. El backend calcula el monto y
  /// aplica sus protecciones anti-doble cobro. Un HTTP 409 significa que NO
  /// debe reintentarse automáticamente.
  Future<PagoIntencion> crearIntencion(List<int> servicioRealizadoIds) async {
    final http.Response response = await _post(
      '/pagos/stripe/intencion',
      <String, dynamic>{'servicio_realizado_ids': servicioRealizadoIds},
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final Map<String, dynamic> body = _objeto(response);
      try {
        return PagoIntencion.fromJson(body);
      } on TypeError {
        throw const PagosException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PagosException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Consulta el estado REAL del pago en el backend (fuente de verdad).
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/stripe/pagos/{pagoId}/estado`
  Future<EstadoPago> consultarEstado(int pagoId) async {
    final http.Response response = await _get(
      '/pagos/stripe/pagos/$pagoId/estado',
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = _objeto(response);
      try {
        return EstadoPago.fromJson(body);
      } on TypeError {
        throw const PagosException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PagosException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Lista el historial de pagos del paciente (más recientes primero).
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/mis-pagos`. Operación de SOLO LECTURA: no
  /// crea intenciones de pago ni modifica ningún pago.
  Future<List<PagoHistorial>> listarMisPagos() async {
    final http.Response response = await _get('/pagos/mis-pagos');

    if (response.statusCode == 200) {
      return ordenarHistorialPorFechaDesc(
        _lista(response, (json) => PagoHistorial.fromJson(json)),
      );
    }

    throw PagosException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Descarga el comprobante PDF de un pago aprobado del paciente.
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/mis-pagos/{pagoId}/comprobante`.
  ///
  /// Devuelve los bytes binarios tal como los genera FastAPI (el PDF NO se
  /// reconstruye en la app). Es de SOLO LECTURA: no vuelve a cobrar ni vuelve a
  /// confirmar un PaymentIntent.
  ///
  /// Errores manejados: 401 (sesión), 404 (pago inexistente o de otro paciente)
  /// y 409 (pago propio todavía NO aprobado).
  Future<ComprobantePago> descargarComprobante(int pagoId) async {
    final http.Response response = await _get(
      '/pagos/mis-pagos/$pagoId/comprobante',
      accept: 'application/pdf',
    );

    if (response.statusCode == 200) {
      final ComprobantePago comprobante = ComprobantePago(
        bytes: response.bodyBytes,
        nombreArchivo: _nombreArchivoComprobante(response, pagoId),
        contentType: response.headers['content-type'] ?? '',
      );

      if (!comprobante.esPdf) {
        throw const PagosException(
          'El comprobante recibido no tiene un formato PDF válido.',
        );
      }

      return comprobante;
    }

    throw PagosException(
      _mensajeErrorComprobante(response),
      statusCode: response.statusCode,
    );
  }

  /// Nombre de archivo del comprobante: usa el `Content-Disposition` del
  /// backend y, si no es válido, el estándar `comprobante_pago_{id}.pdf`.
  String _nombreArchivoComprobante(http.Response response, int pagoId) {
    final String? disposition = response.headers['content-disposition'];

    if (disposition != null) {
      final RegExpMatch? coincidencia = RegExp(r'filename="?([^";]+)"?')
          .firstMatch(disposition);
      final String? nombre = coincidencia?.group(1)?.trim();

      if (nombre != null && nombre.toLowerCase().endsWith('.pdf')) {
        return nombre;
      }
    }

    return 'comprobante_pago_$pagoId.pdf';
  }

  /// Mensaje de error específico del comprobante (404 y 409 propios).
  String _mensajeErrorComprobante(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 403:
        return 'No tienes permisos para descargar este comprobante.';
      case 404:
        return 'El comprobante no está disponible para este pago.';
      case 409:
        return _detalleBackend(response) ??
            'El comprobante solo está disponible para pagos aprobados.';
      default:
        return _mensajeError(response);
    }
  }

  /// Extrae el campo `detail` (texto) del JSON de error del backend, si existe.
  String? _detalleBackend(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);

      if (body is Map<String, dynamic>) {
        final Object? detail = body['detail'];

        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } on FormatException {
      // El cuerpo no es JSON.
    }

    return null;
  }

  /// Decodifica una lista JSON y mapea cada elemento.
  List<T> _lista<T>(
    http.Response response,
    T Function(Map<String, dynamic>) mapear,
  ) {
    try {
      final Object? body = jsonDecode(response.body);

      if (body is! List) {
        throw const FormatException('Cuerpo de respuesta inesperado');
      }

      return [
        for (final item in body)
          if (item is Map<String, dynamic>) mapear(item),
      ];
    } on FormatException {
      throw const PagosException(
        'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
      );
    } on TypeError {
      throw const PagosException(
        'La respuesta del servidor no tiene el formato esperado.',
      );
    }
  }

  /// Decodifica un objeto JSON de la respuesta.
  Map<String, dynamic> _objeto(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);

      if (body is Map<String, dynamic>) {
        return body;
      }
    } on FormatException {
      // Se maneja abajo con un mensaje entendible.
    }

    throw const PagosException(
      'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
    );
  }

  /// GET autenticado con JWT Bearer contra [ruta].
  ///
  /// [accept] permite solicitar contenido binario (p. ej. `application/pdf`).
  Future<http.Response> _get(
    String ruta, {
    String accept = 'application/json',
  }) async {
    final String token = await _token();
    final Uri uri = Uri.parse('${ApiConfig.baseUrl}$ruta');

    try {
      return await _client
          .get(uri, headers: _headers(token, accept: accept))
          .timeout(_timeout);
    } on TimeoutException {
      throw const PagosException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const PagosException(
        'No se pudo conectar con el servidor. '
        'Verifica tu conexión e inténtalo de nuevo.',
      );
    } on Exception {
      throw const PagosException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
      );
    }
  }

  /// POST autenticado con JWT Bearer y cuerpo JSON contra [ruta].
  Future<http.Response> _post(String ruta, Map<String, dynamic> cuerpo) async {
    final String token = await _token();
    final Uri uri = Uri.parse('${ApiConfig.baseUrl}$ruta');

    try {
      return await _client
          .post(
            uri,
            headers: _headers(token, json: true),
            body: jsonEncode(cuerpo),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const PagosException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const PagosException(
        'No se pudo conectar con el servidor. '
        'Verifica tu conexión e inténtalo de nuevo.',
      );
    } on Exception {
      throw const PagosException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
      );
    }
  }

  /// Lee el JWT o lanza 401 si no hay sesión.
  Future<String> _token() async {
    final String? token = await _leerToken();

    if (token == null || token.isEmpty) {
      throw const PagosException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }

    return token;
  }

  /// Cabeceras comunes de las peticiones autenticadas.
  Map<String, String> _headers(
    String token, {
    bool json = false,
    String accept = 'application/json',
  }) => {
    'Authorization': 'Bearer $token',
    'Accept': accept,
    if (json) 'Content-Type': 'application/json',
  };

  /// Convierte el error HTTP de FastAPI en un mensaje entendible.
  String _mensajeError(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);

      if (body is Map<String, dynamic> && body['detail'] != null) {
        final Object? detail = body['detail'];

        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }

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

    switch (response.statusCode) {
      case 401:
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 403:
        return 'No tienes permisos para realizar esta operación.';
      case 404:
        return 'No se encontró la información solicitada.';
      case 409:
        return 'Ya existe un pago en curso para los servicios seleccionados. '
            'Verifica el estado antes de intentarlo de nuevo.';
      case 422:
        return 'Los datos enviados no son válidos.';
      case 500:
        return 'Ocurrió un error en el servidor. Inténtalo más tarde.';
      case 502:
        return 'La pasarela de pagos no respondió. Inténtalo más tarde.';
      default:
        return 'No se pudo completar la solicitud '
            '(código ${response.statusCode}). Inténtalo de nuevo.';
    }
  }

  /// Quita el prefijo "Value error, " de los mensajes de validación.
  String _limpiarMensajeValidacion(String mensaje) {
    const prefijo = 'Value error, ';
    if (mensaje.startsWith(prefijo)) {
      return mensaje.substring(prefijo.length);
    }
    return mensaje;
  }
}
