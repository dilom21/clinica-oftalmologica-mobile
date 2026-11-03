import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../models/agenda_models.dart';
import '../models/cita_models.dart';
import '../services/agenda_service.dart';
import '../widgets/cita_card.dart';
import '../widgets/citas_ui.dart';
import 'cita_detalle_page.dart';

/// Listado real de las citas del paciente autenticado.
///
/// Consume `GET /agenda-citas/citas`; el backend restringe la respuesta a las
/// citas del paciente del JWT (nunca se envía `paciente_id` de otra persona).
class MisCitasView extends StatefulWidget {
  const MisCitasView({
    super.key,
    this.agendaService,
    this.clinica,
    this.onSesionInvalida,
    this.onAgendarCita,
    this.onCitasCambiadas,
  });

  final AgendaService? agendaService;

  /// Clínica de la sesión (solo para mostrar, nunca fija).
  final ClinicaSesion? clinica;

  final Future<void> Function()? onSesionInvalida;

  /// Acceso al flujo de agendamiento cuando aún no hay citas.
  final VoidCallback? onAgendarCita;

  /// Avisa al contenedor cuando una cita fue creada, reprogramada o cancelada.
  final VoidCallback? onCitasCambiadas;

  @override
  State<MisCitasView> createState() => MisCitasViewState();
}

class MisCitasViewState extends State<MisCitasView> {
  late final AgendaService _agenda = widget.agendaService ?? AgendaService();

  List<Cita> _citas = const <Cita>[];
  Map<int, OftalmologoAgenda> _oftalmologos = const <int, OftalmologoAgenda>{};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  /// Recarga las citas del paciente.
  ///
  /// [silencioso] evita mostrar el indicador de carga a pantalla completa
  /// cuando ya hay datos en pantalla (por ejemplo al volver del detalle).
  Future<void> cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final List<Cita> citas = await _agenda.listarCitas();

      Map<int, OftalmologoAgenda> medicos = _oftalmologos;
      if (medicos.isEmpty) {
        try {
          final List<OftalmologoAgenda> lista = await _agenda
              .listarOftalmologos();
          medicos = <int, OftalmologoAgenda>{
            for (final OftalmologoAgenda oftalmologo in lista)
              oftalmologo.id: oftalmologo,
          };
        } catch (_) {
          // El nombre del médico es información complementaria: si falla, las
          // citas se siguen mostrando con los datos reales disponibles.
          medicos = _oftalmologos;
        }
      }

      if (!mounted) return;
      setState(() {
        _citas = citas;
        _oftalmologos = medicos;
        _cargando = false;
        _error = null;
      });
    } on AgendaException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await widget.onSesionInvalida?.call();
        return;
      }

      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Ocurrió un error inesperado. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  /// Citas vigentes (futuras y no canceladas) ordenadas por cercanía.
  List<Cita> get _proximas {
    final List<Cita> lista = _citas
        .where((Cita cita) => cita.esFutura && !cita.estaCancelada)
        .toList();
    lista.sort((a, b) => a.inicio.compareTo(b.inicio));
    return lista;
  }

  /// Citas anteriores o cerradas, de la más reciente a la más antigua.
  List<Cita> get _anteriores {
    final List<Cita> lista = _citas
        .where((Cita cita) => !(cita.esFutura && !cita.estaCancelada))
        .toList();
    lista.sort((a, b) => b.inicio.compareTo(a.inicio));
    return lista;
  }


  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => cargar(silencioso: true),
      color: CitasColores.azulProfundo,
      child: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        children: const <Widget>[
          Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: CitasColores.azulProfundo,
              ),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Cargando tus citas...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: CitasColores.grisTexto),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        children: <Widget>[
          TarjetaCitas(
            child: MensajeEstado(
              icono: Icons.error_outline,
              titulo: 'No se pudieron cargar tus citas',
              mensaje: _error,
              colorIcono: CitasColores.rojo,
              accion: FilledButton.icon(
                onPressed: () => cargar(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ),
          ),
        ],
      );
    }

    if (_citas.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        children: <Widget>[
          TarjetaCitas(
            child: MensajeEstado(
              icono: Icons.event_available,
              titulo: 'Aún no tienes citas registradas',
              mensaje:
                  'Agenda tu primera cita con un oftalmólogo para verla aquí.',
              accion: widget.onAgendarCita == null
                  ? null
                  : FilledButton.icon(
                      onPressed: widget.onAgendarCita,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Agendar cita'),
                    ),
            ),
          ),
        ],
      );
    }

    final List<Cita> proximas = _proximas;
    final List<Cita> anteriores = _anteriores;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: <Widget>[
        if (proximas.isNotEmpty) ...<Widget>[
          _encabezadoSeccion('Próximas citas', proximas.length),
          const SizedBox(height: 10),
          for (final Cita cita in proximas)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CitaCard(
                cita: cita,
                oftalmologo: _oftalmologos[cita.oftalmologoId],
                onTap: () => _abrirDetalle(cita),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (anteriores.isNotEmpty) ...<Widget>[
          _encabezadoSeccion('Historial de citas', anteriores.length),
          const SizedBox(height: 10),
          for (final Cita cita in anteriores)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CitaCard(
                cita: cita,
                oftalmologo: _oftalmologos[cita.oftalmologoId],
                onTap: () => _abrirDetalle(cita),
              ),
            ),
        ],
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Desliza hacia abajo para actualizar',
            style: TextStyle(fontSize: 11.5, color: CitasColores.grisSuave),
          ),
        ),
      ],
    );
  }

  Widget _encabezadoSeccion(String titulo, int total) {
    return Row(
      children: <Widget>[
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: CitasColores.azulProfundo,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: CitasColores.fondoSuave,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '$total',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: CitasColores.azulPrincipal,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _abrirDetalle(Cita cita) async {
    final bool? cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CitaDetallePage(
          citaId: cita.id,
          citaInicial: cita,
          oftalmologo: _oftalmologos[cita.oftalmologoId],
          clinica: widget.clinica,
          agendaService: _agenda,
          onSesionInvalida: widget.onSesionInvalida,
        ),
      ),
    );

    // La cita pudo cancelarse o reprogramarse en el detalle.
    if (cambio == true && mounted) {
      await cargar(silencioso: true);
      widget.onCitasCambiadas?.call();
    }
  }
}

