// La API pública usa nombres sin guion bajo; los campos internos son privados.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chatbot_models.dart';
import '../services/voz/reconocimiento_voz.dart';
import '../services/voz/sintesis_voz.dart';
import 'chatbot_controller.dart';

/// Estados explícitos de la conversación por voz.
enum EstadoVoz {
  inactivo,
  solicitandoPermiso,
  escuchando,
  procesando,
  respondiendo,
  pausado,
  error,
  noDisponible,
  finalizado,
}

/// Máquina de estados del asistente de voz (Nivel 2: conversación automática).
///
/// Ciclo: activar -> permiso -> escuchar -> fin de intervención -> enviar ->
/// responder -> TTS termina -> volver a escuchar.
///
/// Garantías:
/// - STT y TTS nunca están activos a la vez: antes de hablar se detiene el
///   micrófono y antes de escuchar se detiene la síntesis.
/// - Solo se envían resultados FINALES; los parciales únicamente actualizan la
///   transcripción visual.
/// - Cada turno tiene un identificador; los callbacks tardíos se descartan.
/// - Tras silencios/errores repetidos se pausa en lugar de entrar en un bucle.
/// - Al volver del segundo plano NO se reactiva el micrófono automáticamente.
class ChatVozController extends ChangeNotifier {
  ChatVozController({
    required ChatbotController conversacion,
    required ReconocimientoVoz reconocimiento,
    required SintesisVoz sintesis,
    bool reproduccionAutomatica = true,
    int maxSilencios = 2,
    int maxErrores = 2,
    Duration retrasoReintento = const Duration(milliseconds: 400),
    Duration separacionTrasTts = const Duration(milliseconds: 450),
  }) : _conversacion = conversacion,
       _reconocimiento = reconocimiento,
       _sintesis = sintesis,
       _reproduccionAutomatica = reproduccionAutomatica,
       _maxSilencios = maxSilencios,
       _maxErrores = maxErrores,
       _retrasoReintento = retrasoReintento,
       _separacionTrasTts = separacionTrasTts {
    _generacionConversacion = conversacion.generacion;
    _conversacion.addListener(_alCambiarConversacion);
  }

  final ChatbotController _conversacion;
  final ReconocimientoVoz _reconocimiento;
  final SintesisVoz _sintesis;
  final int _maxSilencios;
  final int _maxErrores;
  final Duration _retrasoReintento;
  final Duration _separacionTrasTts;

  bool _reproduccionAutomatica;
  EstadoVoz _estado = EstadoVoz.inactivo;
  bool _activa = false;
  bool _visible = true;
  bool _primerPlano = true;
  bool _pausadoUsuario = false;
  bool _desechado = false;
  bool _activando = false;
  bool _iniciandoEscucha = false;
  bool _preparandoTts = false;

  int _secuencia = 0;
  int _turnoFinalizado = -1;
  int _idTts = 0;
  int _silencios = 0;
  int _erroresStt = 0;
  int _erroresTts = 0;
  int _generacionConversacion = 0;

  String _transcripcion = '';
  String _subtitulo = '';
  String? _aviso;
  String? _mensajeError;
  final ValueNotifier<double> nivel = ValueNotifier<double>(0);
  RespuestaChatbot? _respuestaActual;
  bool _localVerificado = false;
  String? _localeStt;

  // -------------------------------------------------------------------
  // Lectura
  // -------------------------------------------------------------------

  EstadoVoz get estado => _estado;
  bool get activa => _activa;
  bool get pausado => _estado == EstadoVoz.pausado;
  String get transcripcion => _transcripcion;
  String get subtitulo => _subtitulo;
  String? get aviso => _aviso;
  String? get mensajeError => _mensajeError;
  double get nivelAudio => nivel.value;
  RespuestaChatbot? get respuestaActual => _respuestaActual;

  /// `true` si el paciente ya autorizó explícitamente la voz en esta pantalla.
  bool get requiereActivacion => !_activa;

  bool get reproduccionAutomatica => _reproduccionAutomatica;

  bool get reconocimientoLocalVerificado => _localVerificado;

  String? get localeStt => _localeStt;

  bool get respuestaPrivada =>
      _respuestaActual?.contieneInformacionPrivada ?? false;

