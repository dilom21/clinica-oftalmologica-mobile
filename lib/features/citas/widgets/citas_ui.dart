import 'package:flutter/material.dart';

import '../models/cita_models.dart';

/// Paleta y componentes visuales compartidos del módulo Citas.
///
/// Mantiene la identidad de la app (azul profundo / azul principal / fondos
/// celestes muy suaves) sin depender de una clínica concreta.
class CitasColores {
  const CitasColores._();

  static const Color azulProfundo = Color(0xFF0D47A1);
  static const Color azulPrincipal = Color(0xFF1976D2);
  static const Color celeste = Color(0xFF4FC3F7);
  static const Color grisTexto = Color(0xFF5C6F80);
  static const Color grisSuave = Color(0xFF8A9BA9);
  static const Color borde = Color(0xFFE1ECF5);
  static const Color verde = Color(0xFF2E7D32);
  static const Color ambar = Color(0xFFB26A00);
  static const Color rojo = Color(0xFFC62828);
  static const Color fondoSuave = Color(0xFFF2F8FE);
}

/// Color discreto asociado al estado REAL de una cita.
Color colorEstadoCita(String estado) {
  switch (estado.trim().toUpperCase()) {
    case citaProgramada:
      return CitasColores.azulPrincipal;
    case citaConfirmada:
      return CitasColores.verde;
    case citaEnEspera:
      return CitasColores.ambar;
    case citaAtendida:
      return CitasColores.azulProfundo;
    case citaCancelada:
      return CitasColores.rojo;
    case citaNoAsistio:
      return CitasColores.ambar;
    default:
      return CitasColores.grisSuave;
  }
}

/// Etiqueta con el estado real de la cita (sin alterar sus valores).
class ChipEstadoCita extends StatelessWidget {
  const ChipEstadoCita({super.key, required this.estado, this.compacto = false});

  final String estado;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final Color color = colorEstadoCita(estado);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 10 : 12,
        vertical: compacto ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            etiquetaEstadoCita(estado),
            style: TextStyle(
              fontSize: compacto ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo con degradado suave y formas abstractas.
class FondoCitas extends StatelessWidget {
  const FondoCitas({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
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
          child: _FormaFondo(
            size: 280,
            color: CitasColores.azulPrincipal.withValues(alpha: 0.09),
          ),
        ),
        Positioned(
          bottom: -70,
          left: -90,
          child: _FormaFondo(
            size: 260,
            color: CitasColores.celeste.withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

class _FormaFondo extends StatelessWidget {
  const _FormaFondo({required this.size, required this.color});

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
          colors: <Color>[color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// Tarjeta blanca de esquinas redondeadas con sombra discreta.
class TarjetaCitas extends StatelessWidget {
  const TarjetaCitas({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color = Colors.white,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radio = BorderRadius.circular(22);
    final Widget contenido = Container(
      padding: padding,
      child: child,
    );

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radio,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: CitasColores.azulPrincipal.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radio,
        child: onTap == null
            ? contenido
            : InkWell(
                onTap: onTap,
                borderRadius: radio,
                child: contenido,
              ),
      ),
    );
  }
}

/// Estado vacío / de error / informativo, con acción opcional.
class MensajeEstado extends StatelessWidget {
  const MensajeEstado({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.accion,
    this.colorIcono = CitasColores.azulPrincipal,
  });

  final IconData icono;
  final String titulo;
  final String? mensaje;
  final Widget? accion;
  final Color colorIcono;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorIcono.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icono, size: 34, color: colorIcono),
        ),
        const SizedBox(height: 14),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: CitasColores.azulProfundo,
          ),
        ),
        if (mensaje != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            mensaje!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: CitasColores.grisTexto,
            ),
          ),
        ],
        if (accion != null) ...<Widget>[
          const SizedBox(height: 16),
          accion!,
        ],
      ],
    );
  }
}
