import 'package:flutter/material.dart';

import '../models/pago_models.dart';
import 'estado_pago_chip.dart';

/// Tarjeta que resume un pago del historial (Pagos > Historial).
///
/// Usa el mismo lenguaje visual que [ConsultaPagoCard].
class PagoHistorialCard extends StatelessWidget {
  const PagoHistorialCard({super.key, required this.pago, required this.onTap});

  /// Pago del historial a mostrar.
  final PagoHistorial pago;

  /// Acción al tocar la tarjeta (abre el detalle del pago).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1976D2).withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 20,
                    color: Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pago #${pago.pagoId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                  EstadoPagoChip(estado: pago.estadoPago),
                ],
              ),
              const SizedBox(height: 10),
              _fila(
                Icons.schedule,
                formatearFechaHoraBolivia(pago.fechaMostrar),
              ),
              if (pago.tieneConsulta) ...[
                const SizedBox(height: 6),
                _fila(
                  Icons.event_note_outlined,
                  'Consulta #${pago.consultaClinicaId}',
                ),
              ],
              const SizedBox(height: 6),
              _fila(Icons.credit_card, pago.metodoPagoEtiqueta),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE4EDF4)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    formatearMontoConMoneda(pago.moneda, pago.monto),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B2B3A),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    pago.aprobado ? 'Ver detalle y comprobante' : 'Ver detalle',
                    style: const TextStyle(
                      color: Color(0xFF1976D2),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF1976D2)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fila(IconData icono, String texto) {
    return Row(
      children: [
        Icon(icono, size: 16, color: const Color(0xFF5C6F80)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(color: Color(0xFF5C6F80), fontSize: 13),
          ),
        ),
      ],
    );
  }
}
