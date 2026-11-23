import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/storage/token_storage.dart';
import '../models/chatbot_models.dart';
import '../services/chatbot_service.dart';

/// Estado y operaciones de la ÚNICA conversación del paciente con el
/// asistente virtual.
///
/// - Texto y voz comparten este controlador, el mismo UUID y el mismo
///   historial temporal.
/// - El historial vive solo en memoria: nunca se usa SharedPreferences,
///   archivos ni bases de datos locales.
/// - Cada reinicio/cierre/cambio de sesión incrementa [generacion]; las
///   respuestas tardías de una generación anterior se descartan.
class ChatbotController extends ChangeNotifier {
  ChatbotController({
    ChatbotApi? api,
    Future<String?> Function()? leerToken,
    DateTime Function()? ahora,
    this.alSesionInvalida,
    this.maxCaracteresMensaje = 1000,
  }) : _api = api ?? ChatbotService(),
       _propioApi = api == null,
       _leerToken = leerToken ?? (() => TokenStorage().getToken()),
       _ahora = ahora ?? DateTime.now;

  final ChatbotApi _api;
  final bool _propioApi;
  final Future<String?> Function() _leerToken;
  final DateTime Function() _ahora;

  /// Se invoca ante un 401 del chatbot (la app reutiliza su cierre de sesión).
  final Future<void> Function()? alSesionInvalida;

  /// Límite por defecto del backend (`CHATBOT_MAX_MESSAGE_LENGTH`).
  final int maxCaracteresMensaje;

  String? _conversacionId;
  DateTime? _expiraEn;
  int _expiraEnSegundos = 0;
  String? _huellaSesion;
  final List<MensajeChat> _mensajes = <MensajeChat>[];

  bool _enviando = false;
  bool _creando = false;
  bool _tarjetasInvalidas = false;
  bool _desechado = false;
  int _generacion = 0;
  int _secuenciaMensaje = 0;
  String? _mensajePropuesta;
  int? _indicePropuesta;
  TarjetaPropuestaCita? _propuesta;
  int _revisionCitas = 0;

  String? _errorGeneral;
  String? _aviso;
  String? _ultimoTextoFallido;
  ModalidadChat _ultimaModalidad = ModalidadChat.texto;
  Duration? _ultimoRetryAfter;

  // -------------------------------------------------------------------
  // Lectura de estado
  // -------------------------------------------------------------------

  String? get conversacionId => _conversacionId;

  bool get tieneConversacion => _conversacionId != null;

  bool get enviando => _enviando;

  bool get creandoConversacion => _creando;

  bool get tarjetasInvalidas => _tarjetasInvalidas;

  bool get puedeEnviar => !_enviando && !_creando && !_desechado;

  int get generacion => _generacion;

  List<MensajeChat> get mensajes => List<MensajeChat>.unmodifiable(_mensajes);

  String? get errorGeneral => _errorGeneral;

  Duration? get ultimoRetryAfter => _ultimoRetryAfter;

  /// Aviso local, por ejemplo cuando la conversación expiró.
  String? get aviso => _aviso;

  bool get tieneMensajes => _mensajes.isNotEmpty;

  bool get puedeReintentar => _ultimoTextoFallido != null && !_enviando;

  /// Minutos restantes antes del TTL del backend (aproximado).
  int? get minutosRestantes {
    final DateTime? expira = _expiraEn;
    if (expira == null) return null;
    final Duration diferencia = expira.difference(_ahora());
    if (diferencia.isNegative) return 0;
    return (diferencia.inSeconds / 60).ceil();
  }

  bool get expirada {
    final DateTime? expira = _expiraEn;
    return expira != null && !_ahora().isBefore(expira);
  }

  /// Identidad LOCAL de la tarjeta recibida, no un ID de propuesta del Backend.
  /// No se busca retrospectivamente otra tarjeta si esta deja de ser vigente.
  bool propuestaVigente(String mensajeId, int indice) =>
      !_desechado &&
      _conversacionId != null &&
      !expirada &&
      mensajeId == _mensajePropuesta &&
      indice == _indicePropuesta &&
      _propuesta != null &&
      _propuesta!.datosValidos &&
      _propuesta!.inicioLocal!.isAfter(_ahora());

