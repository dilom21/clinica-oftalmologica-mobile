import 'package:flutter/material.dart';

import '../../valoraciones/models/valoracion_models.dart';
import '../../valoraciones/pages/valorar_atencion_page.dart';
import '../../valoraciones/services/valoracion_service.dart';

/// Pantalla de inicio tras la autenticación del paciente.
///
/// Además de la identidad de la clínica, verifica automáticamente si existen
/// avisos post-atención pendientes (CU40) tras finalizar una revisión médica
/// o recibir una receta, mostrando un mensaje in-app para valorar al médico.
class InicioPage extends StatefulWidget {
  const InicioPage({
    super.key,
    this.valoracionService,
    this.onAbrirValoraciones,
    this.onPendientesActualizados,
  });

  final ValoracionService? valoracionService;
  final VoidCallback? onAbrirValoraciones;
  final ValueChanged<int>? onPendientesActualizados;

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> with TickerProviderStateMixin {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);

  late final ValoracionService _valoracionService =
      widget.valoracionService ?? ValoracionService();

  List<NotificacionValoracion> _pendientes = const [];
  final Set<int> _dialogosMostrados = <int>{};

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  late final Animation<double> _logoEntrance = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _titleEntrance = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.25, 0.6, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _cardEntrance = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _logoScale = Tween<double>(
    begin: 0.95,
    end: 1.0,
  ).animate(_logoEntrance);

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _cargarAvisosValoracion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Consulta los avisos post-atención del paciente autenticado (silencioso si
  /// no hay red o sesión todavía).
  Future<void> _cargarAvisosValoracion() async {
    try {
      final pendientes = await _valoracionService.listarPendientes();
      if (!mounted) return;
      setState(() {
        _pendientes = pendientes;
      });
      widget.onPendientesActualizados?.call(pendientes.length);

      // Si hay un aviso no leído aún no mostrado en esta sesión, mostrar
      // el mensaje emergente invitando a valorar la atención recibida.
      final primerNoLeido = pendientes
          .where((item) => !item.leida && !_dialogosMostrados.contains(item.consultaClinicaId))
          .cast<NotificacionValoracion?>()
          .firstOrNull;
      if (primerNoLeido != null && mounted) {
        _dialogosMostrados.add(primerNoLeido.consultaClinicaId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mostrarDialogoInvitacionValoracion(primerNoLeido);
          }
        });
      }
    } catch (_) {
      // No interrumpe la pantalla de inicio si el servidor no responde.
    }
  }

  Future<void> _mostrarDialogoInvitacionValoracion(
    NotificacionValoracion aviso,
  ) async {
    final deseaValorar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: const Icon(
          Icons.star_rounded,
          color: Color(0xFFF59E0B),
          size: 44,
        ),
        title: Text(aviso.titulo, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              aviso.mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5C6F80), height: 1.45),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Dr(a). ${aviso.oftalmologo.nombreCompleto}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _azulProfundo,
                ),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Más tarde'),
          ),
          FilledButton.icon(
            key: const Key('btn_dialogo_valorar_ahora'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.star_rate_rounded, size: 18),
            label: const Text('Valorar ahora'),
            style: FilledButton.styleFrom(
              backgroundColor: _azulPrincipal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (deseaValorar == true) {
      await _abrirValoracionDesdeAviso(aviso);
    } else if (aviso.id != null) {
      try {
        await _valoracionService.marcarNotificacionLeida(aviso.id!);
      } catch (_) {
        // Ignorado silenciosamente.
      }
    }
  }

  Future<void> _abrirValoracionDesdeAviso(NotificacionValoracion aviso) async {
    final resultado = await Navigator.of(context).push<ValoracionClinica>(
      MaterialPageRoute<ValoracionClinica>(
        builder: (_) => ValorarAtencionPage(
          consultaClinicaId: aviso.consultaClinicaId,
          oftalmologo: aviso.oftalmologo,
          fechaConsulta: aviso.fechaConsulta,
          motivoConsulta: aviso.motivoConsulta,
          tieneReceta: aviso.tieneReceta,
          empresaNombre: aviso.empresaNombre,
          valoracionService: _valoracionService,
        ),
      ),
    );

    if (resultado != null && mounted) {
      final mensaje = resultado.mensaje?.trim().isNotEmpty == true
          ? resultado.mensaje!.trim()
          : '¡Gracias! Tu valoración fue registrada correctamente.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(mensaje),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      await _cargarAvisosValoracion();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombreClinica =
        _pendientes.isNotEmpty &&
            (_pendientes.first.empresaNombre?.trim().isNotEmpty == true)
        ? _pendientes.first.empresaNombre!.trim()
        : 'Visión Clara';

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _FondoDecorativo()),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _cargarAvisosValoracion,
              color: _azulPrincipal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),

                        // Logo con fade + escala.
                        FadeTransition(
                          opacity: _logoEntrance,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Center(
                              child: Image.asset(
                                'assets/images/logo_vision_clara.png',
                                height: 92,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Título y subtítulo con fade.
                        FadeTransition(
                          opacity: _titleEntrance,
                          child: Column(
                            children: [
                              Text(
                                'Bienvenido a $nombreClinica',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _azulProfundo,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Centro Oftalmológico',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: const Color(0xFF547799)),
                              ),
                            ],
                          ),
                        ),

                        // Mensaje in-app post-atención para valorar al médico
                        if (_pendientes.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _TarjetaAvisoValoracion(
                            aviso: _pendientes.first,
                            totalPendientes: _pendientes.length,
                            onValorar: () =>
                                _abrirValoracionDesdeAviso(_pendientes.first),
                            onVerTodas: widget.onAbrirValoraciones,
                          ),
                        ],

                        const SizedBox(height: 22),

                        // Tarjeta principal con acceso a valoraciones
                        FadeTransition(
                          opacity: _cardEntrance,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.08),
                              end: Offset.zero,
                            ).animate(_cardEntrance),
                            child: _TarjetaBienvenida(
                              azulProfundo: _azulProfundo,
                              azulPrincipal: _azulPrincipal,
                              onAbrirValoraciones: widget.onAbrirValoraciones,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),
                        Text(
                          'Gracias por confiar en $nombreClinica.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF7893A9)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner destacado cuando el paciente tiene una atención finalizada o receta
/// emitida pendiente de valoración (CU40).
class _TarjetaAvisoValoracion extends StatelessWidget {
  const _TarjetaAvisoValoracion({
    required this.aviso,
    required this.totalPendientes,
    required this.onValorar,
    this.onVerTodas,
  });

  final NotificacionValoracion aviso;
  final int totalPendientes;
  final VoidCallback onValorar;
  final VoidCallback? onVerTodas;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('banner_aviso_valoracion'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8E1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFFD97706),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  aviso.titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            aviso.mensaje,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF5C6F80),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('btn_banner_valorar_ahora'),
            onPressed: onValorar,
            icon: const Icon(Icons.star_rounded, size: 20),
            label: const Text('Valorar atención ahora'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (totalPendientes > 1 && onVerTodas != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: onVerTodas,
              child: Text(
                'Ver todas las pendientes ($totalPendientes)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta principal de bienvenida con acceso directo a valoraciones.
class _TarjetaBienvenida extends StatelessWidget {
  const _TarjetaBienvenida({
    required this.azulProfundo,
    required this.azulPrincipal,
    this.onAbrirValoraciones,
  });

  final Color azulProfundo;
  final Color azulPrincipal;
  final VoidCallback? onAbrirValoraciones;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: azulPrincipal.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
                ),
              ),
              child: Icon(
                Icons.visibility_outlined,
                size: 40,
                color: azulProfundo.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Tu salud visual,\nsiempre acompañada',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: azulProfundo,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Consulta horarios médicos, gestiona tus pagos y comparte tu valoración después de cada atención recibida.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5C6F80),
                height: 1.45,
              ),
            ),
            if (onAbrirValoraciones != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onAbrirValoraciones,
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('Ir a mis valoraciones'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: azulPrincipal,
                  side: BorderSide(color: azulPrincipal),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FondoDecorativo extends StatelessWidget {
  const _FondoDecorativo();

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
          top: -70,
          right: -80,
          child: _FormaCircular(
            size: 280,
            color: const Color(0xFF1976D2).withValues(alpha: 0.10),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -90,
          child: _FormaCircular(
            size: 260,
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.10),
          ),
        ),
        Positioned(
          top: 60,
          left: -60,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1976D2).withValues(alpha: 0.06),
                width: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FormaCircular extends StatelessWidget {
  final double size;
  final Color color;

  const _FormaCircular({required this.size, required this.color});

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
