import 'package:flutter/material.dart';

/// Fondo con degradado de la identidad Visión Clara para las pantallas Pagos.
class FondoPagos extends StatelessWidget {
  const FondoPagos({super.key});

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
          child: _FormaPagos(
            size: 280,
            color: const Color(0xFF1976D2).withValues(alpha: 0.09),
          ),
        ),
        Positioned(
          bottom: -70,
          left: -90,
          child: _FormaPagos(
            size: 260,
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

/// Forma circular con gradiente radial (luz suave).
class _FormaPagos extends StatelessWidget {
  const _FormaPagos({required this.size, required this.color});

  final double size;
  final Color color;

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

/// Indicador de carga centrado con mensaje.
class PagosCargando extends StatelessWidget {
  const PagosCargando({super.key, this.mensaje = 'Cargando información...'});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Color(0xFF1976D2)),
          const SizedBox(height: 16),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5C6F80)),
          ),
        ],
      ),
    );
  }
}

/// Vista de error con mensaje y botón de reintento.
class PagosErrorVista extends StatelessWidget {
  const PagosErrorVista({
    super.key,
    required this.titulo,
    required this.mensaje,
    required this.onReintentar,
  });

  final String titulo;
  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: Color(0xFFD32F2F),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5C6F80), height: 1.4),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vista vacía con ícono y mensaje.
class PagosVacioVista extends StatelessWidget {
  const PagosVacioVista({
    super.key,
    required this.icono,
    required this.mensaje,
  });

  final IconData icono;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icono, size: 46, color: const Color(0xFF8A9BA9)),
          const SizedBox(height: 16),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5C6F80), height: 1.45),
          ),
        ],
      ),
    );
  }
}
