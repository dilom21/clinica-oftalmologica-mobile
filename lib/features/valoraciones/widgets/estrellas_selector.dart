import 'package:flutter/material.dart';

import '../models/valoracion_models.dart';

/// Selector interactivo de puntuación de 1 a 5 estrellas para CU40.
class EstrellasSelector extends StatelessWidget {
  const EstrellasSelector({
    super.key,
    required this.puntuacion,
    required this.onChanged,
    this.habilitado = true,
  });

  final int puntuacion;
  final ValueChanged<int> onChanged;
  final bool habilitado;

  static const Color _dorado = Color(0xFFF59E0B);
  static const Color _inactivo = Color(0xFFCBD5E1);

  Color _colorFondoEtiqueta() {
    if (puntuacion <= 0) return const Color(0xFFF1F5F9);
    if (puntuacion <= 2) return const Color(0xFFFFF3E0);
    if (puntuacion == 3) return const Color(0xFFFFF8E1);
    return const Color(0xFFE8F5E9);
  }

  Color _colorBordeEtiqueta() {
    if (puntuacion <= 0) return const Color(0xFFE2E8F0);
    if (puntuacion <= 2) return const Color(0xFFFFCC80);
    if (puntuacion == 3) return const Color(0xFFFDE68A);
    return const Color(0xFFA5D6A7);
  }

  Color _colorTextoEtiqueta() {
    if (puntuacion <= 0) return const Color(0xFF64748B);
    if (puntuacion <= 2) return const Color(0xFFC2410C);
    if (puntuacion == 3) return const Color(0xFFB45309);
    return const Color(0xFF1B5E20);
  }

  @override
  Widget build(BuildContext context) {
    final valida =
        puntuacion >= puntuacionMinimaValoracion &&
        puntuacion <= puntuacionMaximaValoracion;
    final etiqueta = valida
        ? '$puntuacion / $puntuacionMaximaValoracion · ${etiquetaParaPuntuacion(puntuacion)}'
        : 'Toca las estrellas para calificar (1 a 5)';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (
              int i = puntuacionMinimaValoracion;
              i <= puntuacionMaximaValoracion;
              i++
            )
              IconButton(
                key: Key('estrella_$i'),
                tooltip: '$i estrellas (${etiquetaParaPuntuacion(i)})',
                onPressed: habilitado ? () => onChanged(i) : null,
                iconSize: 42,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                icon: AnimatedScale(
                  scale: i <= puntuacion ? 1.14 : 1.0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    i <= puntuacion
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: i <= puntuacion ? _dorado : _inactivo,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: _colorFondoEtiqueta(),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _colorBordeEtiqueta()),
          ),
          child: Text(
            etiqueta,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _colorTextoEtiqueta(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Visualización compacta de estrellas de solo lectura.
class EstrellasResumen extends StatelessWidget {
  const EstrellasResumen({
    super.key,
    required this.puntuacion,
    this.tamano = 18,
  });

  final int puntuacion;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (
          int i = puntuacionMinimaValoracion;
          i <= puntuacionMaximaValoracion;
          i++
        )
          Icon(
            i <= puntuacion ? Icons.star_rounded : Icons.star_outline_rounded,
            size: tamano,
            color: i <= puntuacion
                ? const Color(0xFFF59E0B)
                : const Color(0xFFCBD5E1),
          ),
      ],
    );
  }
}
