import 'package:flutter/material.dart';

import '../models/planes_cuotas_models.dart';
import 'estado_pago_chip.dart';

/// Chip del estado de un plan de pago (`ACTIVO`, `COMPLETADO`, `CANCELADO`).
class EstadoPlanChip extends StatelessWidget {
  const EstadoPlanChip({super.key, required this.estado});

  final EstadoPlanPago estado;

  @override
  Widget build(BuildContext context) {
    switch (estado) {
      case EstadoPlanPago.activo:
        return const PagoChip(
          texto: 'Activo',
          color: Color(0xFF2E7D32),
          fondo: Color(0xFFE6F4EA),
          icono: Icons.check_circle,
        );
      case EstadoPlanPago.completado:
        return const PagoChip(
          texto: 'Completado',
          color: Color(0xFF1565C0),
          fondo: Color(0xFFE3F1FC),
          icono: Icons.task_alt,
        );
      case EstadoPlanPago.cancelado:
        return const PagoChip(
          texto: 'Cancelado',
          color: Color(0xFF607D8B),
          fondo: Color(0xFFECEFF1),
          icono: Icons.block,
        );
      case EstadoPlanPago.desconocido:
        return const PagoChip(
          texto: 'Estado desconocido',
          color: Color(0xFF607D8B),
          fondo: Color(0xFFECEFF1),
          icono: Icons.help_outline,
        );
    }
  }
}

/// Chip del estado de una cuota (`PENDIENTE`, `VENCIDA`, `PAGADA`,
/// `CANCELADA`).
class EstadoCuotaChip extends StatelessWidget {
  const EstadoCuotaChip({super.key, required this.estado});

  final EstadoCuotaPlan estado;

  @override
  Widget build(BuildContext context) {
    switch (estado) {
      case EstadoCuotaPlan.pendiente:
        return const PagoChip(
          texto: 'Pendiente',
          color: Color(0xFFB26A00),
          fondo: Color(0xFFFDF3E5),
          icono: Icons.schedule,
        );
      case EstadoCuotaPlan.vencida:
        return const PagoChip(
          texto: 'Vencida',
          color: Color(0xFFD32F2F),
          fondo: Color(0xFFFDECEC),
          icono: Icons.warning_amber_rounded,
        );
      case EstadoCuotaPlan.pagada:
        return const PagoChip(
          texto: 'Pagada',
          color: Color(0xFF2E7D32),
          fondo: Color(0xFFE6F4EA),
          icono: Icons.check_circle,
        );
      case EstadoCuotaPlan.cancelada:
        return const PagoChip(
          texto: 'Cancelada',
          color: Color(0xFF607D8B),
          fondo: Color(0xFFECEFF1),
          icono: Icons.block,
        );
      case EstadoCuotaPlan.desconocida:
        return const PagoChip(
          texto: 'Estado desconocido',
          color: Color(0xFF607D8B),
          fondo: Color(0xFFECEFF1),
          icono: Icons.help_outline,
        );
    }
  }
}
