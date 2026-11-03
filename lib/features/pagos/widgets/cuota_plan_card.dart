import 'package:flutter/material.dart';

import '../models/pago_models.dart';
import '../models/planes_cuotas_models.dart';
import 'estado_pago_chip.dart';
import 'estado_plan_chip.dart';

/// Tarjeta de una cuota dentro del detalle del plan (CU33).
///
/// Muestra número de cuota, vencimiento, importe programado, estado real del
/// backend y los intentos anteriores. El botón "Pagar esta cuota" solo se
/// habilita cuando el backend permite el cobro: plan ACTIVO y cuota PENDIENTE
/// o VENCIDA (nunca PAGADA ni CANCELADA).
class CuotaPlanCard extends StatelessWidget {
  const CuotaPlanCard({
    super.key,
    required this.cuota,
    required this.totalCuotas,
    required this.pagable,
    required this.onPagar,
    this.onVerIntentos,
    this.moneda = 'BOB',
  });

  /// Cuota a mostrar.
  final CuotaPlan cuota;

  /// Total de cuotas del plan (para mostrar "N de M").
  final int totalCuotas;

  /// Indica si la cuota puede pagarse ahora.
  final bool pagable;

  /// Inicia el flujo de pago de esta cuota.
  final VoidCallback onPagar;

  /// Consulta los intentos registrados en el backend; `null` para ocultarlo.
  final VoidCallback? onVerIntentos;

  /// Moneda del plan (`BOB`, `USD`, ...).
  final String moneda;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cuota ${cuota.numeroCuota}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                    color: Color(0xFF0D47A1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              EstadoCuotaChip(estado: cuota.estado),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Vencimiento: ${formatearFecha(cuota.fechaVencimiento)}',
                  style: const TextStyle(
                    color: Color(0xFF5C6F80),
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                formatearMontoConMoneda(moneda, cuota.montoProgramado),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ],
          ),
          if (cuota.tieneIntentos) ...[
            const SizedBox(height: 10),
            _IntentosCuota(cuota: cuota, moneda: moneda),
          ],
          if (cuota.estaPagada) ...[
            const SizedBox(height: 8),
            const Text(
              'Pago confirmado. El comprobante está disponible en Historial.',
              style: TextStyle(
                color: Color(0xFF2E7D32),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (pagable) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('pagar-cuota-${cuota.id}'),
                onPressed: onPagar,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Pagar esta cuota'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
          if (onVerIntentos != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('ver-intentos-${cuota.id}'),
                onPressed: onVerIntentos,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Ver intentos de pago'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],

        ],
      ),
    );
  }
}

/// Resumen de los intentos de pago registrados para la cuota.
///
/// Se muestran el estado real de cada pago (`estado_pago`), su importe y su
/// fecha. La app no interpreta ni recalcula ningún cobro.
class _IntentosCuota extends StatelessWidget {
  const _IntentosCuota({required this.cuota, required this.moneda});

  final CuotaPlan cuota;
  final String moneda;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Intentos registrados',
          style: TextStyle(
            color: Color(0xFF5C6F80),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (final intento in cuota.pagos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                EstadoPagoChip(estado: intento.estado),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${formatearMontoConMoneda(moneda, intento.monto)} · '
                    '${formatearFecha(intento.fechaCreacion)}',
                    style: const TextStyle(
                      color: Color(0xFF5C6F80),
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

