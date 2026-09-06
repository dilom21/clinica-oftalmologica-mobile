/// Configuración global de comunicación con la API backend.
///
/// La URL base puede sobreescribirse en tiempo de ejecución con:
///
///   flutter run --dart-define=API_URL=http://...
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://192.168.100.5:8000',
  );
}
