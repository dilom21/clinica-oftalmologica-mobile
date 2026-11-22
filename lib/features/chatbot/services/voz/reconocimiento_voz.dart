import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Resultado de solicitar permiso/verificar el motor de reconocimiento.
enum EstadoPermisoVoz { concedido, denegado, noDisponible }

/// Contrato inyectable de reconocimiento de voz (STT).
///
/// El controlador conversacional solo depende de esta interfaz; las pruebas
/// usan un adaptador simulado y nunca abren el micrófono real.
abstract class ReconocimientoVoz {
  /// Inicializa el motor. No abre el micrófono.
  Future<bool> inicializar();

  /// Solicita permiso contextual y comprueba que exista un locale español.
  Future<EstadoPermisoVoz> solicitarPermiso();

  /// Inicia una intervención corta.
  ///
  /// Devuelve `false` si no fue posible escuchar. Los callbacks pertenecen a
  /// este turno; el controlador descarta los de turnos anteriores.
  Future<bool> iniciar({
    required void Function(String parcial) onParcial,
    required void Function(String texto) onFinal,
    required void Function(String error) onError,
    required void Function() onSilencio,
    void Function(double nivel)? onNivel,
  });

  /// Detiene la captura. Puede emitir un resultado final por el callback.
  Future<void> detener();

  /// Cancela la captura y descarta transcripciones pendientes.
  Future<void> cancelar();

  /// Libera recursos (micrófono detenido, listeners sin uso).
  Future<void> liberar();

  bool get escuchando;

  /// `true` solo después de verificar soporte local y de que una captura
  /// on-device arrancó correctamente. Nunca se asume por usar un plugin.
  bool get procesamientoLocalVerificado;

  /// Locale elegido para STT (`es_BO` o alternativa latinoamericana).
  String? get localeUtilizado;
}

