import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

import 'seleccion_locale_voz.dart';

/// Resultado de solicitar permiso/verificar el motor de reconocimiento.
enum EstadoPermisoVoz { concedido, denegado, noDisponible }

enum ModoReconocimientoVoz { local, generalAndroid }

/// Solo una respuesta afirmativa permite usar el proveedor general.
Future<ModoReconocimientoVoz?> seleccionarModoReconocimiento({
  required bool localDisponible,
  required Future<bool> Function() solicitarConsentimientoGeneral,
}) async {
  if (localDisponible) return ModoReconocimientoVoz.local;
  return await solicitarConsentimientoGeneral()
      ? ModoReconocimientoVoz.generalAndroid
      : null;
}

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

  /// Confirmación de cierre nativo, no solo ausencia de propiedad del turno.
  /// Consultar después de esperar detener/cancelar antes de un envío manual.
  bool get cierreConfirmado;

  /// `true` solo después de verificar soporte local y de que una captura
  /// on-device arrancó correctamente. Nunca se asume por usar un plugin.
  bool get procesamientoLocalVerificado;

  /// Locale elegido para STT (`es_BO` o alternativa latinoamericana).
  String? get localeUtilizado;
}

/// Adaptador real basado en `speech_to_text`.
///
/// Privacidad:
/// - Prioriza on-device; el proveedor general exige consentimiento afirmativo.
/// - Antes de escuchar comprueba el reconocedor local nativo; si no puede
///   verificarlo, solicita consentimiento adicional. Android 31+ usa un recognizer
///   explícitamente on-device; la comprobación Android es de dispositivo, no
///   de modelo por idioma. Los rechazos de locale se tratan de forma explícita.
/// - No graba archivos de audio ni registra transcripciones.
/// Único propietario del plugin por instancia de SpeechToText. Los listeners de
/// initialize son permanentes; nunca capturan una pantalla ni su consentimiento.
/// Las operaciones nativas se serializan incluso si el llamador deja de esperar
/// por timeout: una liberación pendiente no puede cancelar una captura nueva.
class _CoordinadorSpeech {
  _CoordinadorSpeech(this.speech);

  static final Expando<_CoordinadorSpeech> _instancias = Expando();
  static _CoordinadorSpeech para(SpeechToText speech) =>
      _instancias[speech] ??= _CoordinadorSpeech(speech);

  final SpeechToText speech;
  Future<void>? _cola;
  Future<bool>? _inicializacion;
  SpeechToTextReconocimiento? _propietario;
  int _sesion = 0;
  int? _turnoDespacho;
  bool _cierreFallido = false;
  void Function(String)? _estado;
  void Function(SpeechRecognitionError)? _error;

  Future<T> _serializar<T>(Future<T> Function() operacion) {
    final anterior = _cola;
    final fin = Completer<void>();
    _cola = fin.future;
    final resultado = anterior == null
        ? Future<T>.sync(operacion)
        : anterior.then((_) => operacion());
    void terminar() {
      if (identical(_cola, fin.future)) _cola = null;
      fin.complete();
    }

    unawaited(
      resultado.then<void>(
        (_) => terminar(),
        onError: (Object _, StackTrace _) => terminar(),
      ),
    );
    return resultado;
  }

  Future<bool> inicializar() {
    final pendiente = _inicializacion;
    if (pendiente != null) return pendiente;
    final solicitud = _serializar(
      () => speech.initialize(
        onStatus: (estado) {
          // El plugin solo proporciona el estado global, no un ID nativo.
          // Durante la liberación no existe destinatario.
          final seguro =
              const {'listening', 'notListening', 'done'}.contains(estado)
              ? estado
              : 'other';
          _diagnostico('status native=$seguro');
          _estado?.call(estado);
        },
        onError: (error) {
          _diagnostico('error permanent=${error.permanent}');
          _error?.call(error);
        },
        finalTimeout: Duration.zero,
        debugLogging: false,
        options: <SpeechConfigOption>[SpeechToText.androidNoBluetooth],
      ),
    );
    _inicializacion = solicitud;
    void fallo() {
      if (identical(_inicializacion, solicitud)) _inicializacion = null;
    }

    // 7.5.0 solo fija los listeners tras un initialize exitoso. Un permiso
    // denegado no debe impedir reintentar después de concederlo en Ajustes.
    unawaited(
      solicitud.then<void>((disponible) {
        if (!disponible) fallo();
      }, onError: (Object _, StackTrace _) => fallo()),
    );
    return solicitud;
  }