  Future<TarjetaPropuestaCita?> prepararPropuesta(
    String mensajeId,
    int indice,
  ) async {
    if (_enviando || !propuestaVigente(mensajeId, indice)) return null;
    await _verificarSesion();
    if (_desechado) return null;
    verificarExpiracion();
    if (_enviando || !propuestaVigente(mensajeId, indice)) return null;
    return _propuesta;
  }

  void _retirarPropuesta() {
    _mensajePropuesta = null;
    _indicePropuesta = null;
    _propuesta = null;
  }

  // El contrato no informa intención/contexto de propuesta. Solo estas
  // cortesías completas preservan estado sin inferir intención del texto IA.
  // Cualquier contenido adicional (incluidos números/negaciones) lo retira.
  bool _esCortesiaSinCambios(String texto) {
    final normalizado = texto
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'[.,;:!?¡¿]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const expresion =
        r'(?:ok(?:ay)?|muchas gracias|muchisimas gracias|gracias|perfecto|entendido|de acuerdo|muy amable|genial|excelente|vale)';
    return RegExp('^$expresion(?: $expresion)*\$').hasMatch(normalizado);
  }

  void _actualizarPropuesta(MensajeChat mensaje) {
    final propuestas = mensaje.tarjetas
        .whereType<TarjetaPropuestaCita>()
        .toList();
    if (propuestas.isNotEmpty) {
      _retirarPropuesta();
      // Más de una opción no implica una selección única del paciente.
      if (propuestas.length == 1 &&
          propuestas.single.datosValidos &&
          propuestas.single.inicioLocal!.isAfter(_ahora())) {
        _mensajePropuesta = mensaje.id;
        _indicePropuesta = mensaje.tarjetas.indexOf(propuestas.single);
        _propuesta = propuestas.single;
      }
    }
    final propuesta = _propuesta;
    if (propuesta == null) return;
    // Incluso una cortesía no prevalece sobre datos estructurados incompatibles.
    for (final tarjeta in mensaje.tarjetas) {
      if (tarjeta is TarjetaDisponibilidad) {
        final dia = tarjeta.fecha;
        final inicio = segundosHoraChat(propuesta.horaInicio)!;
        final fin = segundosHoraChat(propuesta.horaFin)!;
        final compatible =
            tarjeta.oftalmologoId == propuesta.oftalmologoId &&
            dia != null &&
            dia.year == propuesta.fecha!.year &&
            dia.month == propuesta.fecha!.month &&
            dia.day == propuesta.fecha!.day &&
            tarjeta.intervalos.any(
              (intervalo) =>
                  (segundosHoraChat(intervalo.horaInicio) ?? 86400) <= inicio &&
                  (segundosHoraChat(intervalo.horaFin) ?? -1) >= fin,
            );
        if (!compatible) _retirarPropuesta();
      }
      if (tarjeta is TarjetaCitasPropias &&
          tarjeta.citas.any(
            (cita) =>
                cita.oftalmologoId == propuesta.oftalmologoId &&
                cita.fecha == propuesta.fecha &&
                segundosHoraChat(cita.horaInicio) ==
                    segundosHoraChat(propuesta.horaInicio) &&
                cita.estado != 'CANCELADA',
          )) {
        _retirarPropuesta();
      }
      if (tarjeta is TarjetaDesconocida ||
          (tarjeta is TarjetaProfesionales &&
              !tarjeta.profesionales.any(
                (p) => p.id == propuesta.oftalmologoId,
              ))) {
        _retirarPropuesta();
      }
    }
    if (mensaje.tipo == TipoRespuestaChatbot.privacidad ||
        mensaje.tipo == TipoRespuestaChatbot.desconocido) {
      _retirarPropuesta();
    }
  }

  // -------------------------------------------------------------------
  // Operaciones públicas
  // -------------------------------------------------------------------

  /// Envía un mensaje del paciente.
  ///
  /// Devuelve el mensaje del asistente cuando el backend respondió. Devuelve
  /// `null` si no se pudo enviar o si la respuesta se descartó por pertenecer
  /// a una generación/sesión anterior.
  Future<MensajeChat?> enviar(
    String texto, {
    ModalidadChat modalidad = ModalidadChat.texto,
  }) {
    return _enviarInterno(
      texto,
      modalidad: modalidad,
      agregarMensajePaciente: true,
    );
  }

