/// Configuración de Stripe para la aplicación móvil.
///
/// La clave PUBLICABLE de PRUEBA (`pk_test_...`) NO se hardcodea en el código.
/// Se inyecta en tiempo de compilación mediante `--dart-define`:
///
///   flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_xxxxxxxx
///
/// Reglas de seguridad:
/// - Nunca colocar `sk_test_...` (clave secreta) en la app móvil.
/// - Nunca colocar `STRIPE_WEBHOOK_SECRET` en la app móvil.
/// - El backend es el único que usa la clave secreta.
class StripeConfig {
  /// Clave publicable de Stripe (Test Mode). Vacía si no se configuró.
  static const String publishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  /// Nombre del comercio que muestra el PaymentSheet de Stripe.
  ///
  /// Es genérico a propósito: el nombre comercial real de la clínica está en
  /// `GET /seguridad/tenant/empresas` y el backend todavía no expone un nombre
  /// de comercio por clínica para Stripe. No se escribe el nombre de una
  /// clínica concreta en el código.
  static const String merchantDisplayName = 'Clínica Oftalmológica';

  /// Indica si hay una clave publicable configurada.
  static bool get estaConfigurada => publishableKey.trim().isNotEmpty;
}
