import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../controllers/chat_voz_controller.dart';
import '../controllers/chatbot_controller.dart';
import '../models/chatbot_models.dart';
import '../services/voz/reconocimiento_voz.dart';
import '../services/voz/sintesis_voz.dart';
import '../widgets/chatbot_ui.dart';
import '../widgets/esfera_voz.dart';

/// Cuarta pantalla del CU41: asistente de voz inmersivo.
///
/// Conversación natural por turnos (no full-duplex): escucha, envía, espera,
/// reproduce, y vuelve a escuchar cuando TTS terminó realmente. El micrófono
/// y la reproducción nunca están activos al mismo tiempo.
class ChatVozPage extends StatefulWidget {
  const ChatVozPage({
    super.key,
    required this.conversacion,
    this.clinica,
    this.vozController,
    this.mensajeParaEscuchar,
    this.pedirConsentimiento = true,
    this.iniciarAlAbrir = true,
    this.reproduccionAutomatica = true,
    this.onSesionInvalida,
  });

  final ChatbotController conversacion;
  final ClinicaSesion? clinica;

  /// Controlador inyectable en pruebas. Si es `null`, la página crea los
  /// adaptadores de sesión STT/TTS y los libera al cerrarse. El plugin STT y
  /// sus listeners globales pertenecen al coordinador compartido de la app.
  final ChatVozController? vozController;

  /// Respuesta pública que se desea escuchar desde el chat escrito.
  final MensajeChat? mensajeParaEscuchar;

  final bool pedirConsentimiento;
  final bool iniciarAlAbrir;
  final bool reproduccionAutomatica;
  final Future<void> Function()? onSesionInvalida;

  @override
  State<ChatVozPage> createState() => _ChatVozPageState();
}

class _ChatVozPageState extends State<ChatVozPage> with WidgetsBindingObserver {
  late final bool _propio = widget.vozController == null;
  late final ChatVozController _voz =
      widget.vozController ??
      ChatVozController(
        conversacion: widget.conversacion,
        reconocimiento: SpeechToTextReconocimiento(
          solicitarConsentimientoGeneral: _autorizarReconocimientoGeneral,
        ),
        sintesis: FlutterTtsSintesis(),
        reproduccionAutomatica: widget.reproduccionAutomatica,
      );

  bool _consentimientoMostrado = false;
  bool _cerrando = false;

