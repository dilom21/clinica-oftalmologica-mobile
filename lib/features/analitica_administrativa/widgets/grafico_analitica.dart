import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/analitica_models.dart';

class GraficoSerie extends StatelessWidget {
  const GraficoSerie({super.key, required this.puntos});
  final List<PuntoSerie> puntos;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Gráfico de serie con ${puntos.length} períodos. Los puntos sin cobertura no se dibujan como cero.',
    child: SizedBox(
      height: 190,
      width: double.infinity,
      child: CustomPaint(painter: _SeriePainter(puntos)),
    ),
  );
}

class GraficoPronostico extends StatelessWidget {
  const GraficoPronostico({super.key, required this.puntos});
  final List<PronosticoSemana> puntos;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Gráfico de ${puntos.length} puntos proyectados con intervalos empíricos. No contiene una curva histórica.',
    child: SizedBox(
      height: 190,
      width: double.infinity,
      child: CustomPaint(painter: _PronosticoPainter(puntos)),
    ),
  );
}

class _SeriePainter extends CustomPainter {
  _SeriePainter(this.puntos);
  final List<PuntoSerie> puntos;
  @override
  void paint(Canvas canvas, Size size) {
    _ejes(canvas, size);
    final valores = puntos.where((p) => p.valor != null).toList();
    if (valores.isEmpty) return;
    final maximo = valores.map((p) => p.valor!.toDouble()).reduce(math.max);
    final path = Path();
    var iniciado = false;
    for (var i = 0; i < puntos.length; i++) {
      final valor = puntos[i].valor;
      if (valor == null) {
        iniciado = false;
        continue;
      }
      final point = Offset(
        _x(i, puntos.length, size),
        _y(valor.toDouble(), maximo, size),
      );
      if (!iniciado) {
        path.moveTo(point.dx, point.dy);
        iniciado = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3.5, Paint()..color = _color(puntos[i].estado));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1976D2)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  Color _color(EstadoDato estado) => switch (estado) {
    EstadoDato.ok => const Color(0xFF1976D2),
    EstadoDato.zero => const Color(0xFF2E7D32),
    EstadoDato.suppressed => const Color(0xFF8E24AA),
    EstadoDato.partial => const Color(0xFFF57C00),
    EstadoDato.notCovered => const Color(0xFF78909C),
  };
  @override
  bool shouldRepaint(_SeriePainter old) => old.puntos != puntos;
}

class _PronosticoPainter extends CustomPainter {
  _PronosticoPainter(this.puntos);
  final List<PronosticoSemana> puntos;
  @override
  void paint(Canvas canvas, Size size) {
    _ejes(canvas, size);
    if (puntos.isEmpty) return;
    final maximo = puntos.map((p) => p.limiteSuperior).reduce(math.max);
    final intervalo = Path();
    for (var i = 0; i < puntos.length; i++) {
      final p = Offset(
        _x(i, puntos.length, size),
        _y(puntos[i].limiteSuperior, maximo, size),
      );
      i == 0 ? intervalo.moveTo(p.dx, p.dy) : intervalo.lineTo(p.dx, p.dy);
    }
    for (var i = puntos.length - 1; i >= 0; i--) {
      intervalo.lineTo(
        _x(i, puntos.length, size),
        _y(puntos[i].limiteInferior, maximo, size),
      );
    }
    intervalo.close();
    canvas.drawPath(
      intervalo,
      Paint()..color = const Color(0xFF90CAF9).withValues(alpha: .35),
    );
    final linea = Path();
    for (var i = 0; i < puntos.length; i++) {
      final p = Offset(
        _x(i, puntos.length, size),
        _y(puntos[i].valor, maximo, size),
      );
      i == 0 ? linea.moveTo(p.dx, p.dy) : linea.lineTo(p.dx, p.dy);
      canvas.drawCircle(p, 4, Paint()..color = const Color(0xFF0D47A1));
    }
    canvas.drawPath(
      linea,
      Paint()
        ..color = const Color(0xFF0D47A1)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_PronosticoPainter old) => old.puntos != puntos;
}

void _ejes(Canvas canvas, Size size) {
  canvas.drawLine(
    Offset(28, 8),
    Offset(28, size.height - 24),
    Paint()..color = const Color(0xFFCFD8DC),
  );
  canvas.drawLine(
    Offset(28, size.height - 24),
    Offset(size.width - 8, size.height - 24),
    Paint()..color = const Color(0xFFCFD8DC),
  );
}

double _x(int index, int total, Size size) =>
    32 + index * (size.width - 44) / math.max(1, total - 1);
double _y(double value, double maximo, Size size) =>
    size.height - 28 - (value / math.max(1, maximo)) * (size.height - 42);
