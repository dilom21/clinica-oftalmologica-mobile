import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Contrato inyectable de síntesis de voz (TTS).
///
/// La app solo reproduce `texto_voz` entregado por el backend; nunca reenvía
/// la respuesta a otro modelo para "naturalizarla".
abstract class SintesisVoz {
  /// Inicializa el motor y elige una voz en español.
  Future<bool> inicializar();

  /// Reproduce [texto]. Debe invocar [onInicio] al empezar realmente,
  /// [onFin] al terminar realmente y [onError] si falla.
  Future<void> hablar(
    String texto, {
    required void Function() onInicio,
    required void Function() onFin,
    required void Function(String error) onError,
  });

  /// Detiene la reproducción en curso.
  Future<void> detener();

  /// Libera recursos del motor.
  Future<void> liberar();

  bool get hablando;

  /// `true` si puede verificarse que el motor sintetiza localmente.
  ///
  /// En Android se consulta `isLanguageInstalled` (voz instalada y sin
  /// dependencia de red). En iOS/web no se puede verificar y se devuelve
  /// `false`; el controlador no lee contenido privado en ese caso.
  bool get procesamientoLocalVerificado;
}

/// Adaptador real basado en `flutter_tts`.
class FlutterTtsSintesis implements SintesisVoz {
  FlutterTtsSintesis({
    FlutterTts? tts,
    this.limiteReproduccion = const Duration(minutes: 3),
  }) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// Límite de seguridad, NO una estimación del fin del audio. Al vencer se
  /// solicita stop y se notifica error; nunca se simula una finalización.
  final Duration limiteReproduccion;
  Timer? _vigilancia;
  int _operacion = 0;

  bool _inicializado = false;
  bool _hablando = false;
  bool _localVerificado = false;
  String? _idioma;
  void Function()? _onInicio;
  void Function()? _onFin;
  void Function(String)? _onError;

  @override
  bool get hablando => _hablando;

  /// En Android se consulta `isLanguageInstalled`, que exige una voz instalada
  /// y sin dependencia de red. En otras plataformas no se puede verificar y se
  /// devuelve `false`.
  @override
  bool get procesamientoLocalVerificado => _localVerificado;

  @override
  Future<bool> inicializar() async {
    if (_inicializado) return true;

    try {
      const List<String> candidatos = <String>[
        'es-BO',
        'es-ES',
        'es-US',
        'es-MX',
      ];

      String? elegido;
      for (final String idioma in candidatos) {
        final Object? disponible = await _tts.isLanguageAvailable(idioma);
        if (disponible == true) {
          elegido = idioma;
          break;
        }
      }

      if (elegido == null) return false;

      await _tts.setLanguage(elegido);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);

      _tts.setStartHandler(_alIniciar);
      _tts.setCompletionHandler(_alTerminar);
      _tts.setCancelHandler(_alCancelar);
      _tts.setErrorHandler(_alError);

      _idioma = elegido;
      _localVerificado = await _verificarSintesisLocal(elegido);
      _inicializado = true;
      return true;
    } catch (_) {
      _inicializado = false;
      return false;
    }
  }

  Future<bool> _verificarSintesisLocal(String idioma) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final Object? instalada = await _tts.isLanguageInstalled(idioma);
      return instalada == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> hablar(
    String texto, {
    required void Function() onInicio,
    required void Function() onFin,
    required void Function(String error) onError,
  }) async {
    final String limpio = texto.trim();
    if (limpio.isEmpty) {
      if (_hablando) {
        try {
          await detener();
        } catch (_) {
          onError('error_detener_sintesis');
          return;
        }
      }
      onFin();
      return;
    }

    final int preparacion = _operacion;
    if (!await inicializar()) {
      onError('voz_no_disponible');
      return;
    }
    if (preparacion != _operacion) return;
    final int operacion = _operacion + 1;
    try {
      await detener();
    } catch (_) {
      onError('error_detener_sintesis');
      return;
    }
    if (operacion != _operacion) return;

    _onInicio = onInicio;
    _onFin = onFin;
    _onError = onError;
    _hablando = true;
    _diagnostico('speak requested operation=$operacion');
    _vigilancia = Timer(limiteReproduccion, () {
      if (operacion != _operacion || _onFin == null) return;
      _diagnostico('completion missing operation=$operacion; stopping safely');
      unawaited(_fallarYDetener('timeout_sintesis'));
    });

    try {
      final Object? resultado = await _tts.speak(limpio);
      // Con awaitSpeakCompletion(false) esto confirma aceptación, NO fin de
      // audio. Solo speak.onComplete puede reanudar la escucha automática.
      _diagnostico('speak request returned operation=$operacion');
      if (operacion == _operacion && resultado == 0) {
        await _fallarYDetener('error_sintesis');
      }
    } catch (_) {
      if (operacion == _operacion) {
        await _fallarYDetener('error_sintesis');
      }
    }
  }

  void _alIniciar() {
    if (_onFin == null) return;
    _diagnostico('start operation=$_operacion');
    _hablando = true;
    _onInicio?.call();
  }

  void _alTerminar() {
    if (_onFin == null) return;
    _diagnostico('complete operation=$_operacion');
    final void Function()? callback = _onFin;
    _hablando = false;
    _limpiarCallbacks();
    // Capturar ANTES de limpiar; de lo contrario onFin se pierde siempre.
    callback?.call();
  }

  void _alError(dynamic error) {
    if (_onError == null) return;
    _diagnostico('native error operation=$_operacion');
    // No registrar el mensaje del motor: puede contener el texto sintetizado.
    unawaited(_fallarYDetener('error_sintesis'));
  }

  void _alCancelar() {
    if (_onError == null) return;
    _diagnostico('native cancel operation=$_operacion');
    unawaited(_fallarYDetener('sintesis_cancelada'));
  }

  Future<void> _fallarYDetener(String codigo) async {
    final void Function(String)? callback = _onError;
    if (callback == null) return;
    final Future<void> parada = detener();
    final int operacion = _operacion;
    try {
      await parada;
    } catch (_) {
      _diagnostico('stop not confirmed operation=$operacion');
    }
    if (operacion == _operacion) callback(codigo);
  }

  @override
  Future<void> detener() async {
    final int operacion = ++_operacion;
    _limpiarCallbacks();
    _diagnostico('stop requested operation=$operacion');
    final Object? resultado = await _tts.stop().timeout(
      const Duration(seconds: 3),
    );
    if (resultado == 0) throw StateError('tts_stop_not_confirmed');
    if (operacion == _operacion) {
      _hablando = false;
      _diagnostico('stop confirmed operation=$operacion');
    }
  }

  @override
  Future<void> liberar() async {
    try {
      await detener();
    } catch (_) {
      _diagnostico('dispose stop not confirmed');
    }
  }

  void _limpiarCallbacks() {
    _vigilancia?.cancel();
    _vigilancia = null;
    _onInicio = null;
    _onFin = null;
    _onError = null;
  }

  void _diagnostico(String evento) {
    if (kDebugMode) debugPrint('[CU41Voice][TTS] $evento');
  }

  /// Idioma elegido (`null` mientras no se inicializa).
  String? get idioma => _idioma;
}
