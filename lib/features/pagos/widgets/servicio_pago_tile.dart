import 'package:flutter/material.dart';

import '../models/pago_models.dart';
import 'estado_pago_chip.dart';

/// Fila de un servicio realizado dentro de la pantalla de servicios.
///
/// Los servicios PAGADOS (o no cobrables) muestran su `Checkbox` deshabilitado
/// para que nunca puedan volver a seleccionarse.
class ServicioPagoTile extends StatelessWidget {
  const ServicioPagoTile({
    super.key,
    required this.servicio,
    required this.seleccionado,
    this.onChanged,
  });

  final ServicioRealizadoPago servicio;
  final bool seleccionado;

  /// Callback de selección. `null` cuando la fila no es interactiva.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final seleccionable = esServicioSeleccionable(servicio);
    final activo = seleccionable && seleccionado;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activo ? const Color(0xFF1976D2) : Colors.grey.shade200,
          width: activo ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
        child: Row(
          children: [
            Checkbox(
              value: activo,
              onChanged: seleccionable && onChanged != null
                  ? (valor) => onChanged!(valor ?? false)
                  : null,
              activeColor: const Color(0xFF1976D2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    servicio.nombreServicio,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B2B3A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bs ${formatearMonto(servicio.precio)}',
                    style: const TextStyle(color: Color(0xFF5C6F80)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            EstadoServicioChip(estado: servicio.estadoPago),
          ],
        ),
      ),
    );
  }
}
