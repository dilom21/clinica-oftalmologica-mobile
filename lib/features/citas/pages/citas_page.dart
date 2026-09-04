import 'package:flutter/material.dart';

/// Pantalla temporal de Citas.
///
/// Por ahora NO consume endpoints ni gestiona citas reales; solo muestra una
/// interfaz coherente con Inicio y Perfil.
class CitasPage extends StatefulWidget {
  const CitasPage({super.key});

  @override
  State<CitasPage> createState() => _CitasPageState();
}

class _CitasPageState extends State<CitasPage>
    with TickerProviderStateMixin {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  late final Animation<double> _titleEntrance = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _cardEntrance = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _FondoCitas()),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),

                      // Título.
                      FadeTransition(
                        opacity: _titleEntrance,
                        child: Text(
                          'Citas',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _azulProfundo,
                              ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      FadeTransition(
                        opacity: _titleEntrance,
                        child: Text(
                          'Consulta y gestiona tus citas',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: const Color(0xFF5C6F80)),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Tarjeta central.
                      FadeTransition(
                        opacity: _cardEntrance,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(_cardEntrance),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: _azulPrincipal.withValues(alpha: 0.10),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                                vertical: 36,
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFD6ECFA),
                                          Color(0xFFB7E3F9),
                                        ],
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.calendar_month_outlined,
                                      size: 46,
                                      color: _azulProfundo.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Módulo de citas\nen construcción',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: _azulProfundo,
                                          height: 1.25,
                                        ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Próximamente podrás consultar y '
                                    'gestionar tus citas desde aquí.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF5C6F80),
                                          height: 1.45,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// Fondo con degradado suave y formas abstractas.
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

