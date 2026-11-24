import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../../catalogo/pages/catalogo_page.dart';
import '../../catalogo/services/catalogo_service.dart';
import '../../citas/models/agenda_models.dart';
import '../../citas/models/cita_models.dart';
import '../../citas/models/preseleccion_cita.dart';
import '../../citas/pages/cita_detalle_page.dart';
import '../../citas/services/agenda_service.dart';
import '../../perfil_paciente/services/paciente_service.dart';
import '../controllers/chatbot_controller.dart';
import '../models/chatbot_models.dart';
import '../widgets/chat_bienvenida.dart';
import '../widgets/chat_compositor.dart';
import '../widgets/chat_conversacion.dart';
import '../widgets/chat_encabezado.dart';
import '../widgets/chatbot_ui.dart';
import '../widgets/tarjetas_chatbot.dart';
import 'chat_agendamiento_page.dart';
import 'chat_citas_page.dart';
import 'chat_voz_page.dart';

/// Pantalla dedicada del asistente virtual (CU41).
///
/// Contiene la bienvenida, las sugerencias, la conversación activa, el
/// compositor y las tarjetas dinámicas. Comparte el [ChatbotController] con la
/// experiencia de voz, de modo que texto y voz usan el mismo UUID e historial.
class ChatbotPage extends StatefulWidget {
  const ChatbotPage({
    super.key,
    this.controller,
    this.clinica,
    this.onSesionInvalida,
    this.onCitasCambiadas,
    this.agendaService,
    this.pacienteService,
    this.catalogoService,
    this.reproduccionAutomatica = true,
    this.abrirEnVoz = false,
  });

  /// Controlador compartido. Si es `null`, la página crea uno propio y lo
  /// libera al cerrarse (útil en pruebas y navegación aislada).
  final ChatbotController? controller;

  final ClinicaSesion? clinica;
  final Future<void> Function()? onSesionInvalida;
  final VoidCallback? onCitasCambiadas;
  final AgendaService? agendaService;
  final PacienteService? pacienteService;
  final CatalogoService? catalogoService;

  /// Preferencia básica de voz (no persiste entre sesiones).
  final bool reproduccionAutomatica;

  /// Abre directamente la experiencia de voz (acceso "Hablar" de Inicio),
  /// manteniendo el chat escrito debajo para volver sin perder la conversación.
  final bool abrirEnVoz;

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  late final bool _propio = widget.controller == null;
  late final ChatbotController _chatbot =
      widget.controller ??
      ChatbotController(alSesionInvalida: widget.onSesionInvalida);

  late final AgendaService _agenda = widget.agendaService ?? AgendaService();

  final TextEditingController _texto = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _foco = FocusNode();
  final Map<int, String> _profesionales = <int, String>{};
  final Set<int> _profesionalesSolicitados = <int>{};

  bool _cercaDelFondo = true;
  bool _abriendoPropuesta = false;
  int _ultimoConteo = 0;
  late bool _reproduccionAutomatica = widget.reproduccionAutomatica;

