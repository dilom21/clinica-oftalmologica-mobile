import 'package:flutter/material.dart';

import '../models/pago_models.dart';

/// Chip reutilizable para representar estados del módulo Pagos.
class PagoChip extends StatelessWidget {
  const PagoChip({
    super.key,
    required this.texto,
    required this.color,
    required this.fondo,
    required this.icono,
  });

  final String texto;
  final Color color;
  final Color fondo;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip del estado de pago de un servicio (Pendiente/Pagado).
class EstadoServicioChip extends StatelessWidget {
  const EstadoServicioChip({super.key, required this.estado});

  final EstadoServicioPago estado;

  @override
  Widget build(BuildContext context) {
    final pagado = estado == EstadoServicioPago.pagado;

    return PagoChip(
      texto: estado.etiqueta,
      color: pagado ? const Color(0xFF2E7D32) : const Color(0xFFB26A00),
      fondo: pagado ? const Color(0xFFE6F4EA) : const Color(0xFFFDF3E5),
      icono: pagado ? Icons.check_circle_outline : Icons.schedule,
    );
  }
}

/// Chip del estado general de una operación de pago.
class EstadoPagoChip extends StatelessWidget {
  const EstadoPagoChip({super.key, required this.estado});

  final EstadoPagoApi estado;

  @override
  Widget build(BuildContext context) {
    switch (estado) {
      case EstadoPagoApi.aprobado:
        return const PagoChip(
          texto: 'Aprobado',
          color: Color(0xFF2E7D32),
          fondo: Color(0xFFE6F4EA),
          icono: Icons.check_circle,
        );
      case EstadoPagoApi.pendiente:
        return const PagoChip(
          texto: 'Pendiente',
          color: Color(0xFFB26A00),
          fondo: Color(0xFFFDF3E5),
          icono: Icons.schedule,
        );
      case EstadoPagoApi.rechazado:
        return const PagoChip(
          texto: 'Rechazado',
          color: Color(0xFFD32F2F),
          fondo: Color(0xFFFDECEC),
          icono: Icons.cancel_outlined,
        );
      case EstadoPagoApi.anulado:
        return const PagoChip(
          texto: 'Anulado',
          color: Color(0xFF607D8B),
          fondo: Color(0xFFECEFF1),
          icono: Icons.block,
        );
      case EstadoPagoApi.reembolsado:
        return const PagoChip(
          texto: 'Reembolsado',
          color: Color(0xFF1565C0),
          fondo: Color(0xFFE3F1FC),
          icono: Icons.replay,
        );
      case EstadoPagoApi.desconocido:
        return const PagoChip(
          texto: 'Estado desconocido',
          color: Color(0xFF607D8B),
          fondo: Color(0xFFECEFF1),
          icono: Icons.help_outline,
        );
    }
  }
}
