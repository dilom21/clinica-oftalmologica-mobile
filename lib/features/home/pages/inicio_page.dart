import 'package:flutter/material.dart';

/// Pantalla temporal que se muestra después del inicio de sesión del paciente.
///
/// Muestra la identidad de Visión Clara y una tarjeta indicando que el sistema
/// móvil está en construcción. No contiene módulos funcionales todavía.
class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage>
    with TickerProviderStateMixin {
  // Colores de la identidad Visión Clara.
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);

  // Controla la animación de entrada escalonada.
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

  late final Animation<double> _logoScale =
      Tween<double>(begin: 0.95, end: 1.0).animate(_logoEntrance);

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
          // Fondo degradado discreto y formas suaves.
          const Positioned.fill(child: _FondoDecorativo()),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),

                    // Logo con fade + escala.
                    FadeTransition(
                      opacity: _logoEntrance,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Center(
                          child: Image.asset(
                            'assets/images/logo_vision_clara.png',
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Título y subtítulo con fade.
                    FadeTransition(
                      opacity: _titleEntrance,
                      child: Column(
                        children: [
                          Text(
                            'Bienvenido a Visión Clara',
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
                                ?.copyWith(
                                  color: const Color(0xFF547799),
                                ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Tarjeta principal con fade + slide desde abajo.
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
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    Text(
                      'Gracias por utilizar Visión Clara.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF7893A9),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta principal de bienvenida / estado de construcción.
class _TarjetaBienvenida extends StatelessWidget {
  const _TarjetaBienvenida({
    required this.azulProfundo,
    required this.azulPrincipal,
  });

  final Color azulProfundo;
  final Color azulPrincipal;

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
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
        child: Column(
          children: [
            // Icono de visión dentro de un círculo suave.
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
                ),
              ),
              child: Icon(
                Icons.visibility_outlined,
                size: 44,
                color: azulProfundo.withValues(alpha: 0.85),
              ),
            ),

            const SizedBox(height: 22),

            Text(
              'Sistema móvil\nen construcción',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: azulProfundo,
                    height: 1.25,
                  ),
            ),

            const SizedBox(height: 14),

            Text(
              'Estamos preparando nuevas funcionalidades '
              'para brindarte una mejor experiencia.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5C6F80),
                    height: 1.45,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fondo con degradado suave y formas abstractas discretas.
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

        // Forma grande azul en la parte superior derecha.
        Positioned(
          top: -70,
          right: -80,
          child: _FormaCircular(
            size: 280,
            color: const Color(0xFF1976D2).withValues(alpha: 0.10),
          ),
        ),

        // Forma celeste abajo izquierda.
        Positioned(
          bottom: -60,
          left: -90,
          child: _FormaCircular(
            size: 260,
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.10),
          ),
        ),

        // Anillo tipo lente (guiño a la visión) arriba izquierda.
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

/// Forma circular con gradiente radial (luz suave).
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

