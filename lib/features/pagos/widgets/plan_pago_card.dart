import 'package:flutter/material.dart';

import '../models/pago_models.dart';
import '../models/planes_cuotas_models.dart';
import 'estado_plan_chip.dart';

/// Tarjeta de un plan de pago dentro de la lista "Mis planes de pago" (CU32).
///
/// Muestra EXCLUSIVAMENTE datos devueltos por el backend: identificador,
/// estado, monto total financiado, monto pagado, saldo pendiente, cuotas
/// pagadas / totales y el aviso de cuotas vencidas.
class PlanPagoCard extends StatelessWidget {
  const PlanPagoCard({super.key, required this.plan, required this.onTap});

  /// Plan a mostrar.
  final PlanPagoResumen plan;

  /// Abre el detalle del plan y sus cuotas.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: Key('plan-card-${plan.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Plan de pago #${plan.id}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    EstadoPlanChip(estado: plan.estado),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Saldo pendiente',
                  style: TextStyle(color: Color(0xFF5C6F80), fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  formatearMontoConMoneda(plan.moneda, plan.saldoPendiente),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _DatoPlan(
                        titulo: 'Total financiado',
                        valor: formatearMontoConMoneda(
                          plan.moneda,
                          plan.montoTotal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DatoPlan(
                        titulo: 'Total pagado',
                        valor: formatearMontoConMoneda(
                          plan.moneda,
                          plan.montoPagado,
                        ),
                        colorValor: const Color(0xFF2E7D32),
                        fondo: const Color(0xFFE9F7EF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${plan.cuotasPagadas} de ${plan.cantidadCuotas} '
                        'cuotas pagadas',
                        style: const TextStyle(
                          color: Color(0xFF5C6F80),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Text(
                      '${plan.porcentaje} %',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    key: Key('plan-progreso-${plan.id}'),
                    value: plan.progreso,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE3EDF7),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF1976D2),
                    ),
                  ),
                ),
                if (plan.tieneCuotasVencidas) ...[
                  const SizedBox(height: 12),
                  const _AvisoVencidas(),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Ver plan y cuotas'),
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
          ),
        ),
      ),
    );
  }
}

/// Recuadro con un importe resumido del plan.
class _DatoPlan extends StatelessWidget {
  const _DatoPlan({
    required this.titulo,
    required this.valor,
    this.colorValor = const Color(0xFF0D47A1),
    this.fondo = const Color(0xFFF4F9FF),
  });

  final String titulo;
  final String valor;
  final Color colorValor;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: Color(0xFF5C6F80), fontSize: 11.5),
          ),
          const SizedBox(height: 3),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: colorValor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de cuotas vencidas informado por el backend.
class _AvisoVencidas extends StatelessWidget {
  const _AvisoVencidas();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD32F2F)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tienes cuotas vencidas en este plan.',
              style: TextStyle(
                color: Color(0xFFB3261E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
