import 'package:flutter/material.dart';

import '../models/valoracion_models.dart';
import 'estrellas_selector.dart';
import 'valoraciones_vistas.dart';

/// Tarjeta para una valoración ya registrada por el paciente, con acceso
/// directo a actualizarla sin generar duplicados.
class ValoracionRegistradaCard extends StatelessWidget {
  const ValoracionRegistradaCard({
    super.key,
    required this.atencion,
    required this.onActualizar,
  });

  final AtencionValorable atencion;
  final VoidCallback onActualizar;

  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);
  static const Color _grisTexto = Color(0xFF5C6F80);

  @override
  Widget build(BuildContext context) {
    final val = atencion.valoracion!;
    final especialidad = atencion.oftalmologo.especialidad?.trim();
    final comentario = val.comentario?.trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: _azulPrincipal.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera: médico + fecha consulta
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
                  ),
                ),
                child: const Icon(
                  Icons.verified_outlined,
                  size: 21,
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
                        fontSize: 15,
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
              Text(
                formatearFechaCortaValoracion(atencion.fechaConsulta),
                style: const TextStyle(fontSize: 12, color: _grisTexto),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Calificación con estrellas + chip
          Row(
            children: [
              EstrellasResumen(puntuacion: val.puntuacion, tamano: 21),
              const SizedBox(width: 10),
              ValoracionEstadoChip(
                texto: '${val.puntuacion}/5 · ${val.etiquetaPuntuacion}',
                color: const Color(0xFF0D47A1),
                fondo: const Color(0xFFE3F1FC),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Comentario (o etiqueta discreta si es opcional vacío)
          if (comentario.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4EDF4)),
              ),
              child: Text(
                '“$comentario”',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF334155),
                  height: 1.4,
                ),
              ),
            )
          else
            const Text(
              'Sin comentario adicional',
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: Color(0xFF8A9BA9),
              ),
            ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE4EDF4)),
          const SizedBox(height: 10),

          // Pie: fecha de actualización + botón Actualizar
          Row(
            children: [
              Expanded(
                child: Text(
                  'Actualizada el ${formatearFechaCortaValoracion(val.fechaActualizacion)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF8A9BA9),
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: Key('btn_actualizar_valoracion_${val.id}'),
                onPressed: onActualizar,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Actualizar valoración'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _azulPrincipal,
                  side: const BorderSide(color: _azulPrincipal),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
