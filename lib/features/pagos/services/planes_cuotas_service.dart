import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/pago_models.dart';
import '../models/planes_cuotas_models.dart';
import 'pagos_service.dart';

/// Servicio de CU32 (consultar planes de pago) y CU33 (consultar y pagar
/// cuotas) del paciente autenticado.
///
/// Toda la comunicación HTTP vive aquí; las páginas nunca llaman HTTP directo.
/// Reutiliza el JWT del paciente ([TokenStorage]) y NUNCA envía `paciente_id`:
/// el backend lo deduce del token (identificación multitenant).
///
/// Endpoints consumidos (los reales de FastAPI, sin inventar rutas):
/// - `GET  /pagos/mis-planes`
/// - `GET  /pagos/mis-planes/{plan_id}`
/// - `POST /pagos/cuotas/{cuota_id}/stripe/intencion`
/// - `GET  /pagos/stripe/pagos/{pago_id}/estado`  (delegado a [PagosService])
/// - `GET  /pagos/cuotas/{cuota_id}/intentos`
///
/// Las reglas financieras (montos, mora, cuotas pagables) son SIEMPRE del
/// backend: esta clase no calcula ni ajusta importes.
class PlanesCuotasService {
  PlanesCuotasService({http.Client? client, Future<String?> Function()? leerToken})
    : _client = client ?? http.Client(),
      _leerToken = leerToken ?? (() => TokenStorage().getToken());

  final http.Client _client;

  /// Fuente del JWT (por defecto [TokenStorage], inyectable en pruebas).
  final Future<String?> Function() _leerToken;

  /// Tiempo máximo de espera para una respuesta del servidor.
  static const Duration _timeout = Duration(seconds: 20);

  /// Servicio de pagos de CU31: se reutiliza la consulta de estado del pago
  /// para no duplicar el contrato `GET /pagos/stripe/pagos/{id}/estado`.
  late final PagosService _pagos = PagosService(
    client: _client,
    leerToken: _leerToken,
  );

