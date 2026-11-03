import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../../perfil_paciente/services/paciente_service.dart';
import '../models/cita_models.dart';
import '../services/agenda_service.dart';
import '../widgets/citas_ui.dart';
import 'agendar_cita_view.dart';
import 'mis_citas_view.dart';

/// Vistas internas de la pestaña Citas.
enum VistaCitas { agendar, misCitas }

/// Pantalla de Citas del paciente: reúne CU09 (consultar disponibilidad) y CU10
/// (agendar, listar, reprogramar y cancelar citas reales).
///
/// La pantalla no duplica la lógica de cada flujo: presenta dos vistas
/// especializadas dentro de una única pestaña de la barra inferior.
///
/// - [AgendarCitaView] -> pasos 1-4 + `POST /agenda-citas/citas`.
/// - [MisCitasView]    -> `GET /agenda-citas/citas` + detalle de cada cita.
///
/// La segunda vista se construye la primera vez que se abre (carga diferida),
/// de modo que abrir la app no dispara peticiones que el paciente todavía no
/// pidió. Ninguna de las dos consume
/// `/agenda-citas/oftalmologos/{id}/agenda` ni envía el `paciente_id` de otra
/// persona.
class CitasPage extends StatefulWidget {
  const CitasPage({
    super.key,
    this.agendaService,
    this.pacienteService,
    this.clinica,
    this.onSesionInvalida,
    this.onCitasCambiadas,
    this.vistaInicial,
  });

  /// Servicio de agenda/citas; inyectable en pruebas.
  final AgendaService? agendaService;

  /// Servicio del paciente (aporta el `paciente_id` real del JWT).
  final PacienteService? pacienteService;

  /// Clínica de la sesión (solo para mostrar, nunca fija).
  final ClinicaSesion? clinica;

  /// Se invoca ante un JWT inválido. En producción el contenedor limpia la
  /// sesión y vuelve al login.
  final Future<void> Function()? onSesionInvalida;

  /// Avisa al contenedor cuando una cita se creó, reprogramó o canceló.
  final VoidCallback? onCitasCambiadas;

  /// Vista con la que se abre la pestaña (por defecto, agendar).
  final VistaCitas? vistaInicial;

  @override
  State<CitasPage> createState() => CitasPageState();
}

class CitasPageState extends State<CitasPage> {
  late final AgendaService _agenda = widget.agendaService ?? AgendaService();
  late final PacienteService _paciente =
      widget.pacienteService ?? PacienteService();

  final GlobalKey<AgendarCitaViewState> _agendarKey =
      GlobalKey<AgendarCitaViewState>();
  final GlobalKey<MisCitasViewState> _misCitasKey =
      GlobalKey<MisCitasViewState>();

  late VistaCitas _vista = widget.vistaInicial ?? VistaCitas.agendar;

  /// Vistas ya construidas (carga diferida de cada sub-pantalla).
  late final Set<VistaCitas> _construidas = <VistaCitas>{_vista};

  // -------------------------------------------------------------------
  // API pública para el contenedor de pestañas
  // -------------------------------------------------------------------

  /// Refresca la vista visible cuando el paciente vuelve a la pestaña Citas.
  void alMostrarPestana() {
    if (_vista == VistaCitas.agendar) {
      _agendarKey.currentState?.alMostrar();
      return;
    }
    _misCitasKey.currentState?.cargar(silencioso: true);
  }

  /// Abre el flujo de agendamiento (acceso directo desde Inicio).
  void abrirAgendarCita() {
    _irAVista(VistaCitas.agendar);
  }

  /// Abre el listado de citas del paciente.
  void abrirMisCitas({bool recargar = true}) {
    _irAVista(VistaCitas.misCitas, recargar: recargar);
  }

  // -------------------------------------------------------------------
  // Navegación interna
  // -------------------------------------------------------------------