  /// Reintenta EXPLÍCITAMENTE el último mensaje fallido.
  ///
  /// No se ejecuta solo ni se dispara desde temporizadores.
  Future<MensajeChat?> reintentarUltimo() async {
    final String? texto = _ultimoTextoFallido;
    if (texto == null || _enviando || _creando) return null;
    final ModalidadChat modalidad = _ultimaModalidad;
    _quitarErroresLocales();
    return _enviarInterno(
      texto,
      modalidad: modalidad,
      agregarMensajePaciente: false,
    );
  }

  /// Comprueba el TTL antes de mostrar o enviar. Devuelve `true` si expiró.
  bool verificarExpiracion() {
    if (!expirada) return false;
    _descartarPorExpiracion();
    return true;
  }

  /// Inicia una conversación nueva: finaliza la anterior de forma segura y
  /// limpia el historial local. Se crea el UUID en el primer mensaje.
  Future<void> nuevaConversacion() async {
    final String? anterior = _conversacionId;
    _generacion++;
    _limpiarEstado(mantenerAviso: false);
    _notificar();

    if (anterior != null && anterior.isNotEmpty) {
      // Mejor esfuerzo: una conversación nueva nunca reutiliza el contexto
      // anterior, aunque el DELETE no llegue al servidor.
      unawaited(_finalizarSilencioso(anterior));
    }
  }

  /// Finaliza la conversación activa mediante `DELETE`.
  Future<void> finalizar() async {
    final String? anterior = _conversacionId;
    _generacion++;
    _limpiarEstado(mantenerAviso: false);
    _notificar();

    if (anterior == null || anterior.isEmpty) return;
    await _finalizarSilencioso(anterior);
  }

  /// Cierre de sesión o JWT rechazado: invalida todo sin usar la red.
  void cerrarSesion() {
    _generacion++;
    _limpiarEstado(mantenerAviso: false);
    _notificar();
  }

  /// Marca las tarjetas de propuestas/disponibilidad como históricas.
  ///
  /// Se usa tras registrar, reprogramar o cancelar una cita real. Opcionalmente
  /// agrega un aviso local (nunca una respuesta simulada de la IA).
  void invalidarTarjetas({String? evento}) {
    ++_revisionCitas;
    _retirarPropuesta();
    _tarjetasInvalidas = true;
    if (evento != null && evento.trim().isNotEmpty) {
      _agregarSistema(evento.trim());
    }
    _notificar();
  }

  /// Limpia el aviso de expiración mostrado por la interfaz.
  void limpiarAviso() {
    if (_aviso == null) return;
    _aviso = null;
    _notificar();
  }

  // -------------------------------------------------------------------
  // Envío
  // -------------------------------------------------------------------

