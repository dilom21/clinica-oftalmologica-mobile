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
  FlutterTtsSintesis({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

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
      _tts.setCancelHandler(_alTerminar);
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
      onFin();
      return;
    }

    if (!await inicializar()) {
      onError('voz_no_disponible');
      return;
    }

    await detener();

    _onInicio = onInicio;
    _onFin = onFin;
    _onError = onError;
    _hablando = true;

    try {
      await _tts.speak(limpio);
    } catch (_) {
      _hablando = false;
      _limpiarCallbacks();
      onError('error_sintesis');
    }
  }

  void _alIniciar() {
    _hablando = true;
    _onInicio?.call();
  }

  void _alTerminar() {
    final bool estabaHablando = _hablando;
    _hablando = false;
    _limpiarCallbacks();
    if (estabaHablando) _onFin?.call();
  }

  void _alError(dynamic error) {
    _hablando = false;
    final void Function(String)? callback = _onError;
    _limpiarCallbacks();
    callback?.call('error_sintesis');
  }

  @override
  Future<void> detener() async {
    _hablando = false;
    _limpiarCallbacks();
    try {
      await _tts.stop();
    } catch (_) {
      // El motor ya estaba detenido.
    }
  }

  @override
  Future<void> liberar() async {
    await detener();
  }

  void _limpiarCallbacks() {
    _onInicio = null;
    _onFin = null;
    _onError = null;
  }

  /// Idioma elegido (`null` mientras no se inicializa).
  String? get idioma => _idioma;
}
