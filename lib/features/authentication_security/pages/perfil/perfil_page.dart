import 'package:flutter/material.dart';

import '../../../../core/storage/token_storage.dart';
import '../../models/mi_perfil_paciente.dart';
import '../../services/paciente_service.dart';
import '../login/login_page.dart';

/// Perfil del paciente autenticado (SOLO LECTURA).
///
/// Consulta `GET /pacientes/me` con el JWT y muestra los datos reales.
/// También implementa CU02: Cerrar sesión (elimina el JWT local y vuelve
/// a LoginPage limpiando la pila de navegación).
class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage>
    with TickerProviderStateMixin {
  // Colores de la identidad Visión Clara.
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);
  static const Color _verdeActivo = Color(0xFF2E7D32);
  static const Color _rojoSalida = Color(0xFFD32F2F);

  final PacienteService _pacienteService = PacienteService();

  MiPerfilPaciente? _perfil;
  String? _error;
  bool _cargando = true;

  // Animación de entrada (se dispara cuando el perfil está listo).
  late final AnimationController _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  late final Animation<double> _cabeceraEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _avatarEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.05, 0.4, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _datosEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.25, 0.55, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _logoutEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.5, 0.75, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _cuentaEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.68, 0.9, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _contactoEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.8, 1.0, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _avatarScale =
      Tween<double>(begin: 0.95, end: 1.0).animate(_avatarEntrance);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  /// Carga controlada del perfil (una sola vez por apertura de la página).
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _perfil = null;
    });

    try {
      final perfil = await _pacienteService.obtenerMiPerfil();

      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _cargando = false;
      });
      _animacion.forward(from: 0);
    } on PacienteException catch (error) {
      if (!mounted) return;

      // 401 = JWT inválido/expirado: limpiar sesión y volver al Login.
      if (error.statusCode == 401) {
        await _borrarSesionYSalir();
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

  /// Elimina el token local y navega a LoginPage limpiando toda la pila.
  Future<void> _borrarSesionYSalir() async {
    final storage = TokenStorage();
    await storage.deleteToken();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  /// CU02 - Cerrar sesión (solo local, sin endpoint logout).
  Future<void> _cerrarSesion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout, color: Color(0xFFD32F2F), size: 40),
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          '¿Estás seguro de que deseas cerrar tu sesión?',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) {
      return;
    }

    // Eliminar el JWT y garantizar que ya no esté disponible.
    final storage = TokenStorage();
    await storage.deleteToken();
    if (await storage.hasToken()) {
      await storage.deleteToken();
    }

    if (!mounted) return;
    await _borrarSesionYSalir();
  }

  // ---------------------------------------------------------------
  // Presentación (sin alterar los valores del backend)
  // ---------------------------------------------------------------

  static String _formatoFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  static String _labelSexo(String? sexo) {
    switch (sexo) {
      case 'M':
        return 'Masculino';
      case 'F':
        return 'Femenino';
      default:
        return sexo == null || sexo.trim().isEmpty ? 'No registrado' : sexo;
    }
  }

  static String _textoEstado(bool estado) {
    return estado ? 'Activo' : 'Inactivo';
  }

  static String _textoCampo(String? valor) {
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? 'No registrado' : texto;
  }

  // ---------------------------------------------------------------
  // Construcción de la vista
  // ---------------------------------------------------------------

  /// Envuelve un bloque con fade + slide para la entrada escalonada.
  Widget _bloqueAnimado({
    required Animation<double> animation,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _construirContenido() {
    if (_cargando) {
      return _buildCargando();
    }

    if (_error != null || _perfil == null) {
      return _buildError();
    }

    return _buildPerfil(_perfil!);
  }

  /// Loading elegante mientras llega la respuesta de /pacientes/me.
  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: Color(0xFF1976D2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Cargando tu perfil…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5C6F80),
                ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta de error elegante con opción de reintentar.
  Widget _buildError() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 44,
                  color: Color(0xFFE65100),
                ),
                const SizedBox(height: 14),
                Text(
                  'No se pudo cargar tu perfil',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0D47A1),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Inténtalo de nuevo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5C6F80),
                      ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _cargar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Contenido principal del perfil cuando los datos reales están listos.
  Widget _buildPerfil(MiPerfilPaciente perfil) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabecera: título "Perfil".
              FadeTransition(
                opacity: _cabeceraEntrance,
                child: Text(
                  'Perfil',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _azulProfundo,
                      ),
                ),
              ),

              const SizedBox(height: 26),

              // Avatar (fade + escala 0.95 -> 1).
              FadeTransition(
                opacity: _avatarEntrance,
                child: ScaleTransition(
                  scale: _avatarScale,
                  child: Center(
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _azulPrincipal.withValues(alpha: 0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.person_outline,
                        size: 54,
                        color: _azulProfundo.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Nombre completo (real).
              FadeTransition(
                opacity: _datosEntrance,
                child: Text(
                  perfil.nombreCompleto,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B2B3A),
                      ),
                ),
              ),

              const SizedBox(height: 6),

              // Correo real.
              FadeTransition(
                opacity: _datosEntrance,
                child: Text(
                  perfil.correo,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5C6F80),
                      ),
                ),
              ),

              const SizedBox(height: 12),

              // Etiqueta discreta "Paciente".
              FadeTransition(
                opacity: _datosEntrance,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8ECFA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Paciente',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Botón Cerrar sesión en la parte superior del perfil.
              _bloqueAnimado(
                animation: _logoutEntrance,
                child: _buildBotonCerrarSesion(),
              ),

              const SizedBox(height: 26),

              // Tarjeta: Información de tu cuenta.
              _bloqueAnimado(
                animation: _cuentaEntrance,
                child: _tarjetaCuenta(perfil),
              ),

              const SizedBox(height: 18),

              // Tarjeta: Información de contacto.
              _bloqueAnimado(
                animation: _contactoEntrance,
                child: _tarjetaContacto(perfil),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  /// Tarjeta "Información de tu cuenta".
  Widget _tarjetaCuenta(MiPerfilPaciente perfil) {
    return _TarjetaSeccion(
      titulo: 'Información de tu cuenta',
      hijos: [
        _FilaInfo(label: 'CI', value: _textoCampo(perfil.ci)),
        const _SeparadorPerfil(),
        _FilaInfo(
          label: 'Fecha de nacimiento',
          value: _formatoFecha(perfil.fechaNacimiento),
        ),
        const _SeparadorPerfil(),
        _FilaInfo(label: 'Sexo', value: _labelSexo(perfil.sexo)),
        const _SeparadorPerfil(),
        _FilaInfo(
          label: 'Estado',
          value: _textoEstado(perfil.estado),
          colorValor: perfil.estado ? _verdeActivo : _rojoSalida,
        ),
      ],
    );
  }

  /// Tarjeta "Información de contacto".
  Widget _tarjetaContacto(MiPerfilPaciente perfil) {
    return _TarjetaSeccion(
      titulo: 'Información de contacto',
      hijos: [
        _FilaInfo(label: 'Teléfono', value: _textoCampo(perfil.telefono)),
        const _SeparadorPerfil(),
        _FilaInfo(
          label: 'Contacto de emergencia',
          value: _textoCampo(perfil.contactoEmergencia),
        ),
        const _SeparadorPerfil(),
        _FilaInfo(label: 'Dirección', value: _textoCampo(perfil.direccion)),
      ],
    );
  }

  /// Botón "Cerrar sesión" (rojo moderado, coherente con el tema).
  Widget _buildBotonCerrarSesion() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _rojoSalida.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _cerrarSesion,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.logout,
                  size: 20,
                  color: Color(0xFFD32F2F),
                ),
                const SizedBox(width: 10),
                Text(
                  'Cerrar sesión',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _rojoSalida,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fondo degradado discreto y formas suaves.
          const Positioned.fill(child: _FondoPerfil()),

          SafeArea(child: _construirContenido()),
        ],
      ),
    );
  }
}