  Future<MensajeChat?> _enviarInterno(
    String texto, {
    required ModalidadChat modalidad,
    required bool agregarMensajePaciente,
  }) async {
    final String limpio = texto.trim();
    if (limpio.isEmpty || _desechado) return null;

    if (limpio.length > maxCaracteresMensaje) {
      _errorGeneral =
          'El mensaje supera el límite de $maxCaracteresMensaje caracteres.';
      _notificar();
      return null;
    }

    if (_enviando || _creando) return null;

    // El TTL se comprueba de forma perezosa (sin temporizadores).
    verificarExpiracion();

    // Un JWT distinto invalida cualquier conversación anterior.
    await _verificarSesion();

    if (_desechado) return null;

    // Suspender no basta: una intención nueva no puede reutilizar el contexto
    // anterior aunque falle la petición o la respuesta no contenga tarjetas.
    if (!_esCortesiaSinCambios(limpio)) _retirarPropuesta();
    _quitarErroresLocales();
    _errorGeneral = null;
    _aviso = null;
    _ultimoRetryAfter = null;

    if (agregarMensajePaciente) {
      _mensajes.add(
        MensajeChat(
          id: _nuevoId(),
          rol: RolMensajeChat.paciente,
          texto: limpio,
          hora: _ahora(),
        ),
      );
    }

    _enviando = true;
    _notificar();

    final int generacionEnvio = _generacion;
    final int revisionCitasEnvio = _revisionCitas;

    try {
      final bool lista = await _asegurarConversacion(limpio, modalidad);
      if (!lista || generacionEnvio != _generacion) return null;

      final RespuestaChatbot respuesta = await _api.enviarMensaje(
        conversacionId: _conversacionId!,
        mensaje: limpio,
        modalidad: modalidad,
      );

      if (generacionEnvio != _generacion) return null;

      final String? huellaActual = await _huellaActual();
      if (generacionEnvio != _generacion || _desechado) return null;
      if (huellaActual != _huellaSesion) {
        _limpiarPorSesion();
        return null;
      }

      final String idRespuesta = respuesta.conversacionId.trim();
      if (idRespuesta.isNotEmpty && idRespuesta != _conversacionId) {
        throw const ChatbotException(
          'La respuesta pertenece a otra conversación y fue descartada. '
          'Inicia una conversación nueva.',
          respuestaInvalida: true,
        );
      }

      if (respuesta.respuesta.trim().isEmpty) {
        throw const ChatbotException(
          'El asistente envió una respuesta vacía. Inténtalo de nuevo.',
          respuestaInvalida: true,
        );
      }

      _expiraEn = _ahora().add(Duration(seconds: _expiraEnSegundos));
      _tarjetasInvalidas = false;
      _ultimoTextoFallido = null;
      _ultimaModalidad = modalidad;

      final MensajeChat mensaje = MensajeChat(
        id: _nuevoId(),
        rol: RolMensajeChat.asistente,
        texto: respuesta.respuesta,
        hora: _ahora(),
        tarjetas: respuesta.tarjetas,
        tipo: respuesta.tipo,
        textoVoz: respuesta.textoVoz,
      );
      _mensajes.add(mensaje);
      if (revisionCitasEnvio == _revisionCitas) _actualizarPropuesta(mensaje);
      return mensaje;
    } on ChatbotException catch (error) {
      if (generacionEnvio != _generacion || _desechado) return null;
      await _manejarError(error, limpio, modalidad);
      return null;
    } catch (_) {
      if (generacionEnvio != _generacion || _desechado) return null;
      await _manejarError(
        const ChatbotException(
          'Ocurrió un error inesperado con el asistente. '
          'Inténtalo de nuevo.',
        ),
        limpio,
        modalidad,
      );
      return null;
    } finally {
      if (generacionEnvio == _generacion && !_desechado) {
        _enviando = false;
        _notificar();
      }
    }
  }

  /// Crea el UUID de conversación si todavía no existe.
  Future<bool> _asegurarConversacion(
    String texto,
    ModalidadChat modalidad,
  ) async {
    if (_conversacionId != null && !expirada) return true;

    if (expirada) _descartarPorExpiracion();

    _creando = true;
    _notificar();

    try {
      final String? huellaAntes = await _huellaActual();
      final ConversacionChatbot conversacion = await _api.crearConversacion();
      final String? huellaDespues = await _huellaActual();

      if (huellaAntes != huellaDespues) {
        _limpiarPorSesion();
        return false;
      }

      if (conversacion.id.trim().isEmpty) {
        throw const ChatbotException(
          'No se pudo iniciar la conversación. Inténtalo de nuevo.',
          respuestaInvalida: true,
        );
      }

      _conversacionId = conversacion.id;
      _expiraEnSegundos = conversacion.expiraEnSegundos > 0
          ? conversacion.expiraEnSegundos
          : 1800;
      _expiraEn = _ahora().add(Duration(seconds: _expiraEnSegundos));
      _huellaSesion = huellaDespues;
      return true;
    } on ChatbotException catch (error) {
      await _manejarError(error, texto, modalidad);
      return false;
    } catch (_) {
      await _manejarError(
        const ChatbotException(
          'No se pudo iniciar la conversación. Inténtalo de nuevo.',
        ),
        texto,
        modalidad,
      );
      return false;
    } finally {
      _creando = false;
      _notificar();
    }
  }

