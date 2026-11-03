import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../../perfil_paciente/services/paciente_service.dart';
import '../models/agenda_models.dart';
import '../models/cita_models.dart';
import '../services/agenda_service.dart';
import '../widgets/citas_ui.dart';

/// Flujo completo de agendamiento de una cita real.
///
/// Reutiliza CU09 (`GET /agenda-citas/oftalmologos` y
/// `GET /agenda-citas/disponibilidad`) y registra la cita con CU10
/// (`POST /agenda-citas/citas`).
///
/// Reglas de seguridad implementadas:
/// - El `paciente_id` se obtiene SIEMPRE de `GET /pacientes/me`; el paciente
///   nunca lo escribe ni puede elegir el de otra persona.
/// - El horario solo puede elegirse entre los turnos completos de 30 minutos
///   derivados de los intervalos que devolvió el backend.
/// - Un segundo toque en "Confirmar cita" no crea una segunda cita.
/// - Tras un timeout NO se reintenta automáticamente: el resultado es incierto.
class AgendarCitaView extends StatefulWidget {
  const AgendarCitaView({
    super.key,
    this.agendaService,
    this.pacienteService,
    this.clinica,
    this.onCitaCreada,
    this.onSesionInvalida,
    this.onVerMisCitas,
  });

  /// Servicio de agenda; inyectable en pruebas.
  final AgendaService? agendaService;

  /// Servicio del paciente (aporta el `paciente_id` real).
  final PacienteService? pacienteService;

  /// Clínica de la sesión (solo para mostrar el resumen).
  final ClinicaSesion? clinica;

  /// Se invoca cuando el backend confirmó la cita (HTTP 201).
  final void Function(Cita cita)? onCitaCreada;

  /// Se invoca con 401 para limpiar la sesión y volver al login.
  final Future<void> Function()? onSesionInvalida;

  /// Acceso directo al listado de citas tras reservar.
  final VoidCallback? onVerMisCitas;

  @override
  State<AgendarCitaView> createState() => AgendarCitaViewState();
}

class AgendarCitaViewState extends State<AgendarCitaView> {
  late final AgendaService _agenda = widget.agendaService ?? AgendaService();
  late final PacienteService _paciente =
      widget.pacienteService ?? PacienteService();

  final TextEditingController _motivoCtrl = TextEditingController();
  final TextEditingController _observacionesCtrl = TextEditingController();

  // Oftalmólogos reales.
  List<OftalmologoAgenda> _oftalmologos = const <OftalmologoAgenda>[];
  bool _cargandoOftalmologos = true;
  String? _errorOftalmologos;

  // Selección del paciente.
  OftalmologoAgenda? _oftalmologo;
  DateTime _fecha = _hoy();
  RanuraDisponible? _ranura;

  // Disponibilidad real.
  bool _consultando = false;
  DisponibilidadRespuesta? _disponibilidad;
  String? _errorDisponibilidad;
  List<RanuraDisponible> _ranuras = const <RanuraDisponible>[];

  // Registro de la cita.
  bool _creando = false;
  Cita? _citaCreada;

  static DateTime _hoy() {
    final DateTime ahora = DateTime.now();
    return DateTime(ahora.year, ahora.month, ahora.day);
  }

