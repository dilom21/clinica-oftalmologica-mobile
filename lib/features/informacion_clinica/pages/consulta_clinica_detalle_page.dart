import 'package:flutter/material.dart';

import '../models/informacion_clinica_models.dart';

/// Detalle de una consulta clínica ya autorizada para el paciente.
///
/// Recibe el objeto cargado en el listado. No vuelve a pedir datos ni
/// acepta un identificador que pudiera apuntar a otra consulta.
class ConsultaClinicaDetallePage extends StatelessWidget {
  const ConsultaClinicaDetallePage({super.key, required this.consulta});

  final ConsultaClinicaAutorizada consulta;

  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _grisTexto = Color(0xFF5C6F80);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _azulProfundo,
        elevation: 0,
        title: const Text(
          'Consulta',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        key: const Key('consulta-clinica-detalle'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _Bloque(
            titulo: consulta.titulo,
            children: [
              Text(
                fechaHoraClinica(consulta.fechaConsulta),
                style: const TextStyle(color: _grisTexto),
              ),
              Text(
                consulta.oftalmologo.nombreCompleto,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (consulta.oftalmologo.especialidad != null)
                Text(
                  consulta.oftalmologo.especialidad!,
                  style: const TextStyle(color: _grisTexto),
                ),
              if (consulta.anamnesis != null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Anamnesis',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(consulta.anamnesis!),
              ],
              if (consulta.observaciones != null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Observaciones',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(consulta.observaciones!),
              ],
            ],
          ),
          if (consulta.diagnosticos.isNotEmpty)
            _Bloque(
              titulo: 'Diagnósticos',
              children: [
                for (final diagnostico in consulta.diagnosticos)
                  _Item(
                    titulo: diagnostico.nombre,
                    detalle: diagnostico.descripcion,
                  ),
              ],
            ),
          if (consulta.tratamientos.isNotEmpty)
            _Bloque(
              titulo: 'Tratamientos',
              children: [
                for (final tratamiento in consulta.tratamientos)
                  _Item(
                    titulo: tratamiento.descripcion,
                    detalle: _rangoTratamiento(tratamiento),
                  ),
              ],
            ),
          if (consulta.indicaciones.isNotEmpty)
            _Bloque(
              titulo: 'Indicaciones',
              children: [
                for (final indicacion in consulta.indicaciones)
                  _Item(titulo: indicacion.descripcion),
              ],
            ),
          if (consulta.recetas.isNotEmpty)
            _Bloque(
              titulo: 'Recetas',
              children: [
                for (final receta in consulta.recetas) ...[
                  Text(
                    'Emitida el ${fechaHoraClinica(receta.fechaEmision)}',
                    style: const TextStyle(color: _grisTexto),
                  ),
                  if (receta.observaciones != null) Text(receta.observaciones!),
                  for (final detalle in receta.detalles)
                    _Item(
                      titulo: detalle.medicamento,
                      detalle: _posologia(detalle),
                    ),
                ],
              ],
            ),
          if (consulta.examenes.isNotEmpty)
            _Bloque(
              titulo: 'Exámenes',
              children: [
                for (final examen in consulta.examenes) ...[
                  Text(
                    examen.nombreExamen,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final resultado in examen.resultados)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(resultado.resultado),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  String? _rangoTratamiento(TratamientoAutorizado tratamiento) {
    final partes = <String>[
      if (tratamiento.observaciones != null) tratamiento.observaciones!,
      if (tratamiento.fechaInicio != null || tratamiento.fechaFin != null)
        'Del ${fechaClinica(tratamiento.fechaInicio)} al ${fechaClinica(tratamiento.fechaFin)}',
    ];
    if (partes.isEmpty) return null;
    return partes.join('\n');
  }

  String? _posologia(DetalleRecetaAutorizado detalle) {
    final partes = <String?>[
      detalle.presentacion,
      detalle.dosis,
      detalle.frecuencia,
      detalle.duracion,
      detalle.indicaciones,
    ].whereType<String>().toList();
    if (partes.isEmpty) return null;
    return partes.join(' · ');
  }
}

class _Bloque extends StatelessWidget {
  const _Bloque({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.titulo, this.detalle});

  final String titulo;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (detalle != null)
            Text(detalle!, style: const TextStyle(color: Color(0xFF5C6F80))),
        ],
      ),
    );
  }
}