  /// Lista los planes de pago del paciente autenticado.
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/mis-planes?page=..&page_size=..`
  ///
  /// [estado] es opcional y acepta `ACTIVO`, `COMPLETADO` o `CANCELADO`.
  Future<List<PlanPagoResumen>> listarMisPlanes({
    String? estado,
    int pagina = 1,
    int porPagina = 50,
  }) async {
    final StringBuffer ruta = StringBuffer(
      '/pagos/mis-planes?page=$pagina&page_size=$porPagina',
    );
    final String estadoApi = (estado ?? '').trim().toUpperCase();
    if (estadoApi.isNotEmpty) {
      ruta.write('&estado=$estadoApi');
    }

    final http.Response respuesta = await _get(ruta.toString());

    if (respuesta.statusCode == 200) {
      final Map<String, dynamic> cuerpo = _objeto(respuesta);

      try {
        return PaginaPlanes.fromJson(cuerpo).items;
      } on TypeError {
        throw const PagosException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PagosException(
      _mensajeError(
        respuesta,
        mensaje404: 'No se encontró la información de tus planes de pago.',
      ),
      statusCode: respuesta.statusCode,
    );
  }

  /// Consulta un plan del paciente con su cronograma de cuotas.
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/mis-planes/{planId}`
  Future<PlanPago> consultarMiPlan(int planId) async {
    final http.Response respuesta = await _get('/pagos/mis-planes/$planId');

    if (respuesta.statusCode == 200) {
      final Map<String, dynamic> cuerpo = _objeto(respuesta);

      try {
        return PlanPago.fromJson(cuerpo);
      } on TypeError {
        throw const PagosException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PagosException(
      _mensajeError(respuesta, mensaje404: 'No se encontró el plan de pago.'),
      statusCode: respuesta.statusCode,
    );
  }

  /// Crea (o reutiliza) el PaymentIntent de Stripe de una cuota.
  ///
  /// `POST {ApiConfig.baseUrl}/pagos/cuotas/{cuotaId}/stripe/intencion`
  ///
  /// El backend decide el importe y aplica sus protecciones anti-doble cobro:
  /// un HTTP 409 significa que NO debe reintentarse automáticamente.
  Future<IntencionCuotaStripe> crearIntencionCuota(int cuotaId) async {
    final http.Response respuesta = await _post(
      '/pagos/cuotas/$cuotaId/stripe/intencion',
      const <String, dynamic>{},
    );

    if (respuesta.statusCode == 201 || respuesta.statusCode == 200) {
      final Map<String, dynamic> cuerpo = _objeto(respuesta);

      try {
        return IntencionCuotaStripe.fromJson(cuerpo);
      } on TypeError {
        throw const PagosException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PagosException(
      _mensajeError(
        respuesta,
        mensaje409:
            'La cuota ya no está disponible para cobro. '
            'Actualiza el plan antes de intentarlo de nuevo.',
      ),
      statusCode: respuesta.statusCode,
    );
  }

  /// Consulta el estado REAL del pago en el backend (fuente de verdad).
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/stripe/pagos/{pagoId}/estado`
  Future<EstadoPago> consultarEstadoPago(int pagoId) =>
      _pagos.consultarEstado(pagoId);

  /// Lista los pagos e intentos registrados de una cuota.
  ///
  /// `GET {ApiConfig.baseUrl}/pagos/cuotas/{cuotaId}/intentos`
  Future<IntentosCuota> listarIntentos(int cuotaId) async {
    final http.Response respuesta = await _get(
      '/pagos/cuotas/$cuotaId/intentos',
    );

    if (respuesta.statusCode == 200) {
      final Map<String, dynamic> cuerpo = _objeto(respuesta);

      try {
        return IntentosCuota.fromJson(cuerpo);
      } on TypeError {
        throw const PagosException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PagosException(
      _mensajeError(respuesta, mensaje404: 'No se encontró la cuota.'),
      statusCode: respuesta.statusCode,
    );
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
  Map<String, String> _headers(String token, {bool json = false}) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
  };

  /// GET autenticado con JWT Bearer contra [ruta].
  Future<http.Response> _get(String ruta) async {
    final String token = await _token();
    final Uri uri = Uri.parse('${ApiConfig.baseUrl}$ruta');

    try {
      return await _client.get(uri, headers: _headers(token)).timeout(_timeout);
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

  /// Decodifica un objeto JSON de la respuesta.
  Map<String, dynamic> _objeto(http.Response respuesta) {
    try {
      final Object? cuerpo = jsonDecode(respuesta.body);

      if (cuerpo is Map<String, dynamic>) return cuerpo;
    } on FormatException {
      // Se maneja abajo con un mensaje entendible.
    }

    throw const PagosException(
      'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
    );
  }

  /// Convierte el error HTTP de FastAPI en un mensaje entendible.
  String _mensajeError(
    http.Response respuesta, {
    String? mensaje404,
    String? mensaje409,
  }) {
    try {
      final Object? cuerpo = jsonDecode(respuesta.body);

      if (cuerpo is Map<String, dynamic> && cuerpo['detail'] != null) {
        final Object? detalle = cuerpo['detail'];

        if (detalle is String && detalle.trim().isNotEmpty) {
          return detalle.trim();
        }

        if (detalle is List && detalle.isNotEmpty) {
          final List<String> mensajes = <String>[
            for (final item in detalle)
              if (item is Map<String, dynamic> && item['msg'] is String)
                item['msg'] as String,
          ];

          if (mensajes.isNotEmpty) {
            return mensajes.map(_limpiarMensajeValidacion).join('\n');
          }
        }
      }
    } on FormatException {
      // El cuerpo no es JSON: se usa el mensaje por código de estado.
    }

    switch (respuesta.statusCode) {
      case 401:
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 403:
        return 'No tienes permisos para realizar esta operación.';
      case 404:
        return mensaje404 ?? 'No se encontró la información solicitada.';
      case 409:
        return mensaje409 ??
            'La operación no está disponible en este momento. '
                'Actualiza la información antes de intentarlo de nuevo.';
      case 422:
        return 'Los datos enviados no son válidos.';
      case 500:
        return 'Ocurrió un error en el servidor. Inténtalo más tarde.';
      case 502:
        return 'La pasarela de pagos no respondió. Inténtalo más tarde.';
      default:
        return 'No se pudo completar la solicitud '
            '(código ${respuesta.statusCode}). Inténtalo de nuevo.';
    }
  }

  /// Quita el prefijo "Value error, " de los mensajes de validación.
  String _limpiarMensajeValidacion(String mensaje) {
    const String prefijo = 'Value error, ';
    if (mensaje.startsWith(prefijo)) {
      return mensaje.substring(prefijo.length);
    }
    return mensaje;
  }

}
