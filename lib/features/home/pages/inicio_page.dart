import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../../citas/models/agenda_models.dart';
import '../../citas/models/cita_models.dart';
import '../../citas/services/agenda_service.dart';
import '../../citas/widgets/citas_ui.dart';
import '../../informacion_clinica/pages/informacion_clinica_page.dart';
import '../../perfil_paciente/models/mi_perfil_paciente.dart';
import '../../perfil_paciente/services/paciente_service.dart';

/// Panel de Inicio del paciente autenticado.
///
/// Es un panel real: no hay textos de "sistema en construcción". Se alimenta
/// únicamente de datos del backend:
///
/// - `GET /pacientes/me`       -> saludo con el nombre y las iniciales reales.
/// - `GET /agenda-citas/citas` -> próxima cita vigente del paciente.
///
/// El nombre del oftalmólogo no viene en `CitaResponse`: se cruza
/// `oftalmologo_id` con `GET /agenda-citas/oftalmologos` (dato real). Si esa
/// consulta falla se muestra `Oftalmólogo asignado`, nunca un nombre inventado.
///
/// La clínica mostrada proviene siempre de [ClinicaSesion] (sesión guardada por
/// el login multitenant), nunca de un texto fijo.
///
/// Reglas de robustez:
/// - El perfil es información complementaria: si falla, el saludo cae en la
///   identidad de la clínica y el panel sigue funcionando.
/// - Un 401 NO expulsa al paciente desde Inicio: el panel se ve incluso
///   mientras la sesión se está leyendo del almacenamiento seguro. Quien exige
///   datos (Citas, Pagos, Perfil) es quien cierra la sesión.
class InicioPage extends StatefulWidget {
  const InicioPage({
    super.key,
    this.clinica,
    this.pacienteService,
    this.agendaService,
    this.onAgendarCita,
    this.onVerMisCitas,
    this.onVerPagos,
    this.onVerInformacionClinica,
  });

  /// Clínica de la sesión activa.
  ///
  /// Es `null` mientras se lee la sesión guardada o cuando la app no pudo
  /// identificar la clínica; en ese caso se muestra una bienvenida genérica.
  final ClinicaSesion? clinica;

  /// Servicio del paciente (`GET /pacientes/me`); inyectable en pruebas.
  final PacienteService? pacienteService;

  /// Servicio de agenda/citas; inyectable en pruebas.
  final AgendaService? agendaService;

  /// Abre el flujo de agendamiento (pestaña Citas).
  final VoidCallback? onAgendarCita;

  /// Abre el listado de citas del paciente (pestaña Citas).
  final VoidCallback? onVerMisCitas;

  /// Abre el historial de pagos (pestaña Pagos).
  final VoidCallback? onVerPagos;

  /// Abre la información clínica de la clínica.
  final VoidCallback? onVerInformacionClinica;

  @override
  State<InicioPage> createState() => InicioPageState();
}

class InicioPageState extends State<InicioPage> {
  late final PacienteService _paciente =
      widget.pacienteService ?? PacienteService();
  late final AgendaService _agenda = widget.agendaService ?? AgendaService();

  MiPerfilPaciente? _perfil;
  List<Cita> _citas = const <Cita>[];
  Map<int, OftalmologoAgenda> _oftalmologos = const <int, OftalmologoAgenda>{};

  /// Solo el panel de la próxima cita usa estado de carga/error: el resto del
  /// dashboard es contenido estático y no debe parpadear.
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // -------------------------------------------------------------------
  // API pública para el contenedor de pestañas
  // -------------------------------------------------------------------

  /// Refresco silencioso cuando el paciente vuelve a la pestaña Inicio.
  ///
  /// El panel debe mostrar la cita recién reservada sin reiniciar la app, pero
  /// sin tapar la pantalla con un indicador de carga.
  void alMostrarPestana() {
    _cargar(silencioso: true);
  }

  // -------------------------------------------------------------------
  // Datos reales
  // -------------------------------------------------------------------

  /// Carga el perfil y las citas del paciente autenticado.
  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    // 1) Perfil: complementario. Un fallo aquí no rompe el panel.
    MiPerfilPaciente? perfil;
    try {
      perfil = await _paciente.obtenerMiPerfil();
    } on PacienteException {
      perfil = null;
    } catch (_) {
      perfil = null;
    }

    if (!mounted) return;