  @override
  void initState() {
    super.initState();
    _ultimoConteo = _chatbot.mensajes.length;
    _chatbot.addListener(_alCambiarConversacion);
    _scroll.addListener(_alDesplazar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatbot.verificarExpiracion();
      unawaited(_resolverProfesionales());
      if (widget.abrirEnVoz) {
        unawaited(_abrirVoz());
      }
    });
  }

  @override
  void dispose() {
    _chatbot.removeListener(_alCambiarConversacion);
    _scroll.removeListener(_alDesplazar);
    _texto.dispose();
    _scroll.dispose();
    _foco.dispose();
    if (_propio) _chatbot.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Reacción a cambios de conversación
  // -------------------------------------------------------------------

  void _alCambiarConversacion() {
    if (!mounted) return;

    final int conteo = _chatbot.mensajes.length;
    if (conteo != _ultimoConteo) {
      final bool crecio = conteo > _ultimoConteo;
      _ultimoConteo = conteo;
      if (crecio && _cercaDelFondo) _programarScroll();
    }

    unawaited(_resolverProfesionales());
  }

  void _alDesplazar() {
    if (!_scroll.hasClients) return;
    final double restante = _scroll.position.maxScrollExtent - _scroll.offset;
    final bool cerca = restante < 90;
    if (cerca != _cercaDelFondo) {
      _cercaDelFondo = cerca;
    }
  }

  void _programarScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  /// Resuelve nombres reales de oftalmólogos para las tarjetas de citas.
  ///
  /// Es información complementaria: si falla, la tarjeta muestra "Profesional
  /// asignado" y no se inventa ningún nombre.
  Future<void> _resolverProfesionales() async {
    final Set<int> ids = <int>{
      for (final MensajeChat mensaje in _chatbot.mensajes)
        for (final TarjetaChatbot tarjeta in mensaje.tarjetas)
          if (tarjeta is TarjetaCitasPropias)
            for (final CitaPropiaChat cita in tarjeta.citas)
              if (cita.oftalmologoId != null &&
                  cita.oftalmologoId! > 0 &&
                  !_profesionales.containsKey(cita.oftalmologoId))
                cita.oftalmologoId!,
    };

    ids.removeAll(_profesionalesSolicitados);
    if (ids.isEmpty) return;
    _profesionalesSolicitados.addAll(ids);

    try {
      final List<OftalmologoAgenda> lista = await _agenda.listarOftalmologos();
      if (!mounted) return;
      setState(() {
        for (final OftalmologoAgenda oftalmologo in lista) {
          final String nombre = oftalmologo.nombreCompleto.trim();
          if (nombre.isNotEmpty) {
            _profesionales[oftalmologo.id] = nombre;
          }
        }
      });
    } on AgendaException catch (error) {
      if (error.statusCode == 401) {
        final Future<void> Function()? callback = widget.onSesionInvalida;
        if (callback != null) unawaited(callback());
      }
      // Dato complementario. Se permite reintentar en una próxima respuesta.
      _profesionalesSolicitados.removeAll(ids);
    } catch (_) {
      // Dato complementario. Se permite reintentar en una próxima respuesta.
      _profesionalesSolicitados.removeAll(ids);
    }
  }

  // -------------------------------------------------------------------
  // Envío de mensajes
  // -------------------------------------------------------------------

  Future<void> _enviarTexto(String texto) async {
    final String limpio = texto.trim();
    if (limpio.isEmpty || !_chatbot.puedeEnviar) return;

    _texto.clear();
    _cercaDelFondo = true;
    _programarScroll();

    final MensajeChat? respuesta = await _chatbot.enviar(limpio);
    if (!mounted) return;

    if (respuesta == null && _chatbot.errorGeneral != null) {
      // El detalle ya se muestra como mensaje local en la conversación.
      _programarScroll();
    }
  }

  Future<void> _enviarCompositor() async {
    final String texto = _texto.text.trim();
    if (texto.isEmpty) return;
    await _enviarTexto(texto);
  }

  Future<void> _reintentar() async {
    if (!_chatbot.puedeReintentar) return;
    await _chatbot.reintentarUltimo();
    if (!mounted) return;
    _programarScroll();
  }

  Future<void> _nuevaConversacion() async {
    if (_chatbot.enviando) {
      _avisar('Espera a que el asistente termine de responder.');
      return;
    }

    final bool tieneMensajes = _chatbot.mensajes.isNotEmpty;
    if (tieneMensajes) {
      final bool? confirmado = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Nueva conversación'),
          content: const Text(
            'Se cerrará la conversación actual y se borrarán los mensajes y '
            'tarjetas temporales. Esta acción no se puede deshacer.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Empezar de nuevo'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;
    }

    await _chatbot.nuevaConversacion();
    if (!mounted) return;
    _texto.clear();
    _foco.unfocus();
    setState(() {});
  }

  // -------------------------------------------------------------------
  // Navegación a módulos existentes
  // -------------------------------------------------------------------

  Future<void> _abrirVoz({MensajeChat? mensaje}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatVozPage(
          conversacion: _chatbot,
          clinica: widget.clinica,
          mensajeParaEscuchar: mensaje,
          reproduccionAutomatica: _reproduccionAutomatica,
          onSesionInvalida: widget.onSesionInvalida,
        ),
      ),
    );
    if (!mounted) return;
    _programarScroll();
  }

  void _abrirCatalogo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogoPage(
          service: widget.catalogoService,
          clinica: widget.clinica,
          onSesionInvalida: () => widget.onSesionInvalida?.call(),
        ),
      ),
    );
  }

  Future<void> _abrirAgendamiento({
    PreseleccionCita? preseleccion,
    Future<bool> Function()? validarContexto,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatAgendamientoPage(
          preseleccion: preseleccion,
          validarContexto: validarContexto,
          clinica: widget.clinica,
          agendaService: widget.agendaService,
          pacienteService: widget.pacienteService,
          onSesionInvalida: widget.onSesionInvalida,
          onCitasCambiadas: _alCambiarCitas,
        ),
      ),
    );
  }

  void _abrirMisCitas() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatCitasPage(
          clinica: widget.clinica,
          agendaService: widget.agendaService,
          pacienteService: widget.pacienteService,
          onSesionInvalida: widget.onSesionInvalida,
          onCitasCambiadas: _alCambiarCitas,
        ),
      ),
    );
  }

  Future<void> _abrirDetalleCita(int citaId) async {
    final bool? cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CitaDetallePage(
          citaId: citaId,
          clinica: widget.clinica,
          agendaService: widget.agendaService,
          onSesionInvalida: widget.onSesionInvalida,
        ),
      ),
    );
    if (cambio == true && mounted) _alCambiarCitas();
  }

  void _alCambiarCitas() {
    widget.onCitasCambiadas?.call();
    _chatbot.invalidarTarjetas(
      evento:
          'La información de tus citas cambió. Consulta "Mis citas" para ver '
          'el estado real antes de continuar.',
    );
    if (mounted) _programarScroll();
  }

  void _seleccionarHorario(
    TarjetaDisponibilidad disponibilidad,
    IntervaloChat intervalo,
  ) {
    final String profesional =
        disponibilidad.profesional?.nombre ??
        'el profesional de la disponibilidad mostrada';
    final String fecha = disponibilidad.fecha == null
        ? 'la fecha mostrada'
        : fechaLargaEspanol(disponibilidad.fecha!);
    _enviarTexto(
      'Quiero una cita con $profesional el $fecha a las '
      '${intervalo.inicioCorto}.',
    );
  }

  Future<void> _continuarPropuesta(String mensajeId, int indice) async {
    if (_abriendoPropuesta) return;
    _abriendoPropuesta = true;
    try {
      final propuesta = await _chatbot.prepararPropuesta(mensajeId, indice);
      if (!mounted) return;
      if (propuesta == null || !propuesta.datosValidos) {
        _avisar('La propuesta ya no está vigente. Solicita una nueva.');
        return;
      }
      final fecha = propuesta.fecha!;
      await _abrirAgendamiento(
        validarContexto: () async =>
            await _chatbot.prepararPropuesta(mensajeId, indice) != null,
        preseleccion: PreseleccionCita(
          oftalmologoId: propuesta.oftalmologoId!,
          fecha: DateTime(fecha.year, fecha.month, fecha.day),
          horaInicio: propuesta.horaInicio,
        ),
      );
    } finally {
      _abriendoPropuesta = false;
    }
  }

  void _navegar(TarjetaNavegacion navegacion) {
    switch (navegacion.destino) {
      case DestinoChat.catalogo:
        _abrirCatalogo();
      case DestinoChat.agendarCita:
        _abrirAgendamiento();
      case DestinoChat.misCitas:
        _abrirMisCitas();
      case DestinoChat.detalleCita:
      case DestinoChat.reprogramarCita:
      case DestinoChat.cancelarCita:
        final int? id = navegacion.citaId;
        if (id != null && id > 0) {
          _abrirDetalleCita(id);
        } else {
          _avisar('El asistente no indicó una cita válida para esta acción.');
        }
      case DestinoChat.desconocido:
        _avisar('Esta acción no está disponible en esta versión.');
    }
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
      );
  }

  // -------------------------------------------------------------------
  // Diálogos informativos
  // -------------------------------------------------------------------

  Future<void> _mostrarPrivacidad() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Privacidad y alcance'),
        content: const SingleChildScrollView(
          child: Text(
            'Este asistente es administrativo. Puede consultar servicios, '
            'profesionales, disponibilidad y tus propias citas. No realiza '
            'diagnósticos, no prescribe, no interpreta exámenes y no sustituye '
            'la valoración de un profesional de salud.\n\n'
            'Las conversaciones se mantienen solo en memoria mientras usas la '
            'aplicación. No se guardan en el dispositivo y se eliminan al '
            'cerrar sesión, al iniciar una conversación nueva o al expirar.\n\n'
            'No escribas contraseñas, documentos, datos de pago ni información '
            'clínica sensible. Para la voz, el micrófono se activa solo cuando '
            'lo pides y la transcripción se solicita en el dispositivo. La '
            'información privada solo se lee en voz alta si el motor de voz '
            'local puede verificarse; de lo contrario se muestra por escrito.'
            '\n\n'
            'Las acciones sobre citas (agendar, reprogramar, cancelar) se '
            'completan en los formularios existentes y siempre requieren tu '
            'confirmación explícita.',
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

  Future<void> _configuracionVoz() async {
    bool automatica = _reproduccionAutomatica;
    final bool? guardado = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Configuración de voz'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: automatica,
                    onChanged: (bool valor) =>
                        setLocal(() => automatica = valor),
                    title: const Text('Reproducir respuestas'),
                    subtitle: const Text(
                      'Cuando el asistente responda, leerá el texto con la voz '
                      'del dispositivo. La información privada solo se lee si '
                      'el motor local puede verificarse.',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'La calidad de la voz depende del motor instalado en el '
                    'dispositivo. No se usa un servicio externo de voz.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: ChatbotColores.grisTexto,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (guardado == true && mounted) {
      setState(() => _reproduccionAutomatica = automatica);
    }
  }

  void _abrirMenu(String opcion) {
    switch (opcion) {
      case 'nueva':
        _nuevaConversacion();
      case 'privacidad':
        _mostrarPrivacidad();
      case 'voz':
        _configuracionVoz();
    }
  }

  // -------------------------------------------------------------------
  // Interfaz
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatbotColores.fondo,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: FondoChatbot()),
          SafeArea(
            child: AnimatedBuilder(
              animation: _chatbot,
              builder: (BuildContext context, Widget? child) {
                return Column(
                  children: <Widget>[
                    ChatEncabezado(
                      clinica: widget.clinica,
                      onVolver: () => Navigator.of(context).maybePop(),
                      onOpcion: _abrirMenu,
                    ),
                    Expanded(
                      child: _chatbot.mensajes.isEmpty
                          ? ChatBienvenida(
                              clinica: widget.clinica,
                              aviso: _chatbot.aviso,
                              puedeEnviar: _chatbot.puedeEnviar,
                              onSugerencia: _enviarTexto,
                              onPrivacidad: _mostrarPrivacidad,
                            )
                          : ChatConversacion(
                              mensajes: _chatbot.mensajes,
                              enviando: _chatbot.enviando,
                              tarjetasInvalidas: _chatbot.tarjetasInvalidas,
                              propuestaVigente: _chatbot.propuestaVigente,
                              puedeReintentar: _chatbot.puedeEnviar,
                              scrollController: _scroll,
                              acciones: _accionesTarjetas(),
                              puedeEscuchar: _puedeEscuchar,
                              onCopiar: (MensajeChat mensaje) =>
                                  copiarTexto(context, mensaje.texto),
                              onEscuchar: (MensajeChat mensaje) =>
                                  _abrirVoz(mensaje: mensaje),
                              onReintentar: _reintentar,
                            ),
                    ),
                    _avisoAlcance(),
                    ChatCompositor(
                      controller: _texto,
                      focusNode: _foco,
                      puedeEnviar: _chatbot.puedeEnviar,
                      maxCaracteres: _chatbot.maxCaracteresMensaje,
                      onEnviar: _enviarCompositor,
                      onVoz: () => _abrirVoz(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoAlcance() {
    if (_chatbot.mensajes.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: Colors.white.withValues(alpha: 0.60),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.shield_outlined,
            size: 14,
            color: ChatbotColores.grisTexto,
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Asistente administrativo. No realiza diagnósticos médicos.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.3,
                color: ChatbotColores.grisTexto,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AccionesTarjetasChatbot _accionesTarjetas() {
    return AccionesTarjetasChatbot(
      onVerCatalogo: _abrirCatalogo,
      onConsultarServicio: (ServicioChat servicio) => _enviarTexto(
        'Quiero más información del servicio ${servicio.nombre}.',
      ),
      onVerDisponibilidad: (ProfesionalChat profesional) => _enviarTexto(
        'Quiero consultar la disponibilidad de ${profesional.nombre} para '
        'los próximos días.',
      ),
      onSeleccionarHorario: _seleccionarHorario,
      onContinuarAgendamiento: _continuarPropuesta,
      onVerCita: _abrirDetalleCita,
      onNavegar: _navegar,
      profesionales: Map<int, String>.unmodifiable(_profesionales),
    );
  }

  bool _puedeEscuchar(MensajeChat mensaje) {
    if (mensaje.texto.trim().isEmpty) return false;
    if (mensaje.tipo == TipoRespuestaChatbot.privacidad) return false;
    return !mensaje.tarjetas.any((TarjetaChatbot t) => t.esPrivada);
  }
}
