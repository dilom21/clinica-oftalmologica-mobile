import 'package:flutter/material.dart';

import '../models/pago_models.dart';

/// Barra inferior con el total seleccionado y el botón de pago.
///
/// El botón se deshabilita cuando no hay servicios seleccionados o cuando hay
/// una operación de pago en curso.
class PagoResumenBar extends StatelessWidget {
  const PagoResumenBar({
    super.key,
    required this.total,
    required this.habilitado,
    required this.procesando,
    required this.onPagar,
  });

  final double total;
  final bool habilitado;
  final bool procesando;
  final VoidCallback onPagar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Total seleccionado',
                  style: TextStyle(color: Color(0xFF5C6F80)),
                ),
                const Spacer(),
                Text(
                  'Bs ${formatearMonto(total)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: habilitado && !procesando ? onPagar : null,
                icon: procesando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.credit_card),
                label: Text(procesando ? 'Procesando...' : 'Pagar con tarjeta'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB0C4D4),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