  bool get puedeEscucharRespuesta =>
      _respuestaActual != null &&
      (!respuestaPrivada || _sintesis.procesamientoLocalVerificado) &&
      _estado != EstadoVoz.respondiendo &&
      _estado != EstadoVoz.procesando;

  set reproduccionAutomatica(bool valor) {
    if (_reproduccionAutomatica == valor) return;
    _reproduccionAutomatica = valor;
    _notificar();
  }

  /// Texto principal que la esfera muestra bajo su animación.
  String get textoEstado => switch (_estado) {
    EstadoVoz.inactivo => 'Listo para conversar',
    EstadoVoz.solicitandoPermiso => 'Preparando el micrófono',
    EstadoVoz.escuchando => 'Te escucho...',
    EstadoVoz.procesando => 'Consultando información...',
    EstadoVoz.respondiendo => 'El asistente está hablando',
    EstadoVoz.pausado => 'Conversación en pausa',
    EstadoVoz.error => 'No pudimos continuar',
    EstadoVoz.noDisponible => 'Voz no disponible',
    EstadoVoz.finalizado => 'Conversación finalizada',
  };

  /// Subtítulo accesible con contexto adicional.
  String get textoSubtitulo {
    switch (_estado) {
      case EstadoVoz.inactivo:
        return 'Pulsa el micrófono para hablar con el asistente.';
      case EstadoVoz.solicitandoPermiso:
        return 'Verificando el permiso de micrófono.';
      case EstadoVoz.escuchando:
        return _transcripcion.isEmpty
            ? 'Habla con naturalidad. Puedes pausar cuando quieras.'
            : 'Estoy escuchando tu mensaje.';
      case EstadoVoz.procesando:
        return 'Estamos preparando la respuesta. No hace falta que repitas.';
      case EstadoVoz.respondiendo:
        return 'Puedes detener la respuesta con el control de audio.';
      case EstadoVoz.pausado:
        return _aviso ?? 'Pulsa continuar para retomar la conversación.';
      case EstadoVoz.error:
        return _mensajeError ?? _aviso ?? 'Puedes reintentar o volver al chat.';
      case EstadoVoz.noDisponible:
        return _mensajeError ??
            'Continúa por escrito desde el chat del asistente.';
      case EstadoVoz.finalizado:
        return 'Puedes volver al chat para iniciar otra consulta.';
    }
  }

  // -------------------------------------------------------------------
  // Activación y ciclo de escucha
  // -------------------------------------------------------------------

  /// Debe llamarse SOLO después del consentimiento informado de la interfaz.
  Future<void> activar() async {
    if (_activando || _desechado) return;
    _activando = true;
    try {
      await _activarInterno();
    } finally {
      _activando = false;
    }
  }