  Future<bool> _autorizarReconocimientoGeneral() async {
    if (!mounted ||
        _cerrando ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    final bool? autorizado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Usar reconocimiento del dispositivo'),
        content: const Text(
          'Android no ofrece reconocimiento exclusivamente local. Si autorizas '
          'el servicio general, el audio podría enviarse al proveedor de '
          'reconocimiento configurado en tu dispositivo para transcribirlo. '
          'Puede requerir conexión a Internet. La aplicación no guarda archivos '
          'de audio; el proveedor aplica sus propias condiciones de privacidad. '
          'El texto reconocido se enviará al asistente de la clínica. '
          'No dictes información clínica sensible. La autorización dura solo '
          'esta sesión de voz.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Usar el chat escrito'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Autorizo el servicio general'),
          ),
        ],
      ),
    );
    return autorizado == true &&
        mounted &&
        !_cerrando &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _iniciarFlujo();
    });
  }

  Future<void> _iniciarFlujo() async {
    if (_consentimientoMostrado) return;
    _consentimientoMostrado = true;

    if (widget.pedirConsentimiento) {
      final bool aceptado = await _mostrarConsentimiento();
      if (!mounted) return;
      if (!aceptado) {
        await _voz.salir();
        if (!mounted) return;
        Navigator.of(context).maybePop();
        return;
      }
    }

    final MensajeChat? mensaje = widget.mensajeParaEscuchar;
    if (mensaje != null) {
      await _voz.reproducirMensaje(mensaje);
      return;
    }

    if (widget.iniciarAlAbrir) {
      await _voz.activar();
    }
  }

  Future<bool> _mostrarConsentimiento() async {
    final bool escucharSolo = widget.mensajeParaEscuchar != null;
    final bool? aceptado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          escucharSolo ? 'Escuchar la respuesta' : 'Conversar por voz',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!escucharSolo) ...<Widget>[
                const Text(
                  'El micrófono se usará para transcribir lo que digas y '
                  'enviarlo al asistente administrativo. Se prioriza el '
                  'reconocimiento local. Si no está disponible, te pediremos '
                  'otra autorización antes de usar el proveedor general, que '
                  'podría recibir el audio. La app no guarda archivos de audio.',
                  style: TextStyle(fontSize: 13.5, height: 1.45),
                ),
                const SizedBox(height: 10),
                const Text(
                  'No dictes contraseñas, documentos, datos de pago ni '
                  'información clínica sensible.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const Text(
                'El asistente es administrativo: no diagnostica, no prescribe '
                'ni interpreta exámenes. La síntesis de voz puede depender del '
                'motor instalado en el dispositivo; por seguridad, la '
                'información privada solo se lee si el motor local puede '
                'verificarse.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Usar el chat escrito'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(escucharSolo ? 'Reproducir' : 'Activar voz'),
          ),
        ],
      ),
    );
    return aceptado == true;
  }

  Future<void> _mostrarPrivacidad() async {
    final bool estabaActiva = _voz.activa && _voz.estado != EstadoVoz.inactivo;
    if (estabaActiva) await _voz.pausar();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Privacidad y alcance'),
        content: const SingleChildScrollView(
          child: Text(
            'El asistente responde consultas administrativas de la clínica: '
            'servicios, profesionales, disponibilidad y tus citas. No realiza '
            'diagnósticos ni sustituye a un profesional de salud.\n\n'
            'El micrófono solo se activa cuando lo pides y se detiene antes '
            'de reproducir una respuesta. Se prioriza el reconocimiento local. '
            'El servicio general solo se usa con tu autorización explícita: '
            'podría enviar audio al proveedor del dispositivo y necesitar '
            'Internet. La app no guarda audio. Puedes rechazarlo y continuar '
            'por escrito. El texto final se envía al asistente.\n\n'
            'La síntesis de voz usa el motor del dispositivo. Cuando puede '
            'verificarse una voz local instalada, el asistente puede leer la '
            'respuesta; si no puede verificarse, la información privada se '
            'muestra solo por escrito.\n\n'
            'La conversación vive solo en memoria y se elimina al cerrar '
            'sesión, al iniciar una conversación nueva o al expirar.',
            style: TextStyle(fontSize: 13.5, height: 1.45),
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarFinalizar() async {
    final bool estabaActiva = _voz.activa && _voz.estado != EstadoVoz.inactivo;
    if (estabaActiva) await _voz.pausar();

    if (!mounted) return;
    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Finalizar la conversación?'),
        content: const Text(
          'Se cerrará esta conversación y su contexto temporal. Si vuelves a '
          'hablar, el asistente comenzará desde cero.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar conversando'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ChatbotColores.rojo),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmado == true) {
      await _voz.finalizarConversacion();
      return;
    }
    if (estabaActiva) {
      await _voz.reanudar();
    }
  }

  Future<void> _volverAlChat() async {
    if (_cerrando) return;
    _cerrando = true;
    await _voz.salir();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _voz.reanudarCicloDeVida();
      return;
    }
    if (state == AppLifecycleState.inactive) {
      // Android/MIUI reports inactive while permission sheets and transient
      // system UI are shown; paused/hidden below indicate an actual departure.
      _voz.focoTemporalPerdido();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _voz.suspenderPorCicloDeVida();
    }
  }

  @override
  void dispose() {
    _cerrando = true;
    WidgetsBinding.instance.removeObserver(this);
    if (_propio) {
      _voz.dispose();
    } else {
      _voz.alOcultarPantalla();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _volverAlChat();
      },
      child: Scaffold(
        backgroundColor: ChatbotColores.nocturno,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                ChatbotColores.nocturno,
                ChatbotColores.nocturnoMedio,
                Color(0xFF06172D),
              ],
              stops: <double>[0, 0.55, 1],
            ),
          ),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _voz,
              builder: (BuildContext context, Widget? child) {
                return _contenido(context);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    final Size pantalla = MediaQuery.sizeOf(context);
    final double diametro = math.min(
      258,
      math.max(168, math.min(pantalla.width * 0.66, pantalla.height * 0.32)),
    );
    final List<MensajeChat> mensajes = widget.conversacion.mensajes;
    final MensajeChat? ultimaConTarjetas = _ultimaConTarjetas(mensajes);
    final pendiente = _voz.transcripcionPendiente;
    final revision = _voz.revisionTranscripcion;

    return Column(
      children: <Widget>[
        _encabezado(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0.0, pantalla.height * 0.52),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ValueListenableBuilder<double>(
                    valueListenable: _voz.nivel,
                    builder: (BuildContext context, double nivel, _) {
                      return EsferaVoz(
                        estado: _voz.estado,
                        nivelAudio: nivel,
                        size: diametro,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: _voz.estado != EstadoVoz.respondiendo,
                    label: '${_voz.textoEstado}. ${_voz.textoSubtitulo}',
                    child: Column(
                      children: <Widget>[
                        Text(
                          _voz.textoEstado,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ChatbotColores.vozTexto,
                            fontSize: 24,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _voz.textoSubtitulo,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ChatbotColores.vozTextoSuave,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pendiente != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _RevisionTranscripcion(
                      key: ValueKey(revision),
                      texto: pendiente,
                      habilitada: _voz.puedeConfirmarTranscripcion,
                      onConfirmar: (texto) {
                        FocusScope.of(context).unfocus();
                        _voz.confirmarTranscripcion(texto, revision: revision);
                      },
                      onRepetir: () {
                        FocusScope.of(context).unfocus();
                        _voz.repetirIntervencion(revision: revision);
                      },
                    ),
                  ] else if (_voz.transcripcion.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    _Transcripcion(texto: _voz.transcripcion),
                  ],
                  if (_voz.subtitulo.isNotEmpty &&
                      _voz.estado != EstadoVoz.escuchando) ...<Widget>[
                    const SizedBox(height: 14),
                    _SubtituloRespuesta(
                      texto: _voz.subtitulo,
                      onAbrirChat: _volverAlChat,
                    ),
                  ],
                  if (_voz.aviso != null &&
                      _voz.estado != EstadoVoz.escuchando &&
                      !(_voz.estado == EstadoVoz.pausado &&
                          _voz.aviso!.contains(
                            'aplicación dejó de',
                          ))) ...<Widget>[
                    const SizedBox(height: 12),
                    _AvisoVoz(
                      texto: _voz.aviso!,
                      error: _voz.estado == EstadoVoz.error,
                    ),
                  ],
                  if (ultimaConTarjetas != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _AccesoRespuesta(
                      cantidad: ultimaConTarjetas.tarjetas.length,
                      onTap: _volverAlChat,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        _controles(),
        const SizedBox(height: 4),
        _pie(),
        const SizedBox(height: 8),
      ],
    );
  }

  MensajeChat? _ultimaConTarjetas(List<MensajeChat> mensajes) {
    final RespuestaChatbot? respuesta = _voz.respuestaActual;
    if (respuesta == null) return null;
    for (int i = mensajes.length - 1; i >= 0; i--) {
      if (mensajes[i].rol == RolMensajeChat.asistente &&
          mensajes[i].tarjetas.isNotEmpty &&
          mensajes[i].texto == respuesta.respuesta) {
        return mensajes[i];
      }
    }
    return null;
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Volver al chat escrito',
            onPressed: _volverAlChat,
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: ChatbotColores.vozTexto,
              size: 20,
            ),
          ),
          const AsistenteAvatar(size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Asistente de voz',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ChatbotColores.vozTexto,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.clinica?.etiqueta ?? 'Conversación administrativa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChatbotColores.vozTextoSuave,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Privacidad y alcance',
            onPressed: _mostrarPrivacidad,
            icon: const Icon(
              Icons.info_outline,
              color: ChatbotColores.vozTextoSuave,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controles() {
    final bool escuchando =
        _voz.estado == EstadoVoz.escuchando ||
        _voz.estado == EstadoVoz.procesando ||
        _voz.estado == EstadoVoz.revisandoTranscripcion;
    final bool respondiendo = _voz.estado == EstadoVoz.respondiendo;
    final bool pausado =
        _voz.estado == EstadoVoz.pausado ||
        _voz.estado == EstadoVoz.error ||
        _voz.estado == EstadoVoz.inactivo;
    final bool finalizado = _voz.estado == EstadoVoz.finalizado;

    final List<Widget> controles = <Widget>[
      _ControlVoz(
        icono: escuchando ? Icons.pause_rounded : Icons.mic_none_rounded,
        etiqueta: escuchando
            ? 'Pausar'
            : pausado
            ? 'Continuar'
            : 'Micrófono',
        tooltip: escuchando ? 'Pausar el micrófono' : 'Activar el micrófono',
        onTap: finalizado
            ? null
            : escuchando
            ? _voz.pausar
            : pausado
            ? _voz.reanudar
            : _voz.activar,
        destacado: !escuchando && pausado,
      ),
      _ControlVoz(
        icono: Icons.volume_off_outlined,
        etiqueta: 'Detener',
        tooltip: 'Detener la respuesta hablada',
        onTap: respondiendo ? _voz.detenerRespuesta : null,
      ),
      _ControlVoz(
        icono: Icons.stop_circle_outlined,
        etiqueta: 'Finalizar',
        tooltip: 'Finalizar la conversación',
        onTap: finalizado ? null : _confirmarFinalizar,
        peligro: true,
      ),
    ];

    final double escala = MediaQuery.textScalerOf(context).scale(12) / 12;
    if (escala > 1.3) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints limites) {
            final double ancho = (limites.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              children: <Widget>[
                for (final Widget control in controles)
                  SizedBox(width: ancho, child: control),
              ],
            );
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: controles,
      ),
    );
  }

  Widget _pie() {
    final bool finalizado = _voz.estado == EstadoVoz.finalizado;
    final bool sinVoz =
        _voz.estado == EstadoVoz.noDisponible || _voz.estado == EstadoVoz.error;

    if (finalizado || sinVoz) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: _volverAlChat,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Volver al chat escrito'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: ChatbotColores.nocturno,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
    }

    return TextButton.icon(
      onPressed: _volverAlChat,
      icon: const Icon(
        Icons.keyboard_outlined,
        size: 17,
        color: ChatbotColores.vozTextoSuave,
      ),
      label: const Text(
        'Volver al chat escrito',
        style: TextStyle(
          color: ChatbotColores.vozTextoSuave,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ControlVoz extends StatelessWidget {
  const _ControlVoz({
    required this.icono,
    required this.etiqueta,
    required this.tooltip,
    required this.onTap,
    this.destacado = false,
    this.peligro = false,
  });

  final IconData icono;
  final String etiqueta;
  final String tooltip;
  final Future<void> Function()? onTap;
  final bool destacado;
  final bool peligro;

  @override
  Widget build(BuildContext context) {
    final bool activo = onTap != null;
    final Color fondo = !activo
        ? Colors.white.withValues(alpha: 0.08)
        : peligro
        ? ChatbotColores.rojo
        : destacado
        ? Colors.white
        : Colors.white.withValues(alpha: 0.14);
    final Color colorIcono = !activo
        ? Colors.white38
        : destacado && !peligro
        ? ChatbotColores.azulProfundo
        : Colors.white;

    return Semantics(
      button: true,
      enabled: activo,
      label: tooltip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Material(
                color: fondo,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: activo ? () => onTap!() : null,
                  child: Icon(icono, size: 24, color: colorIcono),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: activo ? ChatbotColores.vozTextoSuave : Colors.white30,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevisionTranscripcion extends StatefulWidget {
  const _RevisionTranscripcion({
    super.key,
    required this.texto,
    required this.habilitada,
    required this.onConfirmar,
    required this.onRepetir,
  });

  final String texto;
  final bool habilitada;
  final ValueChanged<String> onConfirmar;
  final VoidCallback onRepetir;

  @override
  State<_RevisionTranscripcion> createState() => _RevisionTranscripcionState();
}

class _RevisionTranscripcionState extends State<_RevisionTranscripcion> {
  late final TextEditingController _editor = TextEditingController(
    text: widget.texto,
  );

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ChatbotColores.nocturnoMedio,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChatbotColores.vozTextoSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const ValueKey('revision-transcripcion'),
            controller: _editor,
            enabled: widget.habilitada,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            style: const TextStyle(color: ChatbotColores.vozTexto),
            decoration: const InputDecoration(
              labelText: 'Texto reconocido: puedes editarlo',
              labelStyle: TextStyle(color: ChatbotColores.vozTextoSuave),
              counterStyle: TextStyle(color: ChatbotColores.vozTextoSuave),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (!widget.habilitada)
            const Text(
              'Cerrando el micrófono...',
              style: TextStyle(color: ChatbotColores.vozTextoSuave),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: widget.habilitada && _editor.text.trim().isNotEmpty
                ? () => widget.onConfirmar(_editor.text)
                : null,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Confirmar y enviar'),
          ),
          TextButton.icon(
            onPressed: widget.habilitada ? widget.onRepetir : null,
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Repetir intervención'),
          ),
        ],
      ),
    );
  }
}

class _Transcripcion extends StatelessWidget {
  const _Transcripcion({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.graphic_eq, size: 18, color: ChatbotColores.celeste),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: ChatbotColores.vozTexto,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtituloRespuesta extends StatelessWidget {
  const _SubtituloRespuesta({required this.texto, required this.onAbrirChat});

  final String texto;
  final VoidCallback onAbrirChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: ChatbotColores.nocturnoSuave.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(
                Icons.subtitles_outlined,
                size: 15,
                color: ChatbotColores.celeste,
              ),
              SizedBox(width: 6),
              Text(
                'RESPUESTA',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w800,
                  color: ChatbotColores.celeste,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ChatbotColores.vozTexto,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          if (texto.length > 150) ...<Widget>[
            const SizedBox(height: 2),
            TextButton(
              onPressed: onAbrirChat,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
              ),
              child: const Text('Leer completa en el chat'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AvisoVoz extends StatelessWidget {
  const _AvisoVoz({required this.texto, required this.error});

  final String texto;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: error
            ? ChatbotColores.rojo.withValues(alpha: 0.22)
            : ChatbotColores.celeste.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (error ? ChatbotColores.rojo : ChatbotColores.celeste)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: error ? const Color(0xFFFFD7D7) : ChatbotColores.vozTexto,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}

class _AccesoRespuesta extends StatelessWidget {
  const _AccesoRespuesta({required this.cantidad, required this.onTap});

  final int cantidad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
        label: Text(
          cantidad == 1
              ? 'Ver respuesta y tarjeta'
              : 'Ver respuesta y $cantidad tarjetas',
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: ChatbotColores.azulProfundo,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }
}