/// Fondo con degradado suave y formas abstractas del perfil.
class _FondoPerfil extends StatelessWidget {
  const _FondoPerfil();

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
          child: _FormaPerfil(
            size: 280,
            color: const Color(0xFF1976D2).withValues(alpha: 0.09),
          ),
        ),
        Positioned(
          bottom: -70,
          left: -90,
          child: _FormaPerfil(
            size: 260,
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

/// Forma circular con gradiente radial (luz suave).
class _FormaPerfil extends StatelessWidget {
  final double size;
  final Color color;

  const _FormaPerfil({required this.size, required this.color});

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

/// Tarjeta de perfil con título y filas.
class _TarjetaSeccion extends StatelessWidget {
  const _TarjetaSeccion({required this.titulo, required this.hijos});

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D47A1),
                  ),
            ),
            const SizedBox(height: 12),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

/// Separador fino entre filas de información.
class _SeparadorPerfil extends StatelessWidget {
  const _SeparadorPerfil();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: Color(0xFFE4EDF4), height: 1);
  }
}

/// Fila etiqueta/valor de una tarjeta de perfil.
class _FilaInfo extends StatelessWidget {
  const _FilaInfo({
    required this.label,
    required this.value,
    this.colorValor,
  });

  final String label;
  final String value;
  final Color? colorValor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5C6F80),
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorValor ?? const Color(0xFF1B2B3A),
                    fontWeight: colorValor != null ? FontWeight.w600 : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