  /// Cambia de vista construyéndola si es la primera vez.
  ///
  /// Una vista recién construida carga sus datos en `initState`, por eso solo
  /// se pide un refresco explícito cuando ya existía.
  void _irAVista(VistaCitas vista, {bool recargar = true}) {
    final bool yaConstruida = _construidas.contains(vista);

    if (_vista != vista) {
      setState(() {
        _vista = vista;
        _construidas.add(vista);
      });
    } else if (!yaConstruida) {
      setState(() {
        _construidas.add(vista);
      });
    }

    if (!recargar || !yaConstruida) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (vista == VistaCitas.agendar) {
        _agendarKey.currentState?.alMostrar();
        return;
      }
      _misCitasKey.currentState?.cargar(silencioso: true);
    });
  }

  /// El paciente reservó una cita: el historial debe reflejarla.
  void _alCrearCita(Cita cita) {
    if (_construidas.contains(VistaCitas.misCitas)) {
      _misCitasKey.currentState?.cargar(silencioso: true);
    }
    widget.onCitasCambiadas?.call();
  }

  /// 401 = sesión inválida: se limpia el JWT y se vuelve al login.
  Future<void> _sesionInvalida() async {
    final Future<void> Function()? callback = widget.onSesionInvalida;
    if (callback != null) {
      await callback();
      return;
    }

    await TokenStorage().deleteToken();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // -------------------------------------------------------------------
  // Interfaz
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FF),
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: FondoCitas()),
          SafeArea(
            child: Column(
              children: <Widget>[
                _encabezado(),
                Expanded(
                  child: IndexedStack(
                    index: _vista.index,
                    children: <Widget>[
                      _contenidoAgendar(),
                      _contenidoMisCitas(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenidoAgendar() {
    if (!_construidas.contains(VistaCitas.agendar)) {
      return const SizedBox.shrink();
    }

    return AgendarCitaView(
      key: _agendarKey,
      agendaService: _agenda,
      pacienteService: _paciente,
      clinica: widget.clinica,
      onSesionInvalida: _sesionInvalida,
      onCitaCreada: _alCrearCita,
      onVerMisCitas: () => abrirMisCitas(),
    );
  }

  Widget _contenidoMisCitas() {
    if (!_construidas.contains(VistaCitas.misCitas)) {
      return const SizedBox.shrink();
    }

    return MisCitasView(
      key: _misCitasKey,
      agendaService: _agenda,
      clinica: widget.clinica,
      onSesionInvalida: _sesionInvalida,
      onAgendarCita: () => abrirAgendarCita(),
      onCitasCambiadas: widget.onCitasCambiadas,
    );
  }

  Widget _encabezado() {
    final ClinicaSesion? clinica = widget.clinica;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      CitasColores.azulProfundo,
                      CitasColores.azulPrincipal,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: CitasColores.azulPrincipal.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.calendar_month,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Citas',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: CitasColores.azulProfundo,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      clinica?.etiqueta ?? 'Reserva y gestiona tus consultas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: CitasColores.grisTexto,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _selectorVistas(),
        ],
      ),
    );
  }

  Widget _selectorVistas() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: CitasColores.azulPrincipal.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          _opcionVista(
            vista: VistaCitas.agendar,
            icono: Icons.add_circle_outline,
            etiqueta: 'Agendar',
            clave: 'citas-vista-agendar',
          ),
          _opcionVista(
            vista: VistaCitas.misCitas,
            icono: Icons.list_alt,
            etiqueta: 'Mis citas',
            clave: 'citas-vista-mis-citas',
          ),
        ],
      ),
    );
  }

  Widget _opcionVista({
    required VistaCitas vista,
    required IconData icono,
    required String etiqueta,
    required String clave,
  }) {
    final bool activa = _vista == vista;

    return Expanded(
      child: Material(
        color: activa ? CitasColores.azulProfundo : Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          key: Key(clave),
          borderRadius: BorderRadius.circular(26),
          onTap: activa ? null : () => _irAVista(vista),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icono,
                  size: 17,
                  color: activa ? Colors.white : CitasColores.grisTexto,
                ),
                const SizedBox(width: 7),
                Text(
                  etiqueta,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: activa ? Colors.white : CitasColores.grisTexto,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
