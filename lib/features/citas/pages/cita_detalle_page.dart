import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../models/agenda_models.dart';
import '../models/cita_models.dart';
import '../services/agenda_service.dart';
import '../widgets/citas_ui.dart';

/// Detalle real de una cita con las acciones que permite el backend:
///
/// - Reprogramar: `PUT /agenda-citas/citas/{id}` con `CitaUpdate`
///   (solo fecha y hora de inicio; la hora de fin la calcula FastAPI).
/// - Cancelar: `PATCH /agenda-citas/citas/{id}/estado` con `CANCELADA`.
///
/// El servidor es la autoridad final: cualquier 403/409/422 se muestra tal
/// como lo explica el backend y el detalle se vuelve a sincronizar.
///
/// Devuelve `true` al cerrarse si la cita cambió, para que el listado se
/// recargue con datos reales.
class CitaDetallePage extends StatefulWidget {
  const CitaDetallePage({
    super.key,
    required this.citaId,
    this.citaInicial,
    this.oftalmologo,
    this.clinica,
    this.agendaService,
    this.onSesionInvalida,
  });

  final int citaId;

  /// Datos ya conocidos por el listado (se refrescan al abrir).
  final Cita? citaInicial;

  final OftalmologoAgenda? oftalmologo;
  final ClinicaSesion? clinica;
  final AgendaService? agendaService;
  final Future<void> Function()? onSesionInvalida;

  @override
  State<CitaDetallePage> createState() => _CitaDetallePageState();
}

class _CitaDetallePageState extends State<CitaDetallePage> {
  late final AgendaService _agenda = widget.agendaService ?? AgendaService();

  Cita? _cita;
  OftalmologoAgenda? _oftalmologo;
  bool _cargando = true;
  bool _procesando = false;
  String? _errorCarga;
  bool _cambio = false;

  @override
  void initState() {
    super.initState();
    _cita = widget.citaInicial;
    _oftalmologo = widget.oftalmologo;
    _refrescar();
  }

  /// Vuelve a leer la cita desde el backend (`GET /agenda-citas/citas/{id}`).
  Future<void> _refrescar() async {
    try {
      final Cita actualizada = await _agenda.obtenerCita(widget.citaId);
      OftalmologoAgenda? medico = _oftalmologo;

      if (medico == null) {
        try {
          final List<OftalmologoAgenda> lista = await _agenda
              .listarOftalmologos();
          for (final OftalmologoAgenda oftalmologo in lista) {
            if (oftalmologo.id == actualizada.oftalmologoId) {
              medico = oftalmologo;
              break;
            }
          }
        } catch (_) {
          // Dato complementario: si falla, se muestran los datos de la cita.
        }
      }

      if (!mounted) return;
      setState(() {
        _cita = actualizada;
        _oftalmologo = medico;
        _cargando = false;
        _errorCarga = null;
      });
    } on AgendaException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await widget.onSesionInvalida?.call();
        return;
      }