/// Adaptador real basado en `speech_to_text`.
///
/// Privacidad:
/// - Solicita reconocimiento SOLO en el dispositivo (`onDevice: true`).
/// - Antes de escuchar comprueba `hasOnDeviceSupport`; si no puede verificar
///   reconocimiento local, no abre el micrófono y el paciente continúa por
///   escrito. Android puede ignorar `onDevice` y caer a la red, por eso la
///   comprobación previa es obligatoria.
/// - No graba archivos de audio ni registra transcripciones.
class SpeechToTextReconocimiento implements ReconocimientoVoz {
  SpeechToTextReconocimiento({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  bool _inicializado = false;
  bool _permisoDenegado = false;
  bool _localVerificado = false;
  bool _turnoActivo = false;
  int _generacionTurno = 0;
  String? _localeId;

  void Function(String)? _onParcial;
  void Function(String)? _onFinal;
  void Function(String)? _onError;
  void Function()? _onSilencio;
  bool _finalEmitido = false;
  String _ultimoParcial = '';

  @override
  bool get escuchando => _speech.isListening;

  @override
  bool get procesamientoLocalVerificado => _localVerificado;

  @override
  String? get localeUtilizado => _localeId;

  @override
  Future<bool> inicializar() async {
    if (_inicializado && _speech.isAvailable) return true;

    try {
      final bool disponible = await _speech
          .initialize(
            onError: _alError,
            onStatus: _alEstado,
            finalTimeout: const Duration(seconds: 2),
          )
          .timeout(const Duration(seconds: 12));
      _inicializado = disponible;
      if (!disponible) return false;

      await _elegirLocaleEspanol().timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      _inicializado = false;
      return false;
    }
  }

  Future<void> _elegirLocaleEspanol() async {
    try {
      final List<LocaleName> locales = await _speech.locales();
      const List<String> preferidos = <String>[
        'es_BO',
        'es-BO',
        'es_419',
        'es-419',
        'es_US',
        'es-US',
        'es_MX',
        'es-MX',
        'es_ES',
        'es-ES',
      ];

      for (final String preferido in preferidos) {
        for (final LocaleName locale in locales) {
          if (locale.localeId.toLowerCase() == preferido.toLowerCase()) {
            _localeId = locale.localeId;
            return;
          }
        }
      }

      for (final LocaleName locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('es')) {
          _localeId = locale.localeId;
          return;
        }
      }
      _localeId = null;
    } catch (_) {
      _localeId = null;
    }
  }

  @override
  Future<EstadoPermisoVoz> solicitarPermiso() async {
    if (!await inicializar()) {
      return _permisoDenegado
          ? EstadoPermisoVoz.denegado
          : EstadoPermisoVoz.noDisponible;
    }

    if (_localeId == null) {
      // Sin español disponible no se ofrece reconocimiento en otro idioma.
      return EstadoPermisoVoz.noDisponible;
    }

    try {
      final bool permiso = await _speech.hasPermission;
      if (!permiso) {
        _permisoDenegado = true;
        return EstadoPermisoVoz.denegado;
      }
    } catch (_) {
      return EstadoPermisoVoz.noDisponible;
    }

    return EstadoPermisoVoz.concedido;
  }

  Future<bool> _soporteLocal() async {
    try {
      return await SpeechToTextPlatform.instance
          .hasOnDeviceSupport(localeId: _localeId)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // La plataforma no expone la comprobación: no se asume local.
      return false;
    }
  }

  @override
  Future<bool> iniciar({
    required void Function(String parcial) onParcial,
    required void Function(String texto) onFinal,
    required void Function(String error) onError,
    required void Function() onSilencio,
    void Function(double nivel)? onNivel,
  }) async {
    if (_speech.isListening) {
      await cancelar();
    }

    if (!await inicializar().timeout(const Duration(seconds: 22)) ||
        _localeId == null) {
      onError('motor_no_disponible');
      return false;
    }

    if (!await _soporteLocal()) {
      _localVerificado = false;
      onError('sin_reconocimiento_local');
      return false;
    }

    _onParcial = onParcial;
    _onFinal = onFinal;
    _onError = onError;
    _onSilencio = onSilencio;
    _finalEmitido = false;
    _ultimoParcial = '';
    _turnoActivo = true;
    _generacionTurno++;

    try {
      await _speech
          .listen(
            onResult: _alResultado,
            onSoundLevelChange: onNivel,
            listenOptions: SpeechListenOptions(
              onDevice: true,
              partialResults: true,
              listenMode: ListenMode.dictation,
              cancelOnError: true,
              pauseFor: const Duration(seconds: 2),
              listenFor: const Duration(seconds: 30),
              localeId: _localeId,
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (!_speech.isListening) {
        _turnoActivo = false;
        onError('micrófono_no_iniciado');
        return false;
      }

      _localVerificado = true;
      return true;
    } catch (_) {
      _turnoActivo = false;
      onError('error_inicio_reconocimiento');
      return false;
    }
  }

  void _alResultado(SpeechRecognitionResult resultado) {
    if (!_turnoActivo) return;

    final String texto = resultado.recognizedWords.trim();
    if (!resultado.finalResult) {
      _ultimoParcial = texto;
      if (texto.isNotEmpty) _onParcial?.call(texto);
      return;
    }

    if (_finalEmitido) return;
    _finalEmitido = true;
    _turnoActivo = false;

    if (texto.isEmpty) {
      _onSilencio?.call();
      return;
    }
    _onFinal?.call(texto);
  }

  void _alEstado(String estado) {
    if (!_turnoActivo) return;
    if (estado != SpeechToText.doneStatus &&
        estado != SpeechToText.notListeningStatus) {
      return;
    }

    // El plugin puede entregar el resultado final unos milisegundos después
    // del estado "done". No se declara silencio de inmediato y se descarta si
    // ya comenzó otro turno.
    final int generacion = _generacionTurno;
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (generacion != _generacionTurno) return;
      if (!_turnoActivo) return;
      if (_finalEmitido) return;

      _turnoActivo = false;
      if (_ultimoParcial.isEmpty) {
        _onSilencio?.call();
      } else {
        _finalEmitido = true;
        _onFinal?.call(_ultimoParcial);
      }
    });
  }

  void _alError(SpeechRecognitionError error) {
    final String mensaje = error.errorMsg.toLowerCase();
    if (mensaje.contains('permission') ||
        mensaje.contains('not-allowed') ||
        mensaje.contains('denied')) {
      _permisoDenegado = true;
    }

    if (!_turnoActivo) return;
    _turnoActivo = false;
    _onError?.call(error.errorMsg);
  }

  @override
  Future<void> detener() async {
    _turnoActivo = false;
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {
      // El micrófono ya estaba detenido.
    }
    _limpiarCallbacks();
  }

  @override
  Future<void> cancelar() async {
    _turnoActivo = false;
    try {
      if (_speech.isListening) await _speech.cancel();
    } catch (_) {
      // El micrófono ya estaba detenido.
    }
    _limpiarCallbacks();
  }

  @override
  Future<void> liberar() async {
    await cancelar();
  }

  void _limpiarCallbacks() {
    _onParcial = null;
    _onFinal = null;
    _onError = null;
    _onSilencio = null;
    _ultimoParcial = '';
  }
}
