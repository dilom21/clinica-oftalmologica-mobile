import 'package:flutter/material.dart';

import '../../authentication_security/pages/login/login_page.dart';
import '../../../core/storage/token_storage.dart';
import '../models/agenda_models.dart';
import '../services/agenda_service.dart';

/// Pantalla de Citas (CU09 - Consultar agenda y disponibilidad médica).
///
/// Experiencia del Paciente:
/// - lista los oftalmólogos activos;
/// - permite elegir oftalmólogo y fecha;
/// - consulta los intervalos libres reales devueltos por FastAPI.
///
/// NO consume `/agenda` ni muestra citas internas del médico ni datos de
/// otros pacientes. La reserva/cancelación pertenece a CU10 y no se incluye.
class CitasPage extends StatefulWidget {
  const CitasPage({super.key, this.agendaService});

  /// Servicio de agenda; en producción se crea uno por defecto. Permite
  /// inyectar un servicio con `http.Client` fake en las pruebas.
  final AgendaService? agendaService;

  @override
  State<CitasPage> createState() => _CitasPageState();
}

class _CitasPageState extends State<CitasPage> with TickerProviderStateMixin {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);
  static const Color _grisTexto = Color(0xFF5C6F80);
  static const Color _verdeDisponible = Color(0xFF2E7D32);
  static const Color _ambar = Color(0xFFB26A00);

  late final AgendaService _agendaService =
      widget.agendaService ?? AgendaService();

  // Estado de la carga de oftalmólogos.
  List<OftalmologoAgenda> _oftalmologos = const [];
  bool _cargandoOftalmologos = true;
  String? _errorOftalmologos;

  // Selección del formulario.
  OftalmologoAgenda? _oftalmologoSeleccionado;
  DateTime _fechaSeleccionada = DateTime(1900);

  // Estado de la consulta de disponibilidad.
  bool _consultandoDisponibilidad = false;
  DisponibilidadRespuesta? _disponibilidad;
  String? _errorDisponibilidad;

  // Animación de entrada del encabezado.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  late final Animation<double> _titleEntrance = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _fechaSeleccionada = _normalizarFecha(DateTime.now());
    _controller.forward();
    _cargarOftalmologos();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Datos
  // ---------------------------------------------------------------

  /// Carga inicial de oftalmólogos (una sola vez por apertura de la página).
  Future<void> _cargarOftalmologos() async {
    setState(() {
      _cargandoOftalmologos = true;
      _errorOftalmologos = null;
    });

    try {
      final lista = await _agendaService.listarOftalmologos();

      if (!mounted) return;
      setState(() {
        _oftalmologos = lista;
        _cargandoOftalmologos = false;
        _autoseleccionarOftalmologo();
      });
    } on AgendaException catch (error) {
      if (!mounted) return;

      // 401 = JWT inválido/expirado: limpiar sesión y volver al Login.
      if (error.statusCode == 401) {
        await _cerrarSesionPorSesionInvalida();
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

  /// Si no hay oftalmólogo seleccionado (o desapareció de la lista),
  /// selecciona el primero disponible para mejorar la experiencia.
  void _autoseleccionarOftalmologo() {
    if (_oftalmologos.isEmpty) {
      _oftalmologoSeleccionado = null;
      return;
    }

    final sigueExistente =
        _oftalmologoSeleccionado != null &&
        _oftalmologos.any((o) => o.id == _oftalmologoSeleccionado!.id);

    if (!sigueExistente) {
      _oftalmologoSeleccionado = _oftalmologos.first;
    }
  }

  /// Consulta la disponibilidad real del oftalmólogo seleccionado.
  Future<void> _consultarDisponibilidad() async {
    final oftalmologo = _oftalmologoSeleccionado;
    if (oftalmologo == null || _consultandoDisponibilidad) return;

    setState(() {
      _consultandoDisponibilidad = true;
      _errorDisponibilidad = null;
      _disponibilidad = null;
    });

    try {
      final resultado = await _agendaService.obtenerDisponibilidad(
        oftalmologoId: oftalmologo.id,
        fecha: _fechaSeleccionada,
      );

      if (!mounted) return;
      setState(() {
        _disponibilidad = resultado;
        _consultandoDisponibilidad = false;
      });
    } on AgendaException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await _cerrarSesionPorSesionInvalida();
        return;
      }

      setState(() {
        _errorDisponibilidad = error.message;
        _consultandoDisponibilidad = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorDisponibilidad =
            'Ocurrió un error inesperado. Inténtalo de nuevo.';
        _consultandoDisponibilidad = false;
      });
    }
  }

  /// 401 = sesión inválida/expirada: elimina el JWT local y navega a
  /// LoginPage limpiando toda la pila (patrón de PerfilPage).
  Future<void> _cerrarSesionPorSesionInvalida() async {
    final storage = TokenStorage();
    await storage.deleteToken();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _cambiarOftalmologo(OftalmologoAgenda? oftalmologo) {
    setState(() {
      _oftalmologoSeleccionado = oftalmologo;
      _disponibilidad = null;
      _errorDisponibilidad = null;
    });
  }

  Future<void> _seleccionarFecha() async {
    if (_consultandoDisponibilidad) return;

    final hoy = _normalizarFecha(DateTime.now());
    final fechaInicial = _fechaSeleccionada.isBefore(hoy)
        ? hoy
        : _fechaSeleccionada;

    // Rango solo visual del picker: desde hoy. Sin límite de negocio propio:
    // el backend acepta la fecha que se le envíe.
    final elegida = await showDatePicker(
      context: context,
      initialDate: fechaInicial,
      firstDate: hoy,
      lastDate: DateTime(hoy.year + 2, hoy.month, hoy.day),
      helpText: 'Selecciona la fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (elegida == null || !mounted) return;

    setState(() {
      _fechaSeleccionada = _normalizarFecha(elegida);
      _disponibilidad = null;
      _errorDisponibilidad = null;
    });
  }

  // ---------------------------------------------------------------
  // Helpers de presentación
  // ---------------------------------------------------------------

  static DateTime _normalizarFecha(DateTime fecha) {
    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  static String _formatoFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  /// Convierte `HH:MM:SS` (u `HH:MM`) en `HH:mm` para mostrar.
  static String _horaCorta(String hora) {
    final partes = hora.trim().split(':');
    if (partes.length < 2) return hora.trim().isEmpty ? '--:--' : hora.trim();
    final hh = partes[0].padLeft(2, '0');
    final mm = partes[1].padLeft(2, '0');
    return '$hh:$mm';
  }

  static String _textoEspecialidad(OftalmologoAgenda oftalmologo) {
    final especialidad = oftalmologo.especialidad?.trim() ?? '';
    return especialidad.isEmpty ? 'Especialidad no registrada' : especialidad;
  }

  bool get _controlesHabilitados =>
      !_consultandoDisponibilidad && !_cargandoOftalmologos;

  // ---------------------------------------------------------------
  // Construcción
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _FondoCitas()),
          SafeArea(child: _construirContenido()),
        ],
      ),
    );
  }

  Widget _construirContenido() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FadeTransition(
                opacity: _titleEntrance,
                child: Text(
                  'Disponibilidad médica',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _azulProfundo,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FadeTransition(
                opacity: _titleEntrance,
                child: Text(
                  'Consulta los horarios disponibles de nuestros oftalmólogos',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: _grisTexto, height: 1.4),
                ),
              ),
              const SizedBox(height: 26),
              if (_cargandoOftalmologos)
                _buildCargandoOftalmologos()
              else if (_errorOftalmologos != null)
                _buildErrorOftalmologos()
              else if (_oftalmologos.isEmpty)
                _buildSinOftalmologos()
              else ...[
                _buildFormulario(),
                const SizedBox(height: 18),
                _buildSeccionDisponibilidad(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Estados de la carga de oftalmólogos ----

  Widget _buildCargandoOftalmologos() {
    return _tarjeta(
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Color(0xFF1976D2),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Cargando oftalmólogos…',
              style: TextStyle(color: Color(0xFF5C6F80)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOftalmologos() {
    return _tarjeta(
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 42, color: Color(0xFFE65100)),
          const SizedBox(height: 12),
          Text(
            'No se pudieron cargar los oftalmólogos',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: _azulProfundo),
          ),
          const SizedBox(height: 8),
          Text(
            _errorOftalmologos!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: _grisTexto),
          ),
          const SizedBox(height: 18),
          _botonReintentar(_cargarOftalmologos),
        ],
      ),
    );
  }

  Widget _buildSinOftalmologos() {
    return _tarjeta(
      child: Column(
        children: [
          const Icon(
            Icons.medical_services_outlined,
            size: 44,
            color: Color(0xFF5C6F80),
          ),
          const SizedBox(height: 14),
          Text(
            'No hay oftalmólogos disponibles para consultar en este momento.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: _grisTexto, height: 1.4),
          ),
          const SizedBox(height: 18),
          _botonReintentar(_cargarOftalmologos),
        ],
      ),
    );
  }

  // ---- Formulario de consulta ----

  Widget _buildFormulario() {
    final oftalmologo = _oftalmologoSeleccionado;

    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Consulta de disponibilidad',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: _azulProfundo),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<OftalmologoAgenda>(
            key: ValueKey<int?>(oftalmologo?.id),
            initialValue: oftalmologo,
            isExpanded: true,
            isDense: true,
            menuMaxHeight: 320,
            decoration: InputDecoration(
              labelText: 'Oftalmólogo',
              hintText: 'Selecciona un oftalmólogo',
              prefixIcon: const Icon(Icons.medical_services_outlined),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFC9DCEE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFC9DCEE)),
              ),
            ),
            items: [
              for (final item in _oftalmologos)
                DropdownMenuItem<OftalmologoAgenda>(
                  value: item,
                  child: Text(
                    item.nombreCompleto,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF1B2B3A)),
                  ),
                ),
            ],
            onChanged: _controlesHabilitados ? _cambiarOftalmologo : null,
          ),

          if (oftalmologo != null) ...[
            const SizedBox(height: 6),
            Text(
              'Especialidad: ${_textoEspecialidad(oftalmologo)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF5C6F80)),
            ),
          ],

          const SizedBox(height: 16),

          _buildSelectorFecha(),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed:
                (_oftalmologoSeleccionado != null && _controlesHabilitados)
                ? _consultarDisponibilidad
                : null,
            icon: const Icon(Icons.search),
            label: const Text('Consultar disponibilidad'),
            style: FilledButton.styleFrom(
              backgroundColor: _azulPrincipal,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB9CDE4),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorFecha() {
    final habilitado = _controlesHabilitados;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: habilitado ? _seleccionarFecha : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFC9DCEE)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: Color(0xFF0D47A1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    const Text(
                      'Fecha',
                      style: TextStyle(fontSize: 12, color: Color(0xFF5C6F80)),
                    ),
                    Text(
                      _formatoFecha(_fechaSeleccionada),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B2B3A),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              const Icon(Icons.expand_more, size: 20, color: Color(0xFF8A9BA9)),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Resultado de disponibilidad ----

  Widget _buildSeccionDisponibilidad() {
    if (_consultandoDisponibilidad) {
      return _tarjeta(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Color(0xFF1976D2),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Consultando disponibilidad…',
                style: TextStyle(color: Color(0xFF5C6F80)),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorDisponibilidad != null) {
      return _tarjeta(
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: Color(0xFFE65100),
            ),
            const SizedBox(height: 12),
            Text(
              'No se pudo consultar la disponibilidad',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: _azulProfundo),
            ),
            const SizedBox(height: 8),
            Text(
              _errorDisponibilidad!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: _grisTexto),
            ),
            const SizedBox(height: 18),
            _botonReintentar(_consultarDisponibilidad),
          ],
        ),
      );
    }

    final disponibilidad = _disponibilidad;
    if (disponibilidad == null) {
      return _tarjeta(
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF0D47A1)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Selecciona un oftalmólogo y una fecha, y presiona '
                '“Consultar disponibilidad”.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: _grisTexto, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return _buildResultado(disponibilidad);
  }

  Widget _buildResultado(DisponibilidadRespuesta resultado) {
    final oftalmologo = resultado.oftalmologo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Información del médico.
        _tarjeta(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
                      ),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: Color(0xFF0D47A1),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          oftalmologo.nombreCompleto,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1B2B3A),
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _textoEspecialidad(oftalmologo),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF5C6F80),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 16,
                      color: Color(0xFF0D47A1),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Matrícula: ${oftalmologo.matricula}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Disponibilidad para el ${_formatoFecha(resultado.fecha)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF7893A9)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Horario base del día.
        if (resultado.horariosBase.isNotEmpty) ...[
          _tarjetaHorarioBase(resultado.horariosBase),
          const SizedBox(height: 14),
        ],

        // Disponibilidad.
        if (!resultado.tieneHorario)
          _buildEstadoSinHorario()
        else if (resultado.intervalosDisponibles.isEmpty)
          _buildEstadoSinDisponibilidad()
        else
          _buildIntervalosDisponibles(resultado.intervalosDisponibles),
      ],
    );
  }

  Widget _tarjetaHorarioBase(List<IntervaloHorario> horariosBase) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 20, color: Color(0xFF0D47A1)),
              const SizedBox(width: 8),
              Text(
                'Horario base',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _azulProfundo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final intervalo in horariosBase)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FD),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD0E7F8)),
                  ),
                  child: Text(
                    '${_horaCorta(intervalo.horaInicio)} – '
                    '${_horaCorta(intervalo.horaFin)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoSinHorario() {
    return _tarjeta(
      child: Column(
        children: [
          const Icon(Icons.event_busy_outlined, size: 42, color: _ambar),
          const SizedBox(height: 12),
          Text(
            'Sin horario configurado',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF8A5A00),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'El oftalmólogo no tiene horario para la fecha seleccionada. '
            'Elige otra fecha para consultar su disponibilidad.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: _grisTexto, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoSinDisponibilidad() {
    return _tarjeta(
      child: Column(
        children: [
          const Icon(Icons.event_busy_outlined, size: 42, color: _ambar),
          const SizedBox(height: 12),
          Text(
            'Sin horarios disponibles',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF8A5A00),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'El oftalmólogo tiene horario, pero no quedan intervalos '
            'libres para la fecha seleccionada.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: _grisTexto, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildIntervalosDisponibles(List<IntervaloHorario> intervalos) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_available,
                size: 20,
                color: Color(0xFF2E7D32),
              ),
              const SizedBox(width: 8),
              Text(
                'Intervalos disponibles',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _verdeDisponible,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < intervalos.length; i++) ...[
            if (i > 0) const Divider(color: Color(0xFFE4EDF4), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_horaCorta(intervalos[i].horaInicio)} – '
                      '${_horaCorta(intervalos[i].horaFin)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B2B3A),
                      ),
                    ),
                  ),
                  const Text(
                    'Disponible',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Widgets compartidos ----

  Widget _tarjeta({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _azulPrincipal.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }

  Widget _botonReintentar(VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar'),
        style: FilledButton.styleFrom(
          backgroundColor: _azulPrincipal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Fondo con degradado suave y formas abstractas de Citas.
class _FondoCitas extends StatelessWidget {
  const _FondoCitas();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF4F9FF),
                  Color(0xFFE3F1FC),
                  Color(0xFFD0EAF8),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -90,
          child: _FormaCitas(
            size: 280,
            color: const Color(0xFF1976D2).withValues(alpha: 0.09),
          ),
        ),
        Positioned(
          bottom: -70,
          left: -90,
          child: _FormaCitas(
            size: 260,
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

/// Forma circular con gradiente radial (luz suave).
class _FormaCitas extends StatelessWidget {
  final double size;
  final Color color;

  const _FormaCitas({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(0.3, -0.3),
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