    // 2) Citas: es el dato principal del panel.
    try {
      final List<Cita> citas = await _agenda.listarCitas();
      final Map<int, OftalmologoAgenda> medicos = await _nombresMedicos(citas);

      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _citas = citas;
        _oftalmologos = medicos;
        _cargando = false;
        _error = null;
      });
    } on AgendaException catch (error) {
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _cargando = false;
        _error = error.statusCode == 401
            ? 'Inicia sesión de nuevo para ver tus citas.'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _cargando = false;
        _error = 'No se pudo cargar tu agenda. Inténtalo de nuevo.';
      });
    }
  }

  /// Cruza `oftalmologo_id` con el catálogo real de oftalmólogos.
  ///
  /// Solo se pide el catálogo si hay citas que mostrar; si falla, el nombre del
  /// médico se omite y se usa `Oftalmólogo asignado` (nunca se inventa).
  Future<Map<int, OftalmologoAgenda>> _nombresMedicos(List<Cita> citas) async {
    if (citas.isEmpty) return _oftalmologos;
    if (_oftalmologos.isNotEmpty) return _oftalmologos;

    try {
      final List<OftalmologoAgenda> lista = await _agenda.listarOftalmologos();
      return <int, OftalmologoAgenda>{
        for (final OftalmologoAgenda oftalmologo in lista)
          oftalmologo.id: oftalmologo,
      };
    } catch (_) {
      return _oftalmologos;
    }
  }

  // -------------------------------------------------------------------
  // Datos derivados
  // -------------------------------------------------------------------

  /// Cita vigente más cercana (futura y no cancelada / atendida / no asistida).
  Cita? get _proximaCita {
    final List<Cita> vigentes = <Cita>[
      for (final Cita cita in _citas)
        if (cita.estaVigente && cita.esFutura) cita,
    ]..sort((Cita a, Cita b) => a.inicio.compareTo(b.inicio));

    return vigentes.isEmpty ? null : vigentes.first;
  }

  /// Saludo del panel: nombre real del paciente y, si no está disponible, la
  /// identidad de la clínica autenticada o una bienvenida genérica.
  String get _saludo {
    final MiPerfilPaciente? perfil = _perfil;
    final String nombre = perfil == null
        ? ''
        : _capitalizar(_primerNombre(perfil.nombres));

    if (nombre.isNotEmpty) return 'Hola, $nombre';

    final ClinicaSesion? clinica = widget.clinica;
    if (clinica != null && clinica.etiqueta.trim().isNotEmpty) {
      return 'Bienvenido a ${clinica.etiqueta.trim()}';
    }

    return 'Bienvenido';
  }

  /// Iniciales del paciente para el avatar (`AQ`); vacío si no hay perfil.
  String get _iniciales {
    final MiPerfilPaciente? perfil = _perfil;
    if (perfil == null) return '';

    final String nombres = _primerNombre(perfil.nombres);
    final String apellidos = _primerNombre(perfil.apellidos);
    final String iniciales = '${_letra(nombres)}${_letra(apellidos)}';
    return iniciales.toUpperCase();
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
            child: RefreshIndicator(
              color: CitasColores.azulProfundo,
              onRefresh: () => _cargar(silencioso: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
                children: <Widget>[
                  _encabezado(),
                  const SizedBox(height: 18),
                  _tarjetaProximaCita(),
                  const SizedBox(height: 22),
                  _accionesRapidas(),
                  const SizedBox(height: 22),
                  _consejos(),
                  const SizedBox(height: 20),
                  _pie(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado() {
    final ClinicaSesion? clinica = widget.clinica;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _avatar(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Portal del paciente',
                style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w700,
                  color: CitasColores.grisSuave,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _saludo,
                key: const Key('inicio-bienvenida'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                  color: CitasColores.azulProfundo,
                ),
              ),
              if (clinica != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  clinica.etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: CitasColores.grisTexto,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          key: const Key('inicio-actualizar'),
          tooltip: 'Actualizar',
          onPressed: _cargando ? null : () => _cargar(),
          icon: const Icon(Icons.refresh, color: CitasColores.azulPrincipal),
        ),
      ],
    );
  }

  Widget _avatar() {
    final String iniciales = _iniciales;

    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[CitasColores.azulProfundo, CitasColores.azulPrincipal],
        ),
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: CitasColores.azulPrincipal.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: iniciales.isEmpty
          ? const Icon(
              Icons.remove_red_eye_outlined,
              color: Colors.white,
              size: 26,
            )
          : Text(
              iniciales,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  /// Tarjeta principal del panel: estado de carga, error, sin citas o próxima
  /// cita real.
  Widget _tarjetaProximaCita() {
    if (_cargando) {
      return TarjetaCitas(
        key: const Key('inicio-proxima-cita'),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: CitasColores.fondoSuave,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_note_outlined,
                color: CitasColores.azulPrincipal,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Revisando tu agenda',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CitasColores.azulProfundo,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Estamos consultando tus citas programadas.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: CitasColores.grisTexto,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final String? error = _error;
    if (error != null) {
      return TarjetaCitas(
        key: const Key('inicio-proxima-cita'),
        child: MensajeEstado(
          icono: Icons.cloud_off_outlined,
          titulo: 'No pudimos cargar tu agenda',
          mensaje: error,
          accion: FilledButton.tonalIcon(
            key: const Key('inicio-reintentar'),
            onPressed: () => _cargar(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ),
      );
    }

    final Cita? proxima = _proximaCita;
    if (proxima == null) {
      return TarjetaCitas(
        key: const Key('inicio-proxima-cita'),
        child: MensajeEstado(
          icono: Icons.event_available_outlined,
          titulo: 'Aún no tienes citas programadas',
          mensaje:
              'Agenda una consulta con un oftalmólogo y tu próxima cita '
              'aparecerá aquí.',
          accion: FilledButton.icon(
            key: const Key('inicio-agendar-cita'),
            onPressed: _abrirAgendarCita,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Agendar cita'),
          ),
        ),
      );
    }

    return _tarjetaHero(proxima);
  }

  /// Tarjeta destacada con la próxima cita real del paciente.
  Widget _tarjetaHero(Cita proxima) {
    final OftalmologoAgenda? medico = _oftalmologos[proxima.oftalmologoId];
    final String nombreMedico = medico == null || medico.nombreCompleto.isEmpty
        ? 'Oftalmólogo asignado'
        : 'Dr(a). ${medico.nombreCompleto}';

    return Container(
      key: const Key('inicio-proxima-cita'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[CitasColores.azulProfundo, CitasColores.azulPrincipal],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: CitasColores.azulPrincipal.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _abrirMisCitas,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _heroCabecera(proxima),
                const SizedBox(height: 16),
                _heroDatos(proxima: proxima, nombreMedico: nombreMedico),
                const SizedBox(height: 18),
                _heroAcciones(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cabecera del héroe: etiqueta de sección + estado real de la cita.
  Widget _heroCabecera(Cita proxima) {
    final Color colorEstado = colorEstadoCita(proxima.estado);

    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.visibility_outlined,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'TU PRÓXIMA CITA',
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Color(0xFFD6E9FA),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            etiquetaEstadoCita(proxima.estado),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorEstado,
            ),
          ),
        ),
      ],
    );
  }

  /// Fecha, horario, oftalmólogo y motivo reales de la cita.
  Widget _heroDatos({required Cita proxima, required String nombreMedico}) {
    final String? motivo = proxima.motivo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          fechaLargaEspanol(proxima.fecha),
          style: const TextStyle(
            fontSize: 19,
            height: 1.25,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        _heroLinea(icono: Icons.schedule, texto: proxima.franja, resaltado: true),
        const SizedBox(height: 8),
        _heroLinea(
          icono: Icons.medical_services_outlined,
          texto: nombreMedico,
        ),
        if (motivo != null) ...<Widget>[
          const SizedBox(height: 8),
          _heroLinea(icono: Icons.notes_outlined, texto: motivo, tenue: true),
        ],
      ],
    );
  }

  /// Línea de dato dentro del héroe (icono + texto de una sola línea).
  Widget _heroLinea({
    required IconData icono,
    required String texto,
    bool resaltado = false,
    bool tenue = false,
  }) {
    final Color colorTexto = tenue
        ? const Color(0xFFE8F4FD)
        : Colors.white;

    return Row(
      children: <Widget>[
        Icon(icono, size: 16, color: const Color(0xFFD6E9FA)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: resaltado ? 15 : (tenue ? 13 : 14),
              fontWeight: resaltado ? FontWeight.w600 : FontWeight.w400,
              color: colorTexto,
            ),
          ),
        ),
      ],
    );
  }

  /// Accesos del héroe al listado de citas y al agendamiento.
  Widget _heroAcciones() {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            key: const Key('inicio-ver-mis-citas'),
            onPressed: _abrirMisCitas,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: CitasColores.azulProfundo,
            ),
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('Ver mis citas'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('inicio-agendar-otra'),
            onPressed: _abrirAgendarCita,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.65)),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agendar'),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Navegación (delegada al contenedor de pestañas)
  // -------------------------------------------------------------------

  void _abrirAgendarCita() {
    final VoidCallback? callback = widget.onAgendarCita;
    if (callback != null) {
      callback();
      return;
    }
    _aviso('Abre la pestaña Citas para agendar.');
  }

  void _abrirMisCitas() {
    final VoidCallback? callback = widget.onVerMisCitas;
    if (callback != null) {
      callback();
      return;
    }
    _aviso('Abre la pestaña Citas para ver tus citas.');
  }

  void _abrirPagos() {
    final VoidCallback? callback = widget.onVerPagos;
    if (callback != null) {
      callback();
      return;
    }
    _aviso('Abre la pestaña Pagos para consultar tus pagos.');
  }

  void _abrirInformacionClinica() {
    final VoidCallback? callback = widget.onVerInformacionClinica;
    if (callback != null) {
      callback();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const InformacionClinicaPage(),
      ),
    );
  }

  /// Aviso breve cuando Inicio se usa sin el contenedor de pestañas.
  void _aviso(String mensaje) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  // -------------------------------------------------------------------
  // Utilidades de texto
  // -------------------------------------------------------------------

  /// Primera palabra de un nombre (`Ana María Quispe` -> `Ana`).
  static String _primerNombre(String valor) {
    final List<String> partes = valor
        .trim()
        .split(RegExp(r'\s+'))
        .where((String parte) => parte.isNotEmpty)
        .toList();
    return partes.isEmpty ? '' : partes.first;
  }

  /// Primera letra de un texto (o vacío).
  static String _letra(String valor) {
    final String texto = valor.trim();
    return texto.isEmpty ? '' : texto.substring(0, 1);
  }

  /// Capitaliza la primera letra respetando el resto del texto.
  static String _capitalizar(String valor) {
    final String texto = valor.trim();
    if (texto.isEmpty) return '';
    return '${texto.substring(0, 1).toUpperCase()}'
        '${texto.substring(1).toLowerCase()}';
  }

  // -------------------------------------------------------------------
  // Secciones del panel
  // -------------------------------------------------------------------

  Widget _accionesRapidas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _tituloSeccion('Acciones rápidas'),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _AccionRapida(
                clave: 'inicio-accion-agendar',
                icono: Icons.add_circle_outline,
                titulo: 'Agendar cita',
                subtitulo: 'Elige día y hora',
                color: CitasColores.azulPrincipal,
                onTap: _abrirAgendarCita,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AccionRapida(
                clave: 'inicio-accion-mis-citas',
                icono: Icons.event_note_outlined,
                titulo: 'Mis citas',
                subtitulo: 'Revisa o cancela',
                color: CitasColores.celeste,
                onTap: _abrirMisCitas,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _AccionRapida(
                clave: 'inicio-accion-pagos',
                icono: Icons.payments_outlined,
                titulo: 'Pagos',
                subtitulo: 'Consultas y estados',
                color: CitasColores.verde,
                onTap: _abrirPagos,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AccionRapida(
                clave: 'inicio-accion-informacion',
                icono: Icons.medical_information_outlined,
                titulo: 'Información clínica',
                subtitulo: 'Servicios y horarios',
                color: CitasColores.ambar,
                onTap: _abrirInformacionClinica,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _consejos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _tituloSeccion('Cuidados para tu salud visual'),
        const SizedBox(height: 12),
        TarjetaCitas(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < _consejosVisuales.length; i++) ...<Widget>[
                if (i > 0) const Divider(height: 1, color: CitasColores.borde),
                _ConsejoTile(consejo: _consejosVisuales[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pie() {
    return const Center(
      child: Text(
        'Gracias por confiar en nosotros.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: CitasColores.grisSuave),
      ),
    );
  }

  Widget _tituloSeccion(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: CitasColores.azulProfundo,
      ),
    );
  }
}

/// Recomendaciones generales de cuidado visual (información educativa, no un
/// diagnóstico ni un tratamiento indicado al paciente).
const List<_Consejo> _consejosVisuales = <_Consejo>[
  _Consejo(
    icono: Icons.timer_outlined,
    titulo: 'Regla 20-20-20',
    detalle:
        'Cada 20 minutos, descansa la vista mirando algo lejano durante '
        '20 segundos.',
  ),
  _Consejo(
    icono: Icons.wb_sunny_outlined,
    titulo: 'Protección solar',
    detalle: 'Usa lentes con filtro UV cuando estés al aire libre.',
  ),
  _Consejo(
    icono: Icons.visibility_outlined,
    titulo: 'Controles periódicos',
    detalle: 'Una revisión anual ayuda a detectar cambios a tiempo.',
  ),
];

/// Acceso rápido del panel de Inicio.
class _AccionRapida extends StatelessWidget {
  const _AccionRapida({
    required this.clave,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  final String clave;
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radio = BorderRadius.circular(20);

    return SizedBox(
      height: 118,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radio,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: CitasColores.azulPrincipal.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radio,
          child: InkWell(
            key: Key(clave),
            borderRadius: radio,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icono, size: 20, color: color),
                  ),
                  const Spacer(),
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CitasColores.azulProfundo,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: CitasColores.grisTexto,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Consejo de cuidado visual mostrado en Inicio.
class _Consejo {
  const _Consejo({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
}

/// Fila de un consejo de cuidado visual.
class _ConsejoTile extends StatelessWidget {
  const _ConsejoTile({required this.consejo});

  final _Consejo consejo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: CitasColores.fondoSuave,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              consejo.icono,
              size: 18,
              color: CitasColores.azulPrincipal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  consejo.titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CitasColores.azulProfundo,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  consejo.detalle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: CitasColores.grisTexto,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
