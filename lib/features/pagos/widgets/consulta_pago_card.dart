import 'package:flutter/material.dart';

import '../models/pago_models.dart';
import 'estado_pago_chip.dart';

/// Tarjeta que resume una consulta clínica en la pantalla principal de Pagos.
class ConsultaPagoCard extends StatelessWidget {
  const ConsultaPagoCard({
    super.key,
    required this.consulta,
    required this.onTap,
  });

  final ConsultaPago consulta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final conPendientes = consulta.tienePendientes;

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
                    Icons.event_note_outlined,
                    size: 20,
                    color: Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Consulta del ${formatearFecha(consulta.fechaConsulta)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                  PagoChip(
                    texto: conPendientes ? 'Pago pendiente' : 'Al día',
                    color: conPendientes
                        ? const Color(0xFFB26A00)
                        : const Color(0xFF2E7D32),
                    fondo: conPendientes
                        ? const Color(0xFFFDF3E5)
                        : const Color(0xFFE6F4EA),
                    icono: conPendientes ? Icons.schedule : Icons.verified,
                  ),
                ],
              ),
              if (consulta.oftalmologo != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.medical_services_outlined,
                      size: 16,
                      color: Color(0xFF5C6F80),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        consulta.oftalmologo!,
                        style: const TextStyle(
                          color: Color(0xFF5C6F80),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _metrica('Servicios', '${consulta.cantidadServicios}'),
                  _metrica('Pendientes', '${consulta.cantidadPendientes}'),
                  _metrica(
                    'Total pendiente',
                    'Bs ${formatearMonto(consulta.totalPendiente)}',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE4EDF4)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    conPendientes
                        ? 'Ver servicios para pagar'
                        : 'Ver servicios',
                    style: const TextStyle(
                      color: Color(0xFF1976D2),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: Color(0xFF1976D2)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metrica(String etiqueta, String valor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A9BA9)),
          ),
          const SizedBox(height: 3),
          Text(
            valor,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B2B3A),
            ),
          ),
        ],
      ),
    );
  }
}