  @override
  void initState() {
    super.initState();
    _cargarOftalmologos();
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  /// Refresco pedido por la pestaña contenedora (no recarga si ya hay datos
  /// frescos y no se pidió explícitamente).
  void alMostrar() {
    if (_oftalmologos.isEmpty && !_cargandoOftalmologos) {
      _cargarOftalmologos();
    }
  }

  // ---------------------------------------------------------------
  // Datos reales
  // ---------------------------------------------------------------

  /// Carga los oftalmólogos activos (`GET /agenda-citas/oftalmologos`).
  Future<void> _cargarOftalmologos() async {
    setState(() {
      _cargandoOftalmologos = true;
      _errorOftalmologos = null;
    });

    try {
      final List<OftalmologoAgenda> lista = await _agenda.listarOftalmologos();

      if (!mounted) return;
      setState(() {
        _oftalmologos = lista;
        _cargandoOftalmologos = false;

        final OftalmologoAgenda? actual = _oftalmologo;
        final bool sigueDisponible =
            actual != null && lista.any((o) => o.id == actual.id);
        _oftalmologo = sigueDisponible
            ? actual
            : (lista.isEmpty ? null : lista.first);
      });
    } on AgendaException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await _sesionInvalida();
        return;
      }

      setState(() {
        _errorOftalmologos = error.message;
        _cargandoOftalmologos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorOftalmologos = 'Ocurrió un error inesperado. Inténtalo de nuevo.';
        _cargandoOftalmologos = false;
      });
    }
  }

  Future<void> _sesionInvalida() async {
    await widget.onSesionInvalida?.call();
  }

  /// Aviso modal para los rechazos del servidor al registrar la cita.
  ///
  /// Se usa un diálogo (y no un SnackBar) para que el paciente no pierda el
  /// mensaje del backend mientras revisa la disponibilidad actualizada.
  Future<void> _mostrarAviso(String mensaje) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('No se pudo agendar la cita'),
        content: Text(mensaje),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// El paciente elige otro oftalmólogo: se invalida el horario elegido.
  void _seleccionarOftalmologo(OftalmologoAgenda oftalmologo) {
    if (_consultando || _creando || _oftalmologo?.id == oftalmologo.id) {
      return;
    }

    setState(() {
      _oftalmologo = oftalmologo;
      _ranura = null;
      _disponibilidad = null;
      _ranuras = const <RanuraDisponible>[];
      _errorDisponibilidad = null;
    });
  }

  /// Selector de fecha (nunca permite fechas pasadas).
  Future<void> _elegirFecha() async {
    if (_consultando || _creando) return;

    final DateTime hoy = _hoy();
    final DateTime inicial = _fecha.isBefore(hoy) ? hoy : _fecha;

    final DateTime? elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: hoy,
      lastDate: DateTime(hoy.year + 2, hoy.month, hoy.day),
      helpText: 'Selecciona la fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (elegida == null || !mounted) return;
    _aplicarFecha(DateTime(elegida.year, elegida.month, elegida.day));
  }

  /// Aplica una fecha (chips "Hoy"/"Mañana" o el selector): invalida el
  /// horario previamente elegido porque la disponibilidad cambia.
  void _aplicarFecha(DateTime fecha) {
    if (_consultando || _creando) return;

    setState(() {
      _fecha = fecha;
      _ranura = null;
      _disponibilidad = null;
      _ranuras = const <RanuraDisponible>[];
      _errorDisponibilidad = null;
    });
  }

  /// Consulta la disponibilidad real (CU09) y proyecta turnos de 30 minutos.
  Future<void> _consultarDisponibilidad() async {
    final OftalmologoAgenda? oftalmologo = _oftalmologo;
    if (oftalmologo == null || _consultando) return;

    setState(() {
      _consultando = true;
      _errorDisponibilidad = null;
      _disponibilidad = null;
      _ranuras = const <RanuraDisponible>[];
      _ranura = null;
    });

    try {
      final DisponibilidadRespuesta resultado = await _agenda
          .obtenerDisponibilidad(
            oftalmologoId: oftalmologo.id,
            fecha: _fecha,
          );

      if (!mounted) return;
      setState(() {
        _disponibilidad = resultado;
        _ranuras = generarRanurasDisponibles(resultado.intervalosDisponibles);
        _consultando = false;
      });
    } on AgendaException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await _sesionInvalida();
        return;
      }

      setState(() {
        _errorDisponibilidad = error.message;
        _consultando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorDisponibilidad =
            'Ocurrió un error inesperado. Inténtalo de nuevo.';
        _consultando = false;
      });
    }
  }

  // ---------------------------------------------------------------
  // Registro real de la cita (CU10)
  // ---------------------------------------------------------------

  /// Confirma la cita contra FastAPI.
  ///
  /// - Obtiene el `paciente_id` real desde `GET /pacientes/me`.
  /// - Envía `POST /agenda-citas/citas` una sola vez (botón bloqueado mientras
  ///   la petición está en curso).
  /// - Un 409 refresca la disponibilidad y NO repite el POST.
  /// - Un timeout deja el resultado como incierto: no se reintenta solo.
  Future<void> _confirmarCita() async {
    if (_creando) return;

    final OftalmologoAgenda? oftalmologo = _oftalmologo;
    final RanuraDisponible? ranura = _ranura;

    if (oftalmologo == null || ranura == null) {
      await _mostrarAviso(
        'Selecciona un oftalmólogo, una fecha y un horario disponible '
        'antes de confirmar la cita.',
      );
      return;
    }

    setState(() {
      _creando = true;
    });

    try {
      final perfil = await _paciente.obtenerMiPerfil();

      final Cita cita = await _agenda.crearCita(
        CitaCreate(
          pacienteId: perfil.id,
          oftalmologoId: oftalmologo.id,
          fecha: _fecha,
          horaInicio: ranura.horaInicio,
          motivo: _motivoCtrl.text,
          observaciones: _observacionesCtrl.text,
        ),
      );

      if (!mounted) return;
      setState(() {
        _creando = false;
        _citaCreada = cita;
        _ranura = null;
      });
      _motivoCtrl.clear();
      _observacionesCtrl.clear();

      widget.onCitaCreada?.call(cita);

      // El turno ya está ocupado: se refresca la disponibilidad real.
      await _consultarDisponibilidad();
    } on PacienteException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await _sesionInvalida();
        return;
      }

      setState(() {
        _creando = false;
      });
      await _mostrarAviso(
        'No pudimos verificar tu perfil de paciente, así que la cita no se '
        'registró.\n\n${error.message}',
      );
    } on AgendaException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await _sesionInvalida();
        return;
      }

      setState(() {
        _creando = false;
      });

      if (error.statusCode == 409) {
        await _mostrarAviso(
          'Este horario acaba de ser ocupado. Selecciona otro disponible.',
        );
        // Se actualiza la disponibilidad real y se descarta la selección.
        await _consultarDisponibilidad();
        return;
      }

      if (error.resultadoIncierto) {
        await _mostrarAviso(
          '${error.message}\n\nRevisa "Mis citas" antes de volver a intentarlo.',
        );
        return;
      }

      await _mostrarAviso(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creando = false;
      });
      await _mostrarAviso('Ocurrió un error inesperado. Inténtalo de nuevo.');
    }
  }

  // ---------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: <Widget>[
        if (_citaCreada != null) ...<Widget>[
          _bloqueConfirmacion(_citaCreada!),
          const SizedBox(height: 18),
        ],
        _bloqueOftalmologos(),
        const SizedBox(height: 18),
        _bloqueFecha(),
        const SizedBox(height: 18),
        _bloqueHorario(),
        const SizedBox(height: 18),
        _bloqueMotivo(),
        if (_ranura != null) ...<Widget>[
          const SizedBox(height: 18),
          _bloqueResumen(),
        ],
        const SizedBox(height: 22),
        _botonConfirmar(),
      ],
    );
  }

  /// Título numerado de cada paso del flujo.
  Widget _tituloPaso(String numero, String titulo, String ayuda) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: CitasColores.azulProfundo,
            shape: BoxShape.circle,
          ),
          child: Text(
            numero,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: CitasColores.azulProfundo,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ayuda,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: CitasColores.grisTexto,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Paso 1: oftalmólogo
  // ---------------------------------------------------------------

  Widget _bloqueOftalmologos() {
    return TarjetaCitas(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _tituloPaso(
            '1',
            'Elige tu oftalmólogo',
            'Profesionales que atienden en esta clínica',
          ),
          const SizedBox(height: 14),
          if (_cargandoOftalmologos)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorOftalmologos != null)
            MensajeEstado(
              icono: Icons.cloud_off_outlined,
              titulo: 'No se pudieron cargar los oftalmólogos',
              mensaje: _errorOftalmologos,
              colorIcono: CitasColores.rojo,
              accion: OutlinedButton.icon(
                onPressed: _cargarOftalmologos,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            )
          else if (_oftalmologos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No hay oftalmólogos disponibles para consultar en este '
                'momento.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: CitasColores.grisTexto,
                ),
              ),
            )
          else
            for (final OftalmologoAgenda oftalmologo in _oftalmologos)
              _opcionOftalmologo(oftalmologo),
        ],
      ),
    );
  }

  Widget _opcionOftalmologo(OftalmologoAgenda oftalmologo) {
    final bool activo = _oftalmologo?.id == oftalmologo.id;
    final String iniciales = _iniciales(oftalmologo.nombreCompleto);
    final String? especialidad = oftalmologo.especialidad?.trim();
    final String matricula = oftalmologo.matricula.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: activo ? CitasColores.fondoSuave : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: (_consultando || _creando)
              ? null
              : () => _seleccionarOftalmologo(oftalmologo),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: activo
                    ? CitasColores.azulPrincipal
                    : CitasColores.borde,
                width: activo ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: activo
                      ? CitasColores.azulPrincipal
                      : CitasColores.borde,
                  child: Text(
                    iniciales,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: activo
                          ? Colors.white
                          : CitasColores.azulProfundo,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        oftalmologo.nombreCompleto,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: CitasColores.azulProfundo,
                        ),
                      ),
                      if (especialidad != null && especialidad.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            especialidad,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: CitasColores.grisTexto,
                            ),
                          ),
                        ),
                      if (matricula.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Matrícula: $matricula',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: CitasColores.grisSuave,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  activo ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: activo
                      ? CitasColores.azulPrincipal
                      : CitasColores.grisSuave,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _iniciales(String nombre) {
    final List<String> partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes[1][0]).toUpperCase();
  }

  // ---------------------------------------------------------------
  // Paso 2: fecha
  // ---------------------------------------------------------------

  Widget _bloqueFecha() {
    final bool esHoy = _esMismoDia(_fecha, _hoy());
    final DateTime manana = _hoy().add(const Duration(days: 1));
    final bool esManana = _esMismoDia(_fecha, manana);

    return TarjetaCitas(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _tituloPaso(
            '2',
            'Elige la fecha',
            'No se pueden registrar citas en fechas pasadas',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _chipFecha('Hoy', esHoy, () => _aplicarFecha(_hoy())),
              _chipFecha('Mañana', esManana, () => _aplicarFecha(manana)),
              OutlinedButton.icon(
                onPressed: (_consultando || _creando) ? null : _elegirFecha,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('Otra fecha'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CitasColores.azulProfundo,
                  side: const BorderSide(color: CitasColores.borde),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Icon(
                Icons.event_available,
                size: 18,
                color: CitasColores.azulPrincipal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fechaLargaEspanol(_fecha),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: CitasColores.azulProfundo,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipFecha(String etiqueta, bool activo, VoidCallback onTap) {
    return Material(
      color: activo ? CitasColores.azulProfundo : Colors.white,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: (_consultando || _creando) ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: activo ? CitasColores.azulProfundo : CitasColores.borde,
            ),
          ),
          child: Text(
            etiqueta,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: activo ? Colors.white : CitasColores.azulProfundo,
            ),
          ),
        ),
      ),
    );
  }

  bool _esMismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ---------------------------------------------------------------
  // Paso 3: horario (CU09 + turnos de 30 minutos)
  // ---------------------------------------------------------------

  Widget _bloqueHorario() {
    return TarjetaCitas(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _tituloPaso(
            '3',
            'Elige el horario',
            'Cada consulta dura $duracionCitaMinutos minutos',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_consultando || _oftalmologo == null)
                  ? null
                  : _consultarDisponibilidad,
              icon: _consultando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(
                _consultando
                    ? 'Consultando disponibilidad...'
                    : 'Consultar disponibilidad',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: CitasColores.fondoSuave,
                foregroundColor: CitasColores.azulProfundo,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _resultadoDisponibilidad(),
        ],
      ),
    );
  }

  Widget _resultadoDisponibilidad() {
    if (_errorDisponibilidad != null) {
      return MensajeEstado(
        icono: Icons.error_outline,
        titulo: 'No se pudo consultar la disponibilidad',
        mensaje: _errorDisponibilidad,
        colorIcono: CitasColores.rojo,
        accion: OutlinedButton.icon(
          onPressed: _consultarDisponibilidad,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reintentar'),
        ),
      );
    }

    final DisponibilidadRespuesta? disponibilidad = _disponibilidad;

    if (_consultando || disponibilidad == null) {
      return const Text(
        'Consulta los horarios libres del oftalmólogo para la fecha elegida.',
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: CitasColores.grisTexto,
        ),
      );
    }

    if (!disponibilidad.tieneHorario) {
      return const MensajeEstado(
        icono: Icons.event_busy,
        titulo: 'Sin horario configurado',
        mensaje:
            'El oftalmólogo no atiende en la fecha seleccionada. '
            'Prueba con otra fecha.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (disponibilidad.horariosBase.isNotEmpty) ...<Widget>[
          const Text(
            'Horario base',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: CitasColores.grisTexto,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final IntervaloHorario base in disponibilidad.horariosBase)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: CitasColores.fondoSuave,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${horaCorta(base.horaInicio)} – ${horaCorta(base.horaFin)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: CitasColores.azulProfundo,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_ranuras.isEmpty)
          const MensajeEstado(
            icono: Icons.schedule,
            titulo: 'Sin horarios disponibles',
            mensaje:
                'No quedan turnos libres para esta fecha. Prueba con otra '
                'fecha u otro oftalmólogo.',
          )
        else ...<Widget>[
          const Text(
            'Intervalos disponibles',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: CitasColores.azulProfundo,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Selecciona el horario de tu preferencia.',
            style: TextStyle(fontSize: 12.5, color: CitasColores.grisTexto),
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
        onTap: _creando ? null : () => setState(() => _ranura = ranura),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                const Icon(Icons.check, size: 15, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                ranura.etiqueta,
                style: TextStyle(
                  fontSize: 13.5,
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

  // ---------------------------------------------------------------
  // Paso 4: motivo de consulta (campos OPCIONALES en el backend)
  // ---------------------------------------------------------------

  Widget _bloqueMotivo() {
    final InputDecoration decoracion = InputDecoration(
      filled: true,
      fillColor: CitasColores.fondoSuave,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CitasColores.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CitasColores.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CitasColores.azulPrincipal),
      ),
      counterStyle: const TextStyle(
        fontSize: 11,
        color: CitasColores.grisSuave,
      ),
    );

    return TarjetaCitas(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _tituloPaso(
            '4',
            'Motivo de la consulta',
            'Opcional. Ayuda al oftalmólogo a preparar tu atención',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _motivoCtrl,
            enabled: !_creando,
            onChanged: (_) => setState(() {}),
            maxLength: 200,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: decoracion.copyWith(
              hintText: 'Ej. Control visual anual',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: CitasColores.grisSuave,
              ),
            ),
            style: const TextStyle(
              fontSize: 13.5,
              color: CitasColores.azulProfundo,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _observacionesCtrl,
            enabled: !_creando,
            onChanged: (_) => setState(() {}),
            maxLength: 300,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: decoracion.copyWith(
              hintText: 'Observaciones adicionales (opcional)',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: CitasColores.grisSuave,
              ),
            ),
            style: const TextStyle(
              fontSize: 13.5,
              color: CitasColores.azulProfundo,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Paso 5 y 6: resumen y confirmación
  // ---------------------------------------------------------------

  Widget _bloqueResumen() {
    final OftalmologoAgenda oftalmologo = _oftalmologo!;
    final RanuraDisponible ranura = _ranura!;
    final String motivo = _motivoCtrl.text.trim();
    final String observaciones = _observacionesCtrl.text.trim();

    return TarjetaCitas(
      color: CitasColores.fondoSuave,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.fact_check_outlined,
                size: 20,
                color: CitasColores.azulProfundo,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Resumen de tu cita',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: CitasColores.azulProfundo,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _filaResumen(
            Icons.local_hospital_outlined,
            'Clínica',
            widget.clinica?.etiqueta ?? 'Clínica de tu sesión',
          ),
          _filaResumen(
            Icons.person_outline,
            'Oftalmólogo',
            oftalmologo.nombreCompleto,
          ),
          _filaResumen(Icons.event, 'Fecha', fechaLargaEspanol(_fecha)),
          _filaResumen(Icons.schedule, 'Horario', ranura.etiqueta),
          if (motivo.isNotEmpty) _filaResumen(Icons.notes, 'Motivo', motivo),
          if (observaciones.isNotEmpty)
            _filaResumen(
              Icons.description_outlined,
              'Observaciones',
              observaciones,
            ),
        ],
      ),
    );
  }

  Widget _filaResumen(IconData icono, String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, size: 16, color: CitasColores.azulPrincipal),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
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
                fontWeight: FontWeight.w600,
                color: CitasColores.azulProfundo,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonConfirmar() {
    final bool habilitado = !_creando && _ranura != null;

    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton(
        onPressed: habilitado ? _confirmarCita : null,
        style: FilledButton.styleFrom(
          backgroundColor: CitasColores.azulProfundo,
          disabledBackgroundColor: CitasColores.grisSuave.withValues(
            alpha: 0.35,
          ),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _creando
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Registrando cita...',
                    style: TextStyle(fontSize: 15),
                  ),
                ],
              )
            : const Text(
                'Confirmar cita',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _bloqueConfirmacion(Cita cita) {
    return TarjetaCitas(
      color: const Color(0xFFE8F6EC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.check_circle,
                color: CitasColores.verde,
                size: 26,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '¡Cita registrada!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CitasColores.verde,
                  ),
                ),
              ),
              ChipEstadoCita(estado: cita.estado, compacto: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${fechaLargaEspanol(cita.fecha)} · ${cita.franja}',
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: CitasColores.grisTexto,
            ),
          ),
          if (_oftalmologo != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Oftalmólogo: ${_oftalmologo!.nombreCompleto}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: CitasColores.grisTexto,
              ),
            ),
          ],
          if (widget.clinica != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              widget.clinica!.etiqueta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: CitasColores.grisSuave,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              if (widget.onVerMisCitas != null)
                FilledButton.icon(
                  onPressed: widget.onVerMisCitas,
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: const Text('Ver mis citas'),
                ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _citaCreada = null),
                child: const Text('Agendar otra'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}




