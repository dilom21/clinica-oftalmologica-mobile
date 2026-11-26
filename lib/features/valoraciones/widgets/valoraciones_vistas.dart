import 'package:flutter/material.dart';

/// Fondo con degradado y formas suaves de la identidad Visión Clara
/// para las pantallas del módulo CU40 — Valoraciones.
class FondoValoraciones extends StatelessWidget {
  const FondoValoraciones({super.key});

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
          child: _FormaRadial(
            size: 280,
            color: const Color(0xFF1976D2).withValues(alpha: 0.09),
          ),
        ),
        Positioned(
          bottom: -70,
          left: -90,
          child: _FormaRadial(
            size: 260,
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

class _FormaRadial extends StatelessWidget {
  const _FormaRadial({required this.size, required this.color});

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

/// Chip de estado o etiqueta compacto con icono.
class ValoracionEstadoChip extends StatelessWidget {
  const ValoracionEstadoChip({
    super.key,
    required this.texto,
    required this.color,
    required this.fondo,
    this.icono,
  });

  final String texto;
  final Color color;
  final Color fondo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador de carga centrado.
class ValoracionesCargando extends StatelessWidget {
  const ValoracionesCargando({
    super.key,
    this.mensaje = 'Cargando tus valoraciones…',
  });

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: Color(0xFF1976D2),
            ),
          ),
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

/// Tarjeta de error con mensaje informativo y botón de reintento.
class ValoracionesErrorVista extends StatelessWidget {
  const ValoracionesErrorVista({
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFF3E0),
            ),
            child: const Icon(
              Icons.cloud_off_outlined,
              size: 30,
              color: Color(0xFFE65100),
            ),
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
            style: const TextStyle(color: Color(0xFF5C6F80), height: 1.45),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('btn_reintentar_lista_valoraciones'),
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

/// Estado vacío amigable para pendientes o historial de valoraciones.
class ValoracionesVacioVista extends StatelessWidget {
  const ValoracionesVacioVista({
    super.key,
    required this.icono,
    required this.titulo,
    required this.mensaje,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
              ),
            ),
            child: Icon(icono, size: 32, color: const Color(0xFF0D47A1)),
          ),
          const SizedBox(height: 16),
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
            style: const TextStyle(color: Color(0xFF5C6F80), height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Formatea fecha local como `dd/MM/yyyy`.
String formatearFechaCortaValoracion(DateTime fecha) {
  final local = fecha.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m/${local.year}';
}

/// Formatea fecha y hora local como `dd/MM/yyyy · HH:mm`.
String formatearFechaHoraValoracion(DateTime fecha) {
  final local = fecha.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$d/$m/${local.year} · $hh:$mm';
}
