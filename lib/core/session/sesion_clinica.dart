import 'package:flutter/foundation.dart';

import '../storage/token_storage.dart';

/// Identidad de la clínica a la que pertenece la sesión autenticada.
///
/// Solo contiene datos que el backend ya entregó en
/// `GET /seguridad/tenant/empresas` (`codigo` y `nombre`) y que el login
/// guardó junto al JWT. La app NO deduce, inventa ni escribe nombres de
/// clínicas.
///
/// El backend todavía NO entrega un logotipo por clínica, por eso este modelo
/// no tiene una fuente de imagen: la interfaz usa una identidad genérica en
/// lugar del logotipo de otra clínica.
class ClinicaSesion {
  const ClinicaSesion({required this.codigo, required this.nombre});

  /// Código interno de la empresa (`empresa_codigo` del JWT tenant).
  final String codigo;

  /// Nombre comercial que el backend devolvió para la clínica.
  final String nombre;

  /// Nombre listo para mostrar.
  ///
  /// Si el backend no envió un nombre se usa el código de la clínica; nunca un
  /// nombre fijo de otra clínica.
  String get etiqueta {
    final String texto = nombre.trim();
    return texto.isEmpty ? codigo.trim() : texto;
  }

  /// Dos identidades son la misma cuando comparten código y nombre.
  @override
  bool operator ==(Object other) {
    return other is ClinicaSesion &&
        other.codigo == codigo &&
        other.nombre == nombre;
  }

  @override
  int get hashCode => Object.hash(codigo, nombre);
}

/// Mantiene en memoria la clínica de la sesión activa.
///
/// La fuente de verdad sigue siendo [TokenStorage] (Keystore/Keychain):
/// `saveTenantSession` escribe el JWT junto a `empresa_codigo` y
/// `empresa_nombre`, y `deleteToken`/`deleteSession` los borra. Esta clase solo
/// expone esos datos a la interfaz y avisa cuando cambian (login, cierre de
/// sesión o JWT rechazado) para que ninguna pantalla conserve la identidad de
/// una clínica anterior.
class SesionClinica extends ChangeNotifier {
  SesionClinica({TokenStorage? storage})
    : _storage = storage ?? TokenStorage();

  final TokenStorage _storage;

  ClinicaSesion? _clinica;
  bool _cargada = false;
  bool _desechada = false;

  /// Clínica de la sesión activa, o `null` si todavía no se cargó o si no hay
  /// sesión (por ejemplo, después de cerrar sesión).
  ClinicaSesion? get clinica => _clinica;

  /// Indica si ya se intentó leer la sesión guardada.
  bool get cargada => _cargada;

  /// Lee la clínica guardada junto al JWT.
  ///
  /// Nunca lanza: si el almacenamiento seguro falla o no hay sesión, la
  /// interfaz muestra su identidad genérica (sin inventar una clínica).
  Future<void> cargar() async {
    ClinicaSesion? clinica;

    try {
      final String codigo = (await _storage.getEmpresaCodigo())?.trim() ?? '';
      final String nombre = (await _storage.getEmpresaNombre())?.trim() ?? '';

      if (codigo.isNotEmpty) {
        clinica = ClinicaSesion(codigo: codigo, nombre: nombre);
      }
    } catch (_) {
      // Almacenamiento no disponible: se conserva la identidad genérica.
      clinica = null;
    }

    _clinica = clinica;
    _cargada = true;
    _notificar();
  }

  /// Olvida la identidad de la clínica (cierre de sesión o JWT rechazado).
  ///
  /// Se llama junto al borrado de la sesión segura para que la interfaz no
  /// reutilice el nombre/logotipo de la clínica anterior.
  void limpiar() {
    if (_clinica == null && _cargada) {
      return;
    }

    _clinica = null;
    _cargada = true;
    _notificar();
  }

  @override
  void dispose() {
    _desechada = true;
    super.dispose();
  }

  /// Notifica solo si la página que lo posee sigue montada.
  void _notificar() {
    if (!_desechada) {
      notifyListeners();
    }
  }
}
