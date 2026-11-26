import 'package:flutter/material.dart';

import '../models/valoracion_models.dart';
import 'valoraciones_vistas.dart';

/// Tarjeta para una atención médica finalizada o con receta pendiente de valorar.
class AtencionPendienteCard extends StatelessWidget {
  const AtencionPendienteCard({
    super.key,
    required this.atencion,
    required this.onValorar,
  });

  final AtencionValorable atencion;
  final VoidCallback onValorar;

  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _grisTexto = Color(0xFF5C6F80);

  @override
  Widget build(BuildContext context) {
    final mensajeAviso =
        atencion.notificacion?.mensaje ??
        'Finalizó tu atención con Dr(a). ${atencion.oftalmologo.nombreCompleto}. Cuéntanos cómo fue tu experiencia.';
    final especialidad = atencion.oftalmologo.especialidad?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera: estado y fecha
          Row(
            children: [
              ValoracionEstadoChip(
                texto: atencion.tieneReceta
                    ? 'Receta emitida'
                    : 'Atención finalizada',
                color: const Color(0xFFB45309),
                fondo: const Color(0xFFFFF8E1),
                icono: atencion.tieneReceta
                    ? Icons.medication_outlined
                    : Icons.notifications_active_outlined,
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: _grisTexto,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatearFechaCortaValoracion(atencion.fechaConsulta),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _grisTexto,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Identidad del médico
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
                  ),
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  size: 22,
                  color: _azulProfundo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dr(a). ${atencion.oftalmologo.nombreCompleto}',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B2B3A),
                      ),
                    ),
                    if (especialidad != null && especialidad.isNotEmpty)
                      Text(
                        especialidad,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _grisTexto,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Mensaje in-app recibido
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3F1FC)),
            ),
            child: Text(
              mensajeAviso,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF334155),
                height: 1.4,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Botón CTA con degradado Visión Clara
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: Key('btn_valorar_consulta_${atencion.consultaClinicaId}'),
                onTap: onValorar,
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Valorar atención',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