  bool adquirir(SpeechToTextReconocimiento adaptador) {
    if (_propietario != null && !identical(_propietario, adaptador)) {
      return false;
    }
    _propietario = adaptador;
    return true;
  }

  bool pertenece(SpeechToTextReconocimiento adaptador) =>
      identical(_propietario, adaptador);

  Future<void> escuchar(
    SpeechToTextReconocimiento adaptador,
    int turno,
    Future<void> Function() escuchar,
  ) => _serializar(() async {
    if (!pertenece(adaptador) || turno != adaptador._generacionTurno) return;
    if (_cierreFallido) throw StateError('previous_capture_not_closed');
    final sesion = ++_sesion;
    _turnoDespacho = turno;
    _estado = (estado) {
      if (pertenece(adaptador) &&
          turno == adaptador._generacionTurno &&
          sesion == _sesion) {
        adaptador._alEstado(estado);
      }
    };
    _error = (error) {
      if (pertenece(adaptador) &&
          turno == adaptador._generacionTurno &&
          sesion == _sesion) {
        adaptador._alError(error);
      }
    };
    _diagnostico('listen turn=$turno');
    await escuchar();
  });

  Future<void> detener(SpeechToTextReconocimiento adaptador) =>
      _serializar(() async {
        if (pertenece(adaptador)) await speech.stop();
      });

  Future<void> cancelarCaptura(SpeechToTextReconocimiento adaptador) =>
      _serializar(() async {
        if (pertenece(adaptador)) await speech.cancel();
      });

  Future<void> soltar(
    SpeechToTextReconocimiento adaptador, {
    bool stop = false,
  }) {
    if (!pertenece(adaptador)) return Future<void>.value();
    // Invalidación síncrona ANTES de cualquier await y de una nueva adquisición.
    _propietario = null;
    _estado = null;
    _error = null;
    _turnoDespacho = null;
    ++_sesion;
    return _serializar(() async {
      // Siempre cerrar la captura anterior, aunque listen todavía estuviera
      // arrancando y isListening fuese false cuando se solicitó la salida.
      try {
        if (stop) {
          await speech.stop();
        } else {
          await speech.cancel();
        }
        _cierreFallido = speech.isListening;
      } catch (_) {
        _cierreFallido = true;
        rethrow;
      }
    });
  }

  void _diagnostico(String evento) {
    if (kDebugMode) {
      debugPrint(
        '[CU41Voice][STTCoordinator] $evento session=$_sesion '
        'adapter=${_propietario?._idAdaptador ?? 0} '
        'generation=${_turnoDespacho ?? 0} '
        'dispatch=${_estado != null} listening=${speech.isListening}',
      );
    }
  }
}

class SpeechToTextReconocimiento implements ReconocimientoVoz {
  SpeechToTextReconocimiento({
    SpeechToText? speech,
    this._verificarSoporteLocal,
    this.solicitarConsentimientoGeneral,
  }) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  late final _CoordinadorSpeech _coordinador = _CoordinadorSpeech.para(_speech);
  static int _secuenciaAdaptador = 0;
  final int _idAdaptador = ++_secuenciaAdaptador;
  bool _liberado = false;
  Future<bool> Function()? solicitarConsentimientoGeneral;
  ModoReconocimientoVoz? _modo;
  final Future<bool> Function(String localeId)? _verificarSoporteLocal;
  static const MethodChannel _canalAndroid = MethodChannel(
    'clinica_oftalmologica_mobile/cu41_voice',
  );

  bool _inicializado = false;
  Future<bool>? _inicializacionEnCurso;
  bool _permisoDenegado = false;
  bool _localVerificado = false;
  bool _turnoActivo = false;
  int _generacionTurno = 0;
  String? _localeId;
  List<String> _localesEspanol = localesCandidatosEspanol;
  int _indiceLocale = 0;
  bool? _androidOnDeviceDisponible;

  void Function(String)? _onParcial;
  void Function(String)? _onFinal;
  void Function(String)? _onError;
  void Function()? _onSilencio;
  void Function(double)? _onNivel;
  bool _finalEmitido = false;
  String _ultimoParcial = '';
  Timer? _esperaFinal;
  Timer? _limiteTurno;
  Timer? _estabilidadParcial;
  bool _parcialEstable = false;
  int _repeticionesParcial = 0;
  double _confianzaParcial = -1;
  bool _cerrandoTurno = false;
  int _comprobacionesCierre = 0;
  bool _cierreNotificado = false;
  static const Duration pausaEntrePalabras = Duration(seconds: 4);
  static const Duration duracionEscucha = Duration(seconds: 45);
  static const Duration esperaFinalNativo = Duration(seconds: 2);

