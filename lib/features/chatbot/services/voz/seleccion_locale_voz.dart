/// Locale IDs candidatos, no afirmaciones de disponibilidad. Cada variante
/// debe validarse por el reconocedor local en la sesión real.
const List<String> localesCandidatosEspanol = <String>[
  'es-BO',
  'es-419',
  'es-US',
  'es-MX',
  'es-ES',
];

/// Ordena variantes anunciadas por la plataforma según los candidatos.
List<String> ordenarLocalesEspanol(Iterable<String> localesDisponibles) {
  final List<String> locales = localesDisponibles.toList();
  String? match(String wanted) {
    for (final String locale in locales) {
      if (_normalizar(locale) == _normalizar(wanted)) return locale;
    }
    return null;
  }

  final List<String> ordenados = <String>[];
  for (final String preferido in localesCandidatosEspanol) {
    final String? encontrado = match(preferido);
    if (encontrado != null && !ordenados.contains(encontrado)) {
      ordenados.add(encontrado);
    }
  }
  for (final String locale in locales) {
    if (_normalizar(locale).startsWith('es-') && !ordenados.contains(locale)) {
      ordenados.add(locale);
    }
  }
  return ordenados;
}

/// Devuelve solamente una comprobación positiva; excepción/timeout/método no
/// implementado permanecen como no verificados y nunca abren el micrófono.
Future<bool> comprobarSoporteLocalSeguro(
  Future<bool> Function(String localeId) comprobar,
  String localeId,
) async {
  try {
    return await comprobar(localeId).timeout(const Duration(seconds: 3));
  } catch (_) {
    return false;
  }
}

/// Elige la primera variante en orden preferido cuyo reconocimiento local
/// devuelve soporte positivo. No toma la lista general como prueba offline.
Future<String?> seleccionarPrimerLocaleLocal(
  Iterable<String> locales,
  Future<bool> Function(String localeId) comprobar,
) async {
  for (final String locale in locales) {
    if (await comprobarSoporteLocalSeguro(comprobar, locale)) return locale;
  }
  return null;
}

String _normalizar(String locale) =>
    locale.trim().replaceAll('_', '-').toLowerCase();
