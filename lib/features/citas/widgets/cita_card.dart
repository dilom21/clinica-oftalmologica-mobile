import 'package:flutter/material.dart';

import '../models/agenda_models.dart';
import '../models/cita_models.dart';
import 'citas_ui.dart';

/// Tarjeta de una cita real del paciente.
///
/// El nombre del oftalmólogo solo se muestra cuando la app lo obtuvo de
/// `GET /agenda-citas/oftalmologos` ([oftalmologo] != null). Nunca se inventa
/// un médico ni una especialidad.
class CitaCard extends StatelessWidget {
  const CitaCard({
    super.key,
    required this.cita,
    this.oftalmologo,
    this.onTap,
  });

  final Cita cita;
  final OftalmologoAgenda? oftalmologo;
  final VoidCallback? onTap;

  static const List<String> _mesesCortos = <String>[
    'ENE',
    'FEB',
    'MAR',
    'ABR',
    'MAY',
    'JUN',
    'JUL',
    'AGO',
    'SEP',
    'OCT',
    'NOV',
    'DIC',
  ];

  @override
  Widget build(BuildContext context) {
    final String mes = _mesesCortos[(cita.fecha.month - 1).clamp(0, 11)];
    final String? nombreMedico = oftalmologo?.nombreCompleto;

    return TarjetaCitas(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  CitasColores.azulProfundo,
                  CitasColores.azulPrincipal,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  mes,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${cita.fecha.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.schedule,
                      size: 15,
                      color: CitasColores.azulPrincipal,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        cita.franja,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: CitasColores.azulProfundo,
                        ),
                      ),
                    ),
                    ChipEstadoCita(estado: cita.estado, compacto: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  nombreMedico ?? 'Oftalmólogo asignado',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: nombreMedico == null
                        ? CitasColores.grisSuave
                        : CitasColores.grisTexto,
                  ),
                ),
                if (cita.motivo != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    cita.motivo!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: CitasColores.grisTexto,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text(
                      fechaCorta(cita.fecha),
                      style: const TextStyle(
                        fontSize: 12,
                        color: CitasColores.grisSuave,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Ver detalle',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: CitasColores.azulPrincipal,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: CitasColores.azulPrincipal,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