  @override
  bool get escuchando => _coordinador.pertenece(this) && _speech.isListening;

  @override
  bool get cierreConfirmado =>
      !_speech.isListening && !_coordinador._cierreFallido;

  @override
  bool get procesamientoLocalVerificado => _localVerificado;

  @override
  String? get localeUtilizado => _localeId;

  @override
  Future<bool> inicializar() {
    if (_liberado) return Future<bool>.value(false);
    if (_inicializado && _speech.isAvailable) {
      _diagnostico('initialize cached isAvailable=true');
      return Future<bool>.value(true);
    }
    final Future<bool>? enCurso = _inicializacionEnCurso;
    if (enCurso != null) {
      _diagnostico('initialize joined in-flight request');
      return enCurso;
    }
    final Future<bool> solicitud = _inicializarUnaVez();
    _inicializacionEnCurso = solicitud;
    return solicitud.whenComplete(() {
      if (identical(_inicializacionEnCurso, solicitud)) {
        _inicializacionEnCurso = null;
      }
    });
  }

  Future<bool> _inicializarUnaVez() async {
    _diagnostico('initialize start isAvailable=${_speech.isAvailable}');
    try {
      await _diagnosticarAndroid();
      _diagnostico('plugin initialize invoke');
      final bool disponible = await _coordinador.inicializar().timeout(
        const Duration(seconds: 15),
      );
      _inicializado = disponible;
      _diagnostico(
        'plugin initialize returned=$disponible '
        'isAvailable=${_speech.isAvailable}',
      );
      if (!disponible) {
        await _diagnosticarPermiso('initialize returned false');
        return false;
      }

      // No bloquear preparación de voz consultando SpeechToText.locales(): en
      // Android algunos RecognitionService no responden al broadcast locales.
      // Los IDs siguientes son candidatos; no se marcan compatibles aquí.
      _localesEspanol = localesCandidatosEspanol;
      _localeId = null;
      _indiceLocale = 0;
      _diagnostico(
        'general availability ready; locale enumeration deferred; '
        'candidateCount=${_localesEspanol.length}',
      );
      return true;
    } on TimeoutException catch (error) {
      _inicializado = false;
      _diagnostico(
        'initialize timeout after=${error.duration?.inSeconds}s '
        'isAvailable=${_speech.isAvailable}',
      );
      await _diagnosticarPermiso('initialize timeout');
      return false;
    } on PlatformException catch (error) {
      _inicializado = false;
      _diagnostico('initialize platformException code=${error.code}');
      await _diagnosticarPermiso('initialize platform exception');
      return false;
    } catch (error) {
      _inicializado = false;
      _diagnostico(
        'initialize exception type=${error.runtimeType} '
        'isAvailable=${_speech.isAvailable}',
      );
      await _diagnosticarPermiso('initialize exception');
      return false;
    }
  }

