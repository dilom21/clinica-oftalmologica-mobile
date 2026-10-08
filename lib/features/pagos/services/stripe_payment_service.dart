import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/config/stripe_config.dart';

/// Resultado de intentar presentar el PaymentSheet de Stripe.
enum ResultadoPaymentSheet {
  /// El usuario completó el flujo en la pasarela (NO implica cobro aprobado).
  completado,

  /// El usuario canceló/cerró el PaymentSheet de forma voluntaria.
  cancelado,

  /// Ocurrió un error al inicializar o presentar el PaymentSheet.
  error,
}

/// Resultado devuelto por [StripePaymentService.presentar].
class StripePagoResultado {
  const StripePagoResultado(this.resultado, {this.mensaje});

  /// Tipo de resultado del PaymentSheet.
  final ResultadoPaymentSheet resultado;

  /// Mensaje de error legible cuando [resultado] es
  /// [ResultadoPaymentSheet.error].
  final String? mensaje;

  /// El pago se completó en la pasarela (falta confirmar con el backend).
  bool get fueCompletado => resultado == ResultadoPaymentSheet.completado;

  /// El usuario canceló el flujo voluntariamente.
  bool get fueCancelado => resultado == ResultadoPaymentSheet.cancelado;
}

/// Encapsula TODA la comunicación con el SDK nativo de Stripe.
///
/// Las páginas nunca llaman a `Stripe.instance` directamente: usan este
/// servicio. Esto mantiene la presentación separada de la pasarela y permite
/// sustituirlo en pruebas.
///
/// IMPORTANTE: cerrar/completar el PaymentSheet NO significa que el pago esté
/// aprobado. La única fuente de verdad es el backend (ver `PagosService`).
class StripePaymentService {
  StripePaymentService({String? publishableKey})
    : _publishableKey = publishableKey ?? StripeConfig.publishableKey;

  final String _publishableKey;
  bool _inicializado = false;

  /// Indica si existe una clave publicable configurada.
  bool get estaConfigurado => _publishableKey.trim().isNotEmpty;

  /// Configura la clave publicable y aplica la configuración del SDK.
  ///
  /// Es idempotente: solo ejecuta el trabajo la primera vez.
  Future<void> inicializar() async {
    if (!estaConfigurado || _inicializado) return;

    Stripe.publishableKey = _publishableKey.trim();
    await Stripe.instance.applySettings();
    _inicializado = true;
  }

  /// Inicializa y presenta el PaymentSheet usando el [clientSecret] devuelto
  /// por el backend.
  ///
  /// Devuelve el resultado SIN decidir el estado del pago. La confirmación real
  /// se consulta después contra `GET /pagos/stripe/pagos/{pago_id}/estado`.
  Future<StripePagoResultado> presentar({
    required String clientSecret,
    String merchantDisplayName = StripeConfig.merchantDisplayName,
  }) async {
    await inicializar();

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantDisplayName,
      ),
    );

    try {
      await Stripe.instance.presentPaymentSheet();
      return const StripePagoResultado(ResultadoPaymentSheet.completado);
    } on StripeException catch (error) {
      // La cancelación voluntaria usa FailureCode.Canceled.
      if (error.error.code == FailureCode.Canceled) {
        return const StripePagoResultado(ResultadoPaymentSheet.cancelado);
      }

      return StripePagoResultado(
        ResultadoPaymentSheet.error,
        mensaje:
            error.error.localizedMessage ??
            error.error.message ??
            'Stripe rechazó la operación.',
      );
    } on Exception {
      return const StripePagoResultado(
        ResultadoPaymentSheet.error,
        mensaje: 'No se pudo completar el pago en la pasarela.',
      );
    }
  }
}