  Future<void> _activarInterno() async {
    if (_desechado) return;
    if (_activa &&
        (_estado == EstadoVoz.escuchando ||
            _estado == EstadoVoz.procesando ||
            _estado == EstadoVoz.respondiendo)) {
      return;
    }

    _activa = true;
    _pausadoUsuario = false;
    _silencios = 0;
    _erroresStt = 0;
    _erroresTts = 0;
    _aviso = null;
    _mensajeError = null;
    _estado = EstadoVoz.solicitandoPermiso;
    _notificar();

    EstadoPermisoVoz permiso;
    try {
      permiso = await _reconocimiento.solicitarPermiso().timeout(
        const Duration(seconds: 30),
      );
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[CU41Voice][Controller] permission flow timeout');
      }
      if (!_activa || _desechado) return;
      _estado = EstadoVoz.error;
      _activa = false;
      _pausadoUsuario = true;
      _mensajeError = 'La preparación del micrófono tardó demasiado. Puedes reintentar o continuar por escrito.';
      _notificar();
      return;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[CU41Voice][Controller] permission flow exception');
      }
      if (!_activa || _desechado) return;
      _estado = EstadoVoz.error;
      _activa = false;
      _mensajeError = 'No se pudo preparar el micrófono. Puedes reintentar o continuar por escrito.';
      _notificar();
      return;
    }
    if (!_activa || _desechado) return;

    if (permiso == EstadoPermisoVoz.denegado) {
      if (kDebugMode) {
        debugPrint('[CU41Voice][Controller] permission denied');
      }
      _estado = EstadoVoz.noDisponible;
      _mensajeError =
          'No se concedió permiso para usar el micrófono. Puedes continuar '
          'por escrito desde el chat.';
      _activa = false;
      _notificar();
      return;
    }

    if (permiso == EstadoPermisoVoz.noDisponible) {
      if (kDebugMode) {
        debugPrint('[CU41Voice][Controller] recognizer unavailable');
      }
      _estado = EstadoVoz.noDisponible;
      _mensajeError =
          'El reconocimiento de voz local no está disponible en este '
          'dispositivo o idioma. Puedes continuar por escrito desde el chat.';
      _activa = false;
      _notificar();
      return;
    }

    _localVerificado = _reconocimiento.procesamientoLocalVerificado;
    _localeStt = _reconocimiento.localeUtilizado;

    // La síntesis es opcional: si falla, la conversación puede seguir por
    // escrito o con turnos manuales.
    await _sintesis.inicializar();
    if (!_activa || _desechado) return;

    await _iniciarEscucha();
  }

  Future<void> _iniciarEscucha() async {
    if (_iniciandoEscucha || _desechado) return;
    _iniciandoEscucha = true;
    try {
      await _iniciarEscuchaInterno();
    } finally {
      _iniciandoEscucha = false;
    }
  }

  Future<void> _iniciarEscuchaInterno() async {
    if (!_puedeEscucharAhora()) {
      _estado = EstadoVoz.pausado;
      _notificar();
      return;
    }

    // Nunca se escucha mientras el asistente habla.
    if (_sintesis.hablando) {
      try {
        await _sintesis.detener();
        if (_sintesis.hablando) throw StateError('tts_stop_not_confirmed');
      } catch (_) {
        _pausadoUsuario = true;
        _estado = EstadoVoz.pausado;
        _aviso = 'No se confirmó la detención del audio. El micrófono sigue cerrado.';
        _notificar();
        return;
      }
    }
    if (_reconocimiento.escuchando) await _reconocimiento.detener();

    if (!_puedeEscucharAhora()) {
      _estado = EstadoVoz.pausado;
      _notificar();
      return;
    }

    final int turno = ++_secuencia;
    _transcripcion = '';
    nivel.value = 0;
    _aviso = null;
    _mensajeError = null;
    _estado = EstadoVoz.escuchando;
    _notificar();

    final bool iniciado = await _reconocimiento.iniciar(
      onParcial: (String texto) => _alParcial(texto, turno),
      onFinal: (String texto) => _alFinal(texto, turno),
      onError: (String error) => _alErrorStt(error, turno),
      onSilencio: () => _alSilencio(turno),
      onNivel: (double nivel) => _alNivel(nivel, turno),
    );

    if (!iniciado &&
        turno == _secuencia &&
        _estado == EstadoVoz.escuchando &&
        _activa) {
      unawaited(_falloStt('micrófono_no_iniciado'));
    }
  }

  bool _puedeEscucharAhora() {
    return _activa && _visible && _primerPlano && !_pausadoUsuario;
  }

  bool _turnoVigente(int turno) {
    return turno == _secuencia &&
        _activa &&
        _visible &&
        _primerPlano &&
        _estado == EstadoVoz.escuchando;
  }

  void _alParcial(String texto, int turno) {
    if (!_turnoVigente(turno)) return;
    final String limpio = texto.trim();
    if (limpio.isEmpty) return;
    _transcripcion = limpio;
    if (kDebugMode) {
      debugPrint(
        '[CU41Voice][Controller] partial turn=$turno displayOnly=true',
      );
    }
    _silencios = 0;
    _notificar();
  }

  void _alNivel(double nivelRecibido, int turno) {
    if (!_turnoVigente(turno)) return;
    nivel.value = nivelRecibido.clamp(0.0, 1.0);
  }

  Future<void> _alFinal(String texto, int turno) async {
    if (!_turnoVigente(turno)) return;
    if (kDebugMode) {
      debugPrint('[CU41Voice][Controller] final received turn=$turno');
    }

    final String limpio = texto.trim();
    if (limpio.isEmpty) {
      _alSilencio(turno);
      return;
    }

    if (_turnoFinalizado == turno) return;
    _turnoFinalizado = turno;

    _transcripcion = limpio;
    _estado = EstadoVoz.procesando;
    nivel.value = 0;
    _mensajeError = null;
    _aviso = null;
    _notificar();

    // El micrófono queda cerrado antes de cualquier reproducción.
    await _reconocimiento.detener();
    if (_desechado ||
        !_activa ||
        !_visible ||
        !_primerPlano ||
        _pausadoUsuario ||
        turno != _secuencia) {
      return;
    }

    final int generacion = _conversacion.generacion;
    if (kDebugMode) {
      debugPrint(
        '[CU41Voice][Controller] sending final turn=$turno modality=voice',
      );
    }
    final MensajeChat? respuesta = await _conversacion.enviar(
      limpio,
      modalidad: ModalidadChat.voz,
    );

    if (_desechado || !_activa) return;
    if (turno != _secuencia || generacion != _conversacion.generacion) return;

    if (respuesta == null) {
      _estado = EstadoVoz.pausado;
      _mensajeError =
          _conversacion.errorGeneral ??
          'No pudimos obtener una respuesta. Puedes reintentar o continuar '
              'por escrito.';
      _notificar();
      return;
    }

    _transcripcion = '';
    _subtitulo = respuesta.texto;
    _respuestaActual = RespuestaChatbot(
      conversacionId: _conversacion.conversacionId ?? '',
      respuesta: respuesta.texto,
      textoVoz: respuesta.textoVoz ?? respuesta.texto,
      tipo: respuesta.tipo ?? TipoRespuestaChatbot.texto,
      tarjetas: respuesta.tarjetas,
    );
    _notificar();

    final bool privada =
        respuesta.tipo == TipoRespuestaChatbot.privacidad ||
        respuesta.tarjetas.any((TarjetaChatbot t) => t.esPrivada);

    if (privada && !_sintesis.procesamientoLocalVerificado) {
      // Nunca se lee automáticamente información privada con un motor TTS
      // cuya localidad no puede verificarse.
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'Esta respuesta contiene información privada. Por seguridad se '
          'muestra solo por escrito. Puedes leerla en el chat.';
      _notificar();
      return;
    }

    if (!_reproduccionAutomatica) {
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'Respuesta lista. Usa el control de audio para escucharla o '
          'continúa por escrito.';
      _notificar();
      return;
    }

    await _reproducir(_respuestaActual!.textoVoz, privado: privada);
  }

  /// Prepara y reproduce un mensaje público ya recibido (por ejemplo desde el
  /// icono de altavoz del chat escrito). No reactiva el micrófono.
  Future<void> reproducirMensaje(MensajeChat mensaje) async {
    if (_desechado) return;
    _respuestaActual = RespuestaChatbot(
      conversacionId: _conversacion.conversacionId ?? '',
      respuesta: mensaje.texto,
      textoVoz: mensaje.textoVoz ?? mensaje.texto,
      tipo: mensaje.tipo ?? TipoRespuestaChatbot.texto,
      tarjetas: mensaje.tarjetas,
    );
    _subtitulo = mensaje.texto;
    final bool privada =
        mensaje.tipo == TipoRespuestaChatbot.privacidad ||
        mensaje.tarjetas.any((TarjetaChatbot t) => t.esPrivada);

    _activa = true;
    _pausadoUsuario = true;
    _erroresTts = 0;
    _estado = EstadoVoz.respondiendo;
    _notificar();
    await _reproducir(mensaje.textoVoz ?? mensaje.texto, privado: privada);
  }

  /// Reproduce de nuevo la última respuesta.
  Future<void> escucharRespuesta() async {
    final RespuestaChatbot? respuesta = _respuestaActual;
    if (respuesta == null ||
        _desechado ||
        _preparandoTts ||
        (_estado == EstadoVoz.respondiendo && _sintesis.hablando)) {
      return;
    }
    _pausadoUsuario = false;
    _activa = true;
    await _reproducir(
      respuesta.textoVoz,
      privado: respuesta.contieneInformacionPrivada,
    );
  }

  Future<void> _reproducir(String texto, {bool privado = false}) async {
    if (_preparandoTts || _desechado) return;
    _preparandoTts = true;
    try {
      await _reproducirInterno(texto, privado: privado);
    } finally {
      _preparandoTts = false;
    }
  }

  Future<void> _reproducirInterno(String texto, {bool privado = false}) async {
    final String limpio = texto.trim();
    if (limpio.isEmpty) {
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso = 'La respuesta no contiene texto para leer. Pulsa continuar para retomar.';
      _notificar();
      return;
    }

    final int id = ++_idTts;
    try {
      await _reconocimiento.detener();
      await _sintesis.detener();
    } catch (_) {
      _alErrorTts(id, 'error_detener_audio');
      return;
    }

    if (!_activa || _desechado || id != _idTts || !_visible || !_primerPlano) {
      return;
    }

    _estado = EstadoVoz.respondiendo;
    nivel.value = 0;
    _notificar();

    final bool disponible = await _sintesis.inicializar();
    if (id != _idTts || _desechado || !_activa || !_visible || !_primerPlano) {
      return;
    }
    if (!disponible) {
      if (id != _idTts || _desechado) return;
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'No hay una voz en español disponible en este dispositivo. '
          'Puedes seguir la conversación por escrito.';
      _notificar();
      return;
    }

    if (privado && !_sintesis.procesamientoLocalVerificado) {
      if (id != _idTts || _desechado) return;
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'Esta respuesta contiene información privada y el motor de voz no '
          'pudo verificarse como local. Se muestra solo por escrito.';
      _notificar();
      return;
    }

    try {
      await _sintesis.hablar(
        limpio,
        onInicio: () {
          if (_desechado || id != _idTts) return;
          _diagnosticoTts('start id=$id');
          _estado = EstadoVoz.respondiendo;
          _notificar();
        },
        onFin: () => _alTerminarTts(id),
        onError: (String error) => _alErrorTts(id, error),
      );
    } catch (_) {
      _alErrorTts(id, 'error_sintesis');
    }
  }

  void _alTerminarTts(int id) {
    _diagnosticoTts('complete id=$id current=$_idTts');
    if (_desechado || id != _idTts) return;
    // Consumir el terminal una vez: callbacks duplicados no abren otra sesión.
    _idTts++;
    if (_sintesis.hablando) {
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'El motor aún indica audio activo. Pulsa continuar para reintentar.';
      _notificar();
      return;
    }

    if (!_activa) {
      _estado = EstadoVoz.inactivo;
      _notificar();
      return;
    }

    if (!_visible || !_primerPlano || _pausadoUsuario) {
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso = 'La conversación se pausó. Pulsa continuar para retomar.';
      _notificar();
      return;
    }

    unawaited(_retomarTrasTts(_idTts));
  }

  Future<void> _retomarTrasTts(int id) async {
    _diagnosticoTts(
      'completed; cooldownMs=${_separacionTrasTts.inMilliseconds}',
    );
    if (_separacionTrasTts > Duration.zero) {
      await Future<void>.delayed(_separacionTrasTts);
    }
    if (_desechado ||
        id != _idTts ||
        !_puedeEscucharAhora() ||
        _sintesis.hablando) {
      return;
    }
    _diagnosticoTts('completed -> listening');
    await _iniciarEscucha();
  }

  void _alErrorTts(int id, String error) {
    if (_desechado || id != _idTts) return;
    _diagnosticoTts('error id=$id -> paused');
    _idTts++;
    _erroresTts++;
    _pausadoUsuario = true;
    _estado = EstadoVoz.pausado;
    _aviso = _erroresTts >= _maxErrores
        ? 'La voz del dispositivo no está funcionando. La conversación '
              'continúa disponible por escrito.'
        : 'No pudimos reproducir la respuesta con la voz del dispositivo. '
              'Puedes intentarlo otra vez o leerla en el chat.';
    _notificar();
  }

  void _diagnosticoTts(String evento) {
    if (kDebugMode) debugPrint('[CU41Voice][Controller][TTS] $evento');
  }

  Future<void> _falloStt(String error) async {
    if (!_activa || _desechado) return;

    _erroresStt++;
    _estado = EstadoVoz.error;

    if (error == 'intervencion_sin_final' ||
        error == 'intervencion_incompleta' ||
        error.contains('no_match') ||
        error.contains('speech_timeout')) {
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'No se confirmó una intervención completa. No se envió al asistente. '
          'Pulsa continuar y repite la pregunta cuando veas «Te escucho». ';
      _notificar();
      await _reconocimiento.cancelar();
      return;
    }

    if (error == 'sin_reconocimiento_local') {
      _localVerificado = false;
      _activa = false;
      _estado = EstadoVoz.noDisponible;
      _mensajeError =
          'No se habilitó el reconocimiento de voz. Sin motor local y sin '
          'autorización para el servicio general, puedes continuar por escrito.';
      _notificar();
      return;
    }

    if (error == 'error_idioma_local_no_disponible') {
      _localVerificado = false;
      _activa = false;
      _estado = EstadoVoz.noDisponible;
      _mensajeError =
          'El reconocedor no aceptó las variantes españolas probadas. '
          'Por privacidad no se cambia de proveedor automáticamente. '
          'Puedes continuar por escrito.';
      _notificar();
      return;
    }

    if (_erroresStt >= _maxErrores) {
      _pausadoUsuario = true;
      _mensajeError =
          'No pudimos mantener el micrófono activo. Pulsa continuar para '
          'reintentar o vuelve al chat escrito.';
      _notificar();
      return;
    }

    _mensajeError = 'Se interrumpió el reconocimiento de voz.';
    _notificar();

    if (_retrasoReintento > Duration.zero) {
      await Future<void>.delayed(_retrasoReintento);
    } else {
      // Cede el turno al event loop para liberar la guarda de inicio.
      await Future<void>.delayed(Duration.zero);
    }
    if (!_activa ||
        _desechado ||
        _estado != EstadoVoz.error ||
        _pausadoUsuario) {
      return;
    }
    await _iniciarEscucha();
  }

  void _alErrorStt(String error, int turno) {
    if (turno != _secuencia || !_activa || _desechado) return;
    unawaited(_falloStt(error));
  }

  void _alSilencio(int turno) {
    if (turno != _secuencia || !_activa || _desechado) return;

    _silencios++;
    if (_silencios >= _maxSilencios) {
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'No escuché ninguna intervención. Pulsa el micrófono para '
          'continuar cuando estés listo.';
      _notificar();
      return;
    }

    _aviso = 'No escuché nada. Seguimos escuchando...';
    _notificar();
    unawaited(_reintentarEscuchaTrasSilencio(turno));
  }

  Future<void> _reintentarEscuchaTrasSilencio(int turno) async {
    if (_retrasoReintento > Duration.zero) {
      await Future<void>.delayed(_retrasoReintento);
    }
    if (_desechado || !_activa || _pausadoUsuario || turno != _secuencia) {
      return;
    }
    await _iniciarEscucha();
  }

  // -------------------------------------------------------------------
  // Controles del paciente
  // -------------------------------------------------------------------

  /// Pausa micrófono y reproducción. La conversación se conserva.
  Future<void> pausar() async {
    if (_desechado) return;
    _pausadoUsuario = true;
    _activa = true;
    _secuencia++;
    _idTts++;
    _estado = EstadoVoz.pausado;
    _aviso = 'Micrófono en pausa. Pulsa continuar cuando quieras.';
    nivel.value = 0;
    _notificar();

    await _detenerAudio();
  }

  /// Retoma la conversación por voz desde una pausa.
  Future<void> reanudar() async {
    if (_desechado) return;
    _activa = true;
    _visible = true;
    _pausadoUsuario = false;
    _silencios = 0;
    _erroresStt = 0;
    _aviso = null;
    _mensajeError = null;
    _notificar();
    await _iniciarEscucha();
  }

  /// Detiene la respuesta hablada y vuelve a escuchar.
  Future<void> detenerRespuesta() async {
    if (_desechado) return;
    _idTts++;
    _secuencia++;
    nivel.value = 0;
    try {
      await _sintesis.detener();
    } catch (_) {
      _pausadoUsuario = true;
      _estado = EstadoVoz.pausado;
      _aviso =
          'No se confirmó la detención del audio. El micrófono sigue cerrado.';
      _notificar();
      return;
    }

    if (_activa && _visible && _primerPlano && !_pausadoUsuario) {
      await _iniciarEscucha();
      return;
    }
    _estado = EstadoVoz.pausado;
    _notificar();
  }

  /// Sale de la modalidad de voz conservando la conversación.
  Future<void> salir() async {
    if (_desechado) return;
    _activa = false;
    _pausadoUsuario = false;
    _secuencia++;
    _idTts++;
    _estado = EstadoVoz.inactivo;
    _transcripcion = '';
    nivel.value = 0;
    _aviso = null;
    _mensajeError = null;
    _notificar();
    await _detenerAudio();
  }

  /// Finaliza por completo la conversación (`DELETE`).
  Future<void> finalizarConversacion() async {
    if (_desechado) return;
    _activa = false;
    _pausadoUsuario = false;
    _secuencia++;
    _idTts++;
    _estado = EstadoVoz.finalizado;
    _transcripcion = '';
    nivel.value = 0;
    _aviso = null;
    _notificar();
    await _detenerAudio();
    await _conversacion.finalizar();
    if (!_desechado) _notificar();
  }

  /// La app pasó a segundo plano / perdió foco.
  Future<void> suspenderPorCicloDeVida() async {
    if (_desechado) return;
    _primerPlano = false;
    _pausadoUsuario = true;
    _secuencia++;
    _idTts++;
    nivel.value = 0;
    await _detenerAudio();
    if (_activa) {
      _estado = EstadoVoz.pausado;
      _aviso =
          'La conversación por voz se pausó porque la aplicación dejó de '
          'estar en primer plano. Pulsa continuar para retomar.';
    }
    _notificar();
  }

  /// Una pérdida breve de foco (p. ej. diálogo de permiso del sistema) no
  /// equivale por sí sola a abandonar la app. La ruta debe permanecer visible;
  /// el estado paused/hidden sigue activando la protección de segundo plano.
  void focoTemporalPerdido() {
    if (_desechado) return;
  }

  /// La app volvió al primer plano: NO se activa el micrófono solo.
  void reanudarCicloDeVida() {
    if (_desechado) return;
    _primerPlano = true;
    _notificar();
  }

  /// La pantalla de voz dejó de ser visible.
  Future<void> alOcultarPantalla() async {
    if (_desechado) return;
    _visible = false;
    _pausadoUsuario = true;
    _secuencia++;
    _idTts++;
    nivel.value = 0;
    await _detenerAudio();
    if (_activa) {
      _estado = EstadoVoz.pausado;
    }
    _notificar();
  }

  /// La pantalla volvió a estar visible (no reactiva automáticamente).
  void alMostrarPantalla() {
    if (_desechado) return;
    _visible = true;
    _notificar();
  }

  Future<void> _detenerAudio() async {
    try {
      await _reconocimiento.cancelar();
    } catch (_) {
      // Micrófono ya detenido.
    }
    try {
      await _sintesis.detener();
    } catch (_) {
      // Síntesis ya detenida.
    }
  }

  void _alCambiarConversacion() {
    if (_desechado) return;
    final int actual = _conversacion.generacion;
    if (actual == _generacionConversacion) return;

    final bool estabaActiva =
        _activa ||
        _estado == EstadoVoz.escuchando ||
        _estado == EstadoVoz.procesando ||
        _estado == EstadoVoz.respondiendo;

    _generacionConversacion = actual;
    _secuencia++;
    _idTts++;
    nivel.value = 0;

    if (!estabaActiva) {
      unawaited(_detenerAudio());
      return;
    }

    _pausadoUsuario = true;
    _activa = false;
    _estado = EstadoVoz.pausado;
    _aviso =
        'La conversación cambió. Pulsa continuar para iniciar un nuevo turno '
        'de voz.';
    _notificar();
    unawaited(_detenerAudio());
  }

  void _notificar() {
    if (!_desechado) notifyListeners();
  }

  @override
  void dispose() {
    _desechado = true;
    _activa = false;
    _secuencia++;
    _idTts++;
    _conversacion.removeListener(_alCambiarConversacion);
    unawaited(_reconocimiento.liberar());
    unawaited(_sintesis.liberar());
    nivel.dispose();
    super.dispose();
  }
}