      setState(() {
        _cargando = false;
        _errorCarga = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _errorCarga = 'No se pudo actualizar la cita. Inténtalo de nuevo.';
      });
    }
  }

  /// Solo las citas vigentes y futuras admiten reprogramación o cancelación.
  bool get _puedeGestionar {
    final Cita? cita = _cita;
    if (cita == null) return false;
    return cita.estaVigente && cita.esFutura;
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Escenario de red incierta en una escritura: nunca se reintenta solo.
  Future<void> _avisarResultadoIncierto(String accion) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('No pudimos confirmar la respuesta'),
        content: Text(
          'La $accion pudo haberse registrado, pero el servidor no respondió '
          'a tiempo. Revisa el estado real de la cita antes de intentarlo otra '
          'vez para no duplicar la operación.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() => _cambio = true);
    await _refrescar();
  }

  Future<void> _cancelar() async {
    final Cita? cita = _cita;
    if (cita == null || _procesando) return;

    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('¿Cancelar tu cita?'),
        content: Text(
          'Se cancelará la cita del ${fechaLargaEspanol(cita.fecha)} a las '
          '${cita.horaInicioCorta}. El horario volverá a quedar disponible '
          'para otros pacientes.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Mantener cita'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CitasColores.rojo,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    setState(() => _procesando = true);

    try {
      final Cita actualizada = await _agenda.cambiarEstadoCita(
        cita.id,
        citaCancelada,
      );

      if (!mounted) return;
      setState(() {
        _cita = actualizada;
        _procesando = false;
        _cambio = true;
      });
      _avisar('Tu cita fue cancelada.');
    } on AgendaException catch (error) {
      if (!mounted) return;
      setState(() => _procesando = false);

      if (error.resultadoIncierto) {
        await _avisarResultadoIncierto('cancelación');
        return;
      }

      if (error.statusCode == 401) {
        await widget.onSesionInvalida?.call();
        return;
      }

      _avisar(error.message);

      if (error.statusCode == 404 || error.statusCode == 409) {
        await _refrescar();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _avisar('No se pudo cancelar la cita. Inténtalo de nuevo.');
    }
  }

  Future<void> _reprogramar() async {
    final Cita? cita = _cita;
    if (cita == null || _procesando) return;

    final _SeleccionReprogramacion? seleccion =
        await showModalBottomSheet<_SeleccionReprogramacion>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _HojaReprogramar(
            agenda: _agenda,
            oftalmologoId: cita.oftalmologoId,
            fechaActual: cita.fecha,
            horaActual: cita.horaInicio,
            onSesionInvalida: widget.onSesionInvalida,
          ),
        );

    if (seleccion == null || !mounted) return;

    setState(() => _procesando = true);

    try {
      final Cita actualizada = await _agenda.reprogramarCita(
        cita.id,
        CitaUpdate(
          fecha: seleccion.fecha,
          horaInicio: seleccion.horaInicio,
        ),
      );

      if (!mounted) return;
      setState(() {
        _cita = actualizada;
        _procesando = false;
        _cambio = true;
      });
      _avisar('Tu cita fue reprogramada.');
    } on AgendaException catch (error) {
      if (!mounted) return;
      setState(() => _procesando = false);

      if (error.resultadoIncierto) {
        await _avisarResultadoIncierto('reprogramación');
        return;
      }

      if (error.statusCode == 401) {
        await widget.onSesionInvalida?.call();
        return;
      }

      _avisar(error.message);

      // El horario pudo ocuparse (409) o la cita ya no admite cambios.
      if (error.statusCode == 404 ||
          error.statusCode == 409 ||
          error.statusCode == 422) {
        await _refrescar();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _avisar('No se pudo reprogramar la cita. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (didPop) return;
        Navigator.of(context).pop(_cambio);
      },
      child: Scaffold(
        backgroundColor: CitasColores.fondoSuave,
        appBar: AppBar(
          title: const Text('Detalle de la cita'),
          backgroundColor: CitasColores.azulProfundo,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: FondoCitas()),
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _refrescar,
                color: CitasColores.azulProfundo,
                child: _contenido(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    final Cita? cita = _cita;

    if (cita == null) {
      if (_cargando) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
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
          ],
        );
      }

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        children: <Widget>[
          TarjetaCitas(
            child: MensajeEstado(
              icono: Icons.error_outline,
              titulo: 'No se pudo abrir la cita',
              mensaje: _errorCarga,
              colorIcono: CitasColores.rojo,
              accion: FilledButton.icon(
                onPressed: () {
                  setState(() => _cargando = true);
                  _refrescar();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      children: <Widget>[
        _tarjetaPrincipal(cita),
        if (_errorCarga != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: CitasColores.ambar,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorCarga!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: CitasColores.ambar,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _tarjetaDetalles(cita),
        const SizedBox(height: 14),
        _tarjetaAcciones(cita),
      ],
    );
  }

  Widget _tarjetaDetalles(Cita cita) {
    return TarjetaCitas(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Información de la cita',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: CitasColores.azulProfundo,
            ),
          ),
          const SizedBox(height: 12),
          _filaDetalle(
            Icons.event,
            'Fecha',
            fechaCorta(cita.fecha),
          ),
          _filaDetalle(Icons.schedule, 'Horario', cita.franja),
          _filaDetalle(
            Icons.timelapse,
            'Duración',
            '$duracionCitaMinutos minutos',
          ),
          _filaDetalle(
            Icons.badge_outlined,
            'Matrícula',
            (_oftalmologo?.matricula.isNotEmpty ?? false)
                ? _oftalmologo!.matricula
                : 'No disponible',
          ),
          _filaDetalle(
            Icons.notes,
            'Motivo',
            cita.motivo ?? 'Sin motivo registrado',
          ),
          _filaDetalle(
            Icons.description_outlined,
            'Observaciones',
            cita.observaciones ?? 'Sin observaciones',
          ),
          if ((cita.fechaRegistro ?? '').isNotEmpty)
            _filaDetalle(
              Icons.history,
              'Registrada',
              cita.fechaRegistro!,
            ),
          if ((cita.fechaActualizacion ?? '').isNotEmpty)
            _filaDetalle(
              Icons.update,
              'Actualizada',
              cita.fechaActualizacion!,
            ),
        ],
      ),
    );
  }

  Widget _filaDetalle(IconData icono, String etiqueta, String valor) {

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, size: 17, color: CitasColores.azulPrincipal),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12.5,
                color: CitasColores.grisSuave,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: CitasColores.azulProfundo,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPrincipal(Cita cita) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            CitasColores.azulProfundo,
            CitasColores.azulPrincipal,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: CitasColores.azulProfundo.withValues(alpha: 0.26),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Cita #${cita.id}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              ChipEstadoCita(estado: cita.estado, compacto: true),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            fechaLargaEspanol(cita.fecha),
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.schedule,
                size: 20,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                cita.franja,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.person_outline,
                      size: 17,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _oftalmologo?.nombreCompleto ??
                            'Oftalmólogo #${cita.oftalmologoId}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.local_hospital_outlined,
                      size: 17,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.clinica?.etiqueta ?? 'Clínica de tu sesión',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaAcciones(Cita cita) {
    if (!_puedeGestionar) {
      return TarjetaCitas(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.lock_clock,
                  size: 19,
                  color: CitasColores.grisSuave,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sin acciones disponibles',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: CitasColores.azulProfundo,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _mensajeSinAcciones(cita),
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: CitasColores.grisTexto,
              ),
            ),
          ],
        ),
      );
    }

    return TarjetaCitas(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Gestiona tu cita',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: CitasColores.azulProfundo,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Puedes reprogramar o cancelar mientras la cita siga vigente. El '
            'servidor valida cada cambio.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: CitasColores.grisTexto,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _procesando ? null : _reprogramar,
              icon: const Icon(Icons.edit_calendar_outlined, size: 19),
              label: const Text(
                'Reprogramar cita',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: CitasColores.azulProfundo,
                side: const BorderSide(color: CitasColores.borde, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _procesando ? null : _cancelar,
              icon: const Icon(Icons.event_busy_outlined, size: 19),
              label: const Text(
                'Cancelar cita',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: CitasColores.rojo,
                side: BorderSide(
                  color: CitasColores.rojo.withValues(alpha: 0.45),
                  width: 1.4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (_procesando) ...<Widget>[
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: CitasColores.azulProfundo,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Procesando con el servidor...',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: CitasColores.grisTexto,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _mensajeSinAcciones(Cita cita) {
    if (cita.estaCancelada) {
      return 'Esta cita fue cancelada. Puedes agendar una nueva cuando lo '
          'necesites desde la pestaña Agendar.';
    }

    if (cita.estado == citaAtendida) {
      return 'Esta cita ya fue atendida; la información queda disponible en tu '
          'historial.';
    }

    if (cita.estado == citaNoAsistio) {
      return 'El sistema registró que no asististe a esta cita.';
    }

    if (!cita.esFutura) {
      return 'La fecha de esta cita ya pasó, por lo que no admite cambios.';
    }

    return 'El servidor no permite modificar esta cita en su estado actual.';
  }
}

/// Selección devuelta por la hoja de reprogramación.
class _SeleccionReprogramacion {
  const _SeleccionReprogramacion({
    required this.fecha,
    required this.horaInicio,
  });

  final DateTime fecha;

  /// Hora de inicio en formato `HH:MM:SS` (contrato del backend).
  final String horaInicio;
}

/// Hoja inferior que permite elegir una nueva fecha y hora usando la
/// disponibilidad REAL del oftalmólogo (`GET /agenda-citas/disponibilidad`).
class _HojaReprogramar extends StatefulWidget {
  const _HojaReprogramar({
    required this.agenda,
    required this.oftalmologoId,
    required this.fechaActual,
    required this.horaActual,
    this.onSesionInvalida,
  });

  final AgendaService agenda;
  final int oftalmologoId;
  final DateTime fechaActual;
  final String horaActual;
  final Future<void> Function()? onSesionInvalida;

  @override
  State<_HojaReprogramar> createState() => _HojaReprogramarState();
}

class _HojaReprogramarState extends State<_HojaReprogramar> {
  late final List<DateTime> _fechas = _construirFechas();
  late DateTime _fecha = _fechas.first;
  List<RanuraDisponible> _ranuras = const <RanuraDisponible>[];
  RanuraDisponible? _ranura;
  bool _cargando = true;
  String? _error;

  /// Próximos 21 días desde hoy: el backend decide si hay horario real.
  List<DateTime> _construirFechas() {
    final DateTime hoy = DateTime.now();
    final DateTime base = DateTime(hoy.year, hoy.month, hoy.day);
    return <DateTime>[
      for (int i = 0; i < 21; i++) base.add(Duration(days: i)),
    ];
  }

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  Future<void> _consultar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _ranura = null;
      _ranuras = const <RanuraDisponible>[];
    });

    try {
      final DisponibilidadRespuesta disponibilidad = await widget.agenda
          .obtenerDisponibilidad(
            oftalmologoId: widget.oftalmologoId,
            fecha: _fecha,
          );

      if (!mounted) return;
      setState(() {
        _ranuras = generarRanurasDisponibles(
          disponibilidad.intervalosDisponibles,
        );
        _cargando = false;
      });
    } on AgendaException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        Navigator.of(context).pop();
        await widget.onSesionInvalida?.call();
        return;
      }

      setState(() {
        _cargando = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo consultar la disponibilidad.';
      });
    }
  }

  void _elegirFecha(DateTime fecha) {
    if (_cargando && _esMismoDia(fecha, _fecha)) return;
    setState(() => _fecha = fecha);
    _consultar();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: CitasColores.borde,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Reprogramar cita',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: CitasColores.azulProfundo,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: CitasColores.grisTexto,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Cita actual: ${fechaCorta(widget.fechaActual)} · '
                    '${horaCorta(widget.horaActual)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: CitasColores.grisTexto,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(height: 74, child: _listaFechas()),
              const SizedBox(height: 6),
              const Divider(height: 18, color: CitasColores.borde),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: _contenidoRanuras(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _ranura == null
                        ? null
                        : () => Navigator.of(context).pop(
                            _SeleccionReprogramacion(
                              fecha: _fecha,
                              horaInicio: _ranura!.horaInicio,
                            ),
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: CitasColores.azulProfundo,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _ranura == null
                          ? 'Elige un horario'
                          : 'Confirmar ${_ranura!.etiqueta}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listaFechas() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _fechas.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (BuildContext context, int index) {
        final DateTime fecha = _fechas[index];
        final bool activa = _esMismoDia(fecha, _fecha);

        return Material(
          color: activa ? CitasColores.azulPrincipal : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _elegirFecha(fecha),
            child: Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: activa
                      ? CitasColores.azulPrincipal
                      : CitasColores.borde,
                  width: activa ? 1.6 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    _diaSemanaCorto(fecha),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: activa
                          ? Colors.white70
                          : CitasColores.grisSuave,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fecha.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: activa
                          ? Colors.white
                          : CitasColores.azulProfundo,
                    ),
                  ),
                  Text(
                    _mesCorto(fecha),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: activa
                          ? Colors.white70
                          : CitasColores.grisSuave,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _contenidoRanuras() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: CitasColores.azulProfundo,
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return MensajeEstado(
        icono: Icons.error_outline,
        titulo: 'No se pudo consultar la disponibilidad',
        mensaje: _error,
        colorIcono: CitasColores.rojo,
        accion: OutlinedButton.icon(
          onPressed: _consultar,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reintentar'),
        ),
      );
    }

    if (_ranuras.isEmpty) {
      return const MensajeEstado(
        icono: Icons.event_busy,
        titulo: 'Sin horarios disponibles',
        mensaje:
            'No hay turnos libres ese día. Prueba con otra fecha para tu '
            'reprogramación.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Horarios libres del ${fechaCorta(_fecha)}',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: CitasColores.azulProfundo,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final RanuraDisponible ranura in _ranuras)
              _chipRanura(ranura),
          ],
        ),
      ],
    );
  }

  Widget _chipRanura(RanuraDisponible ranura) {
    final bool activa = _ranura?.horaInicio == ranura.horaInicio;

    return Material(
      color: activa ? CitasColores.azulPrincipal : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _ranura = ranura),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: activa ? CitasColores.azulPrincipal : CitasColores.borde,
              width: activa ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (activa) ...<Widget>[
                const Icon(Icons.check, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                ranura.etiqueta,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: activa ? Colors.white : CitasColores.azulProfundo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _esMismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _diaSemanaCorto(DateTime fecha) {
    const List<String> dias = <String>[
      'Lun',
      'Mar',
      'Mié',
      'Jue',
      'Vie',
      'Sáb',
      'Dom',
    ];
    return dias[(fecha.weekday - 1).clamp(0, 6)];
  }

  static String _mesCorto(DateTime fecha) {
    const List<String> meses = <String>[
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return meses[(fecha.month - 1).clamp(0, 11)];
  }
}