  Future<void> _diagnosticarAndroid() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final Map<Object?, Object?>? datos = await _canalAndroid
          .invokeMapMethod<Object?, Object?>('diagnoseRecognition')
          .timeout(const Duration(seconds: 5));
      _diagnostico(
        'android probe sdk=${datos?['sdk']} '
        'visibleServices=${datos?['visibleServices']} '
        'generalAvailable=${datos?['generalAvailable']} '
        'onDeviceAvailable=${datos?['onDeviceAvailable']} '
        'defaultServicePresent=${datos?['defaultServicePresent']}',
      );
      _androidOnDeviceDisponible = datos?['onDeviceAvailable'] == true;
    } on TimeoutException {
      _androidOnDeviceDisponible = false;
      _diagnostico('android probe timeout');
    } on PlatformException catch (error) {
      _androidOnDeviceDisponible = false;
      _diagnostico('android probe platformException code=${error.code}');
    } catch (error) {
      _androidOnDeviceDisponible = false;
      _diagnostico('android probe exception type=${error.runtimeType}');
    }
  }

  Future<void> _diagnosticarPermiso(String paso) async {
    try {
      final bool permiso = await _speech.hasPermission.timeout(
        const Duration(seconds: 3),
      );
      _diagnostico('$paso permissionCheck=$permiso');
    } on TimeoutException {
      _diagnostico('$paso permissionCheck=timeout');
    } on PlatformException catch (error) {
      _diagnostico('$paso permissionCheckException code=${error.code}');
    } catch (error) {
      _diagnostico('$paso permissionCheckException type=${error.runtimeType}');
    }
  }

  @override
  Future<EstadoPermisoVoz> solicitarPermiso() async {
    _diagnostico('permission flow start');
    if (!await inicializar()) {
      await _consultarPermisoDespuesDeFallo();
      _diagnostico('initialize failed permissionDenied=$_permisoDenegado');
      return _permisoDenegado
          ? EstadoPermisoVoz.denegado
          : EstadoPermisoVoz.noDisponible;
    }

    try {
      _diagnostico('post-initialize permission check start');
      final bool permiso = await _speech.hasPermission.timeout(
        const Duration(seconds: 3),
      );
      _diagnostico('post-initialize permission check result=$permiso');
      if (!permiso) {
        _permisoDenegado = true;
        return EstadoPermisoVoz.denegado;
      }
    } on TimeoutException {
      _diagnostico('post-initialize permission check timeout');
      return EstadoPermisoVoz.noDisponible;
    } on PlatformException catch (error) {
      _diagnostico(
        'post-initialize permission check platformException code=${error.code}',
      );
      return EstadoPermisoVoz.noDisponible;
    } catch (error) {
      _diagnostico(
        'post-initialize permission check exception type=${error.runtimeType}',
      );
      return EstadoPermisoVoz.noDisponible;
    }

    return EstadoPermisoVoz.concedido;
  }

  Future<void> _consultarPermisoDespuesDeFallo() async {
    try {
      final bool permitido = await _speech.hasPermission.timeout(
        const Duration(seconds: 3),
      );
      _permisoDenegado = !permitido;
      _diagnostico('permission after initialize result=$permitido');
    } on TimeoutException {
      _diagnostico('permission after initialize timeout');
    } on PlatformException catch (error) {
      _diagnostico(
        'permission after initialize platformException code=${error.code}',
      );
    } catch (error) {
      _diagnostico(
        'permission after initialize exception type=${error.runtimeType}',
      );
    }
  }

  Future<bool> _soporteLocal(int preparacion) async {
    _diagnostico(
      'local support check start candidateCount=${_localesEspanol.length}',
    );
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final bool available =
            _androidOnDeviceDisponible ??
            await _consultarSoporteOnDeviceAndroid();
        if (_liberado || preparacion != _generacionTurno) return false;
        _diagnostico('Android on-device deviceCapability=$available');
        final modo =
            _modo ??
            await seleccionarModoReconocimiento(
              localDisponible: available,
              solicitarConsentimientoGeneral: () async =>
                  await solicitarConsentimientoGeneral?.call() ?? false,
            );
        if (_liberado || preparacion != _generacionTurno) return false;
        _modo = modo;
        if (_modo == null) return false;
        if (available) _modo = ModoReconocimientoVoz.local;
        _localesEspanol = _modo == ModoReconocimientoVoz.generalAndroid
            ? const <String>['es-US', 'es-MX', 'es-ES', 'es-BO', 'es-419']
            : localesCandidatosEspanol;
        _indiceLocale = 0;
        _localeId = _localesEspanol[_indiceLocale];
        // La API Android solo confirma capacidad del dispositivo, no el
        // modelo del locale. La sesión on-device validará esta variante.
        return true;
      }

      final comprobar = _verificarSoporteLocal ?? _comprobarSoporteLocalNativo;
      final String? compatible = await seleccionarPrimerLocaleLocal(
        _localesEspanol,
        (String locale) async {
          final bool disponible = await comprobar(locale);
          _diagnostico('on-device locale=$locale disponible=$disponible');
          return disponible;
        },
      );
      if (_liberado || preparacion != _generacionTurno) return false;
      if (compatible == null) return false;
      _localeId = compatible;
      _indiceLocale = _localesEspanol.indexOf(compatible);
      return true;
    } catch (_) {
      // La plataforma no expone la comprobación: no se asume local.
      _diagnostico('local support check failed; refusing microphone start');
      return false;
    }
  }

  Future<bool> _consultarSoporteOnDeviceAndroid() async {
    try {
      final Map<Object?, Object?>? data = await _canalAndroid
          .invokeMapMethod<Object?, Object?>('diagnoseRecognition')
          .timeout(const Duration(seconds: 3));
      _androidOnDeviceDisponible = data?['onDeviceAvailable'] == true;
      return _androidOnDeviceDisponible!;
    } catch (_) {
      _androidOnDeviceDisponible = false;
      return false;
    }
  }

  Future<bool> _comprobarSoporteLocalNativo(String localeId) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Android 31 reports device capability, not per-locale model support.
      return _canalAndroid
          .invokeMapMethod<Object?, Object?>('diagnoseRecognition')
          .then((Map<Object?, Object?>? data) {
            final bool available = data?['onDeviceAvailable'] == true;
            _diagnostico(
              'android local capability locale=$localeId available=$available',
            );
            return available;
          });
    }
    return SpeechToTextPlatform.instance.hasOnDeviceSupport(localeId: localeId);
  }

  @override
  Future<bool> iniciar({
    required void Function(String parcial) onParcial,
    required void Function(String texto) onFinal,
    required void Function(String error) onError,
    required void Function() onSilencio,
    void Function(double nivel)? onNivel,
  }) async {
    if (_liberado) return false;
    if (escuchando) {
      await cancelar();
    }
    if (_liberado || !_coordinador.adquirir(this)) {
      onError('reconocimiento_ocupado');
      return false;
    }

    final int preparacion = ++_generacionTurno;
    bool disponible;
    try {
      disponible = await inicializar().timeout(const Duration(seconds: 22));
    } catch (_) {
      disponible = false;
    }
    if (!disponible) {
      if (preparacion != _generacionTurno) return false;
      _abandonarCaptura();
      onError('motor_no_disponible');
      return false;
    }

    if (preparacion != _generacionTurno) return false;
    if (!await _soporteLocal(preparacion)) {
      if (preparacion != _generacionTurno) return false;
      _abandonarCaptura();
      _localVerificado = false;
      _diagnostico('refusing listen: on-device recognizer unavailable');
      onError('sin_reconocimiento_local');
      return false;
    }
    if (preparacion != _generacionTurno) return false;

    _onParcial = onParcial;
    _onFinal = onFinal;
    _onError = onError;
    _onSilencio = onSilencio;
    _onNivel = onNivel;
    _finalEmitido = false;
    _ultimoParcial = '';
    _cancelarTemporizadores();
    _reiniciarEvidenciaParcial();
    _cierreNotificado = false;
    _turnoActivo = true;
    _generacionTurno++;
    final int generacionIniciada = _generacionTurno;

    try {
      await _escucharLocale(onNivel);
      if (generacionIniciada != _generacionTurno) return false;

      if (!_speech.isListening && !_cierreNotificado && !_finalEmitido) {
        _cancelarTemporizadores();
        _turnoActivo = false;
        _abandonarCaptura();
        onError('micrófono_no_iniciado');
        return false;
      }

      _localVerificado = _modo != ModoReconocimientoVoz.generalAndroid;
      _diagnostico(
        'listen started turn=$_generacionTurno locale=$_localeId local=$_localVerificado',
      );
      return true;
    } catch (_) {
      if (generacionIniciada != _generacionTurno) return false;
      _cancelarTemporizadores();
      _turnoActivo = false;
      _abandonarCaptura();
      onError('error_inicio_reconocimiento');
      return false;
    }
  }

  Future<void> _escucharLocale(void Function(double)? onNivel) async {
    final int generacion = _generacionTurno;
    _diagnostico(
      'listen requested turn=$generacion pauseMs=${pausaEntrePalabras.inMilliseconds}',
    );
    _limiteTurno?.cancel();
    _limiteTurno = Timer(duracionEscucha + esperaFinalNativo, () {
      if (generacion != _generacionTurno || !_turnoActivo) return;
      _diagnostico('turn timeout turn=$generacion');
      _cerrarSinFinal(generacion, permitirRecuperacion: false);
    });
    await _coordinador
        .escuchar(
          this,
          generacion,
          () => _speech.listen(
            onResult: (SpeechRecognitionResult resultado) {
              if (generacion != _generacionTurno ||
                  !_coordinador.pertenece(this)) {
                _diagnostico(
                  'result sourceGeneration=$generacion dispatch=false',
                );
                return;
              }
              _alResultado(resultado);
            },
            onSoundLevelChange: (double nivel) {
              if (generacion == _generacionTurno &&
                  _turnoActivo &&
                  _coordinador.pertenece(this)) {
                onNivel?.call(nivel);
              }
            },
            listenOptions: SpeechListenOptions(
              onDevice: _modo != ModoReconocimientoVoz.generalAndroid,
              partialResults: true,
              listenMode: ListenMode.dictation,
              cancelOnError: true,
              pauseFor: pausaEntrePalabras,
              listenFor: duracionEscucha,
              localeId: _localeId,
            ),
          ),
        )
        .timeout(const Duration(seconds: 10));
  }

  void _alResultado(SpeechRecognitionResult resultado) {
    if (!_turnoActivo) return;

    final String texto = resultado.recognizedWords.trim();
    _diagnostico(
      'result turn=$_generacionTurno final=${resultado.finalResult} '
      'nonEmpty=${texto.isNotEmpty}',
    );
    if (!resultado.finalResult) {
      final String anterior = _normalizarTexto(_ultimoParcial);
      final String nuevo = _normalizarTexto(texto);
      if (nuevo.isNotEmpty && nuevo == anterior) {
        _repeticionesParcial++;
      } else {
        _parcialEstable = false;
        _repeticionesParcial = texto.isEmpty ? 0 : 1;
        _estabilidadParcial?.cancel();
        final int generacion = _generacionTurno;
        _estabilidadParcial = Timer(const Duration(seconds: 1), () {
          if (generacion == _generacionTurno && _turnoActivo) {
            _parcialEstable = true;
          }
        });
      }
      _confianzaParcial = resultado.confidence;
      _ultimoParcial = texto;
      if (texto.isNotEmpty) _onParcial?.call(texto);
      // Los parciales no cierran la sesión ni reinician indefinidamente el
      // presupuesto de cierre. El final nativo tiene prioridad mientras tanto.
      return;
    }

    if (_finalEmitido) return;
    _finalEmitido = true;
    _turnoActivo = false;
    _cancelarTemporizadores();

    if (texto.isEmpty) {
      _onSilencio?.call();
      return;
    }
    // Un interrogativo aislado no es una pregunta administrativa completa.
    // No se impone longitud mínima: «Hola», «Servicios», etc. siguen válidos.
    if (_esFragmentoInterrogativo(texto)) {
      _diagnostico('incomplete final rejected turn=$_generacionTurno');
      _onError?.call('intervencion_incompleta');
      return;
    }
    _onFinal?.call(texto);
  }

  String _normalizarTexto(String texto) => texto
      .toLowerCase()
      .replaceAll(RegExp(r'[¿?¡!.,;:]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  bool _esFragmentoInterrogativo(String texto) => const <String>{
    'qué',
    'que',
    'cuál',
    'cual',
    'cuáles',
    'cuales',
    'quién',
    'quien',
    'quiénes',
    'quienes',
    'cuándo',
    'cuando',
    'dónde',
    'donde',
    'cómo',
    'como',
  }.contains(_normalizarTexto(texto));

  bool get _parcialRecuperable {
    if (_ultimoParcial.isEmpty ||
        !_parcialEstable ||
        _esFragmentoInterrogativo(_ultimoParcial)) {
      return false;
    }
    // Confianza ausente no significa confianza alta. Se exige corroboración
    // (misma hipótesis repetida) o un score explícito alto, además de estabilidad.
    final bool confianzaDisponible = _confianzaParcial > 0;
    if (confianzaDisponible && _confianzaParcial < 0.8) return false;
    return _repeticionesParcial >= 2 || _confianzaParcial >= 0.85;
  }

  void _diagnosticarRecuperacion({
    required bool permitida,
    required bool cierreConfirmado,
  }) {
    // Solo bandas respecto de los umbrales existentes, nunca texto ni score
    // asociado a palabras. La evidencia acústica no prueba completitud semántica.
    final confianza = _confianzaParcial <= 0
        ? 'unavailable'
        : _confianzaParcial < 0.8
        ? 'belowFloor'
        : _confianzaParcial < 0.85
        ? 'belowStandalone'
        : 'atOrAboveStandalone';
    _diagnostico(
      'partial recovery rejected allowed=$permitida stable=$_parcialEstable '
      'corroborated=${_repeticionesParcial >= 2} '
      'confidenceAvailable=${_confianzaParcial > 0} confidenceBand=$confianza '
      'closureNotified=$_cierreNotificado closureConfirmed=$cierreConfirmado '
      'nativeListening=${_speech.isListening} '
      'nonEmpty=${_ultimoParcial.isNotEmpty} '
      'isolatedFragment=${_esFragmentoInterrogativo(_ultimoParcial)}',
    );
  }

  void _alEstado(String estado) {
    final seguro = const {'listening', 'notListening', 'done'}.contains(estado)
        ? estado
        : 'other';
    _diagnostico(
      'status turn=$_generacionTurno state=$seguro active=$_turnoActivo',
    );
    if (!_turnoActivo) return;
    if (estado == SpeechToText.listeningStatus) {
      if (_cerrandoTurno) return;
      _cierreNotificado = false;
      _comprobacionesCierre = 0;
      _esperaFinal?.cancel();
      return;
    }
    if (estado != SpeechToText.doneStatus &&
        estado != SpeechToText.notListeningStatus) {
      return;
    }

    if (_cierreNotificado || _cerrandoTurno) return;
    _cierreNotificado = true;
    _comprobacionesCierre = 0;
    _diagnostico('native session closed; waiting final turn=$_generacionTurno');
    _esperarFinalNativo();
  }

  void _esperarFinalNativo({bool comprobacion = false}) {
    _esperaFinal?.cancel();
    final int generacion = _generacionTurno;
    _esperaFinal = Timer(
      comprobacion ? const Duration(milliseconds: 500) : esperaFinalNativo,
      () {
        if (generacion != _generacionTurno || !_turnoActivo || _finalEmitido) {
          return;
        }
        if (_speech.isListening) {
          _comprobacionesCierre++;
          if (_comprobacionesCierre < 9) {
            _diagnostico(
              'closure pending turn=$generacion check=$_comprobacionesCierre',
            );
            _esperarFinalNativo(comprobacion: true);
          } else {
            // Estado atascado durante 6s desde el cierre: stop acotado y pausa.
            _cerrarSinFinal(generacion, permitirRecuperacion: false);
          }
          return;
        }
        _diagnostico('final missing after closure turn=$generacion');
        _cerrarSinFinal(generacion);
      },
    );
  }

  void _cerrarSinFinal(int generacion, {bool permitirRecuperacion = true}) {
    if (generacion != _generacionTurno || !_turnoActivo || _cerrandoTurno) {
      return;
    }
    _cerrandoTurno = true;
    _cancelarTemporizadores();
    unawaited(_cancelarTurnoSinFinal(generacion, permitirRecuperacion));
  }

  Future<void> _cancelarTurnoSinFinal(
    int generacion,
    bool permitirRecuperacion,
  ) async {
    try {
      // stop permite que el motor entregue su final pendiente; cancel lo
      // descartaría. No producir un final sintético (finalTimeout sigue en cero).
      await _coordinador.detener(this).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (generacion != _generacionTurno || !_turnoActivo) return;
      if (_speech.isListening) {
        throw StateError('recognizer_stop_not_confirmed');
      }
    } catch (_) {
      if (generacion == _generacionTurno && _turnoActivo) {
        _diagnosticarRecuperacion(
          permitida: permitirRecuperacion,
          cierreConfirmado: false,
        );
        _cancelarTemporizadores();
        _turnoActivo = false;
        _onError?.call('intervencion_sin_final');
      }
      return;
    }
    if (generacion != _generacionTurno || !_turnoActivo) return;
    _cancelarTemporizadores();
    _turnoActivo = false;
    if (permitirRecuperacion && _cierreNotificado && _parcialRecuperable) {
      _finalEmitido = true;
      _diagnostico(
        'stable partial recovered after confirmed closure turn=$generacion',
      );
      _onFinal?.call(_ultimoParcial);
      return;
    }
    if (_ultimoParcial.isEmpty) {
      _diagnostico('silence closure turn=$generacion');
      _onSilencio?.call();
    } else {
      _diagnosticarRecuperacion(
        permitida: permitirRecuperacion,
        cierreConfirmado: true,
      );
      // Hipótesis incierta: el controlador ofrece revisión, nunca envío directo.
      _onError?.call('intervencion_sin_final');
    }
  }

  void _cancelarTemporizadores() {
    _esperaFinal?.cancel();
    _limiteTurno?.cancel();
    _estabilidadParcial?.cancel();
    _estabilidadParcial = null;
    _esperaFinal = null;
    _limiteTurno = null;
  }

  void _reiniciarEvidenciaParcial() {
    _parcialEstable = false;
    _repeticionesParcial = 0;
    _confianzaParcial = -1;
    _cerrandoTurno = false;
    _comprobacionesCierre = 0;
  }

  void _alError(SpeechRecognitionError error) {
    final String mensaje = error.errorMsg.toLowerCase();
    _diagnostico(
      'native error turn=$_generacionTurno permanent=${error.permanent} '
      'languageRejected=${_esErrorLocale(mensaje)}',
    );
    if (mensaje.contains('permission') ||
        mensaje.contains('not-allowed') ||
        mensaje.contains('denied')) {
      _permisoDenegado = true;
    }

    if (!_turnoActivo) return;
    if (mensaje == 'error_no_match' || mensaje == 'error_speech_timeout') {
      // Algunos proveedores entregan parciales útiles y terminan con no_match.
      // Dejar margen al final pendiente y comprobar el cierre, sin descartar.
      if (!_cierreNotificado && !_cerrandoTurno) {
        _cierreNotificado = true;
        _comprobacionesCierre = 0;
        _esperarFinalNativo();
      }
      return;
    }
    _cancelarTemporizadores();
    if (_esErrorLocale(mensaje) && _indiceLocale + 1 < _localesEspanol.length) {
      unawaited(_probarSiguienteLocale());
      return;
    }
    if (_esErrorLocale(mensaje)) {
      _turnoActivo = false;
      _onError?.call('error_idioma_local_no_disponible');
      return;
    }
    _turnoActivo = false;
    _onError?.call(error.errorMsg);
  }

  Future<void> _probarSiguienteLocale() async {
    int generacion = _generacionTurno;
    _turnoActivo = false;
    try {
      await _coordinador.cancelarCaptura(this);
      // El callback nativo de error llega antes de que el servicio libere la
      // sesión en algunos motores. Esta pausa corta permite un reinicio acotado.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (generacion != _generacionTurno || !_activaParaCallbacks) return;
      _indiceLocale++;
      _localeId = _localesEspanol[_indiceLocale];
      _generacionTurno++;
      generacion = _generacionTurno;
      _ultimoParcial = '';
      _reiniciarEvidenciaParcial();
      _cierreNotificado = false;
      _turnoActivo = true;
      _diagnostico('retry turn=$generacion locale=$_localeId');
      await _escucharLocale(_onNivel);
      if (!_speech.isListening) {
        throw StateError('recognizer_not_started');
      }
    } catch (_) {
      if (generacion != _generacionTurno) return;
      _cancelarTemporizadores();
      _turnoActivo = false;
      _localVerificado = false;
      _onError?.call('error_idioma_local_no_disponible');
    }
  }

  bool get _activaParaCallbacks => _onError != null;

  bool _esErrorLocale(String mensaje) =>
      mensaje.contains('language_not_supported') ||
      mensaje.contains('language_unavailable');

  void _diagnostico(String detalle) {
    if (kDebugMode) {
      debugPrint(
        '[CU41Voice][STT] adapter=$_idAdaptador '
        'generation=$_generacionTurno $detalle',
      );
    }
  }

  void _abandonarCaptura() {
    _limpiarCallbacks();
    unawaited(
      _coordinador.soltar(this).catchError((Object _) {
        _diagnostico('capture cleanup failed');
      }),
    );
  }

  @override
  Future<void> detener() async {
    _generacionTurno++;
    _turnoActivo = false;
    _limpiarCallbacks();
    try {
      await _coordinador.soltar(this, stop: true);
    } catch (_) {
      // El micrófono ya estaba detenido.
    }
  }

  @override
  Future<void> cancelar() async {
    _generacionTurno++;
    _turnoActivo = false;
    _modo = null;
    _localVerificado = false;
    _limpiarCallbacks();
    try {
      await _coordinador.soltar(this);
    } catch (_) {
      // El micrófono ya estaba detenido.
    }
  }

  @override
  Future<void> liberar() async {
    _liberado = true;
    solicitarConsentimientoGeneral = null;
    await cancelar();
  }

  void _limpiarCallbacks() {
    _cancelarTemporizadores();
    _onParcial = null;
    _onFinal = null;
    _onError = null;
    _onSilencio = null;
    _onNivel = null;
    _ultimoParcial = '';
  }
}