  Future<void> _manejarError(
    ChatbotException error,
    String texto,
    ModalidadChat modalidad,
  ) async {
    _errorGeneral = error.message;
    if (error.resultadoIncierto || error.respuestaInvalida) _retirarPropuesta();
    _ultimoRetryAfter = error.retryAfter;

    if (error.sesionCambiada) {
      _limpiarPorSesion();
      return;
    }

    if (error.statusCode == 401) {
      _limpiarPorSesion();
      final Future<void> Function()? callback = alSesionInvalida;
      if (callback != null) {
        unawaited(callback());
      }
      return;
    }

    if (error.statusCode == 404) {
      _retirarPropuesta();
      // El UUID ya no es utilizable. El historial visible se conserva y el
      // siguiente envío crea una conversación nueva; no se afirma que expiró.
      _conversacionId = null;
      _expiraEn = null;
      _huellaSesion = null;
    }

    // Reintento explícito solo cuando es seguro: un timeout/corte de red pudo
    // haber procesado el turno y repetirlo crearía duplicados. Una respuesta
    // inválida de un mensaje ya enviado también deja el turno en duda.
    final bool seguro =
        !error.resultadoIncierto &&
        !(error.respuestaInvalida && _conversacionId != null);
    _ultimoTextoFallido = seguro && texto.trim().isNotEmpty
        ? texto.trim()
        : null;
    _ultimaModalidad = modalidad;

    _mensajes.removeWhere((MensajeChat m) => m.esError);
    _mensajes.add(
      MensajeChat(
        id: _nuevoId(),
        rol: RolMensajeChat.sistema,
        texto: error.message,
        hora: _ahora(),
        esError: true,
        textoReintentable: _ultimoTextoFallido,
      ),
    );
    _notificar();
  }

  // -------------------------------------------------------------------
  // Sesión y ciclo de vida
  // -------------------------------------------------------------------

  Future<void> _verificarSesion() async {
    final String? huellaActual = await _huellaActual();
    final String? anterior = _huellaSesion;
    if (anterior != null && huellaActual != anterior) {
      _generacion++;
      _limpiarEstado(mantenerAviso: false);
      _notificar();
    }
  }

  Future<String?> _huellaActual() async {
    final String? token = await _leerToken();
    if (token == null || token.isEmpty) return null;
    // Huella no reversible y no persistida: solo detecta cambios de sesión.
    return '${token.length}:${token.hashCode}';
  }

  void _limpiarPorSesion() {
    _generacion++;
    _limpiarEstado(mantenerAviso: false);
    _notificar();
  }

  void _descartarPorExpiracion() {
    _generacion++;
    _limpiarEstado(mantenerAviso: true);
    _notificar();
  }

  void _limpiarEstado({required bool mantenerAviso}) {
    _retirarPropuesta();
    _conversacionId = null;
    _expiraEn = null;
    _expiraEnSegundos = 0;
    _huellaSesion = null;
    _mensajes.clear();
    _enviando = false;
    _creando = false;
    _tarjetasInvalidas = false;
    _errorGeneral = null;
    _ultimoTextoFallido = null;
    _ultimoRetryAfter = null;
    if (!mantenerAviso) {
      _aviso = null;
    } else {
      _aviso =
          'La conversación anterior expiró. Escribe tu consulta para '
          'comenzar de nuevo.';
    }
  }

  Future<void> _finalizarSilencioso(String conversacionId) async {
    try {
      await _api.finalizarConversacion(conversacionId);
    } catch (_) {
      // Mejor esfuerzo: la conversación local ya fue abandonada.
    }
  }

  // -------------------------------------------------------------------
  // Utilidades internas
  // -------------------------------------------------------------------

  void _quitarErroresLocales() {
    _mensajes.removeWhere((MensajeChat m) => m.esError);
  }

  void _agregarSistema(String texto) {
    _mensajes.add(
      MensajeChat(
        id: _nuevoId(),
        rol: RolMensajeChat.sistema,
        texto: texto,
        hora: _ahora(),
      ),
    );
  }

  String _nuevoId() => 'm${++_secuenciaMensaje}';

  void _notificar() {
    if (!_desechado) notifyListeners();
  }

  @override
  void dispose() {
    _retirarPropuesta();
    _desechado = true;
    _generacion++;
    _mensajes.clear();
    if (_propioApi && _api is ChatbotService) {
      _api.dispose();
    }
    super.dispose();
  }
}
