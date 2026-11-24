import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/chat_voz_controller.dart';
import 'chatbot_ui.dart';

/// Esfera luminosa de la experiencia de voz.
///
/// - Animación original con [CustomPainter] y [AnimationController].
/// - Refleja el estado real: inactivo, escuchando, procesando, respondiendo,
///   pausado, error o no disponible.
/// - Respeta la preferencia del sistema de reducir movimiento.
/// - El `AnimatedBuilder` está acotado a la esfera: no reconstruye la pantalla
///   completa en cada fotograma.
class EsferaVoz extends StatefulWidget {
  const EsferaVoz({
    super.key,
    required this.estado,
    this.nivelAudio = 0,
    this.size = 250,
  });

  final EstadoVoz estado;
  final double nivelAudio;
  final double size;

  @override
  State<EsferaVoz> createState() => _EsferaVozState();
}

class _EsferaVozState extends State<EsferaVoz>
    with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool _reducirMovimiento = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reducir = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reducir == _reducirMovimiento && _control.isAnimating) return;

    _reducirMovimiento = reducir;
    if (_reducirMovimiento) {
      _control.stop();
      _control.value = 0.35;
      return;
    }

    if (!_control.isAnimating) _control.repeat();
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _control,
            builder: (BuildContext context, Widget? child) {
              return CustomPaint(
                painter: _EsferaPainter(
                  estado: widget.estado,
                  progreso: _control.value,
                  nivel: widget.nivelAudio.clamp(0.0, 1.0),
                  animado: !_reducirMovimiento,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EsferaPainter extends CustomPainter {
  _EsferaPainter({
    required this.estado,
    required this.progreso,
    required this.nivel,
    required this.animado,
  });

  final EstadoVoz estado;
  final double progreso;
  final double nivel;
  final bool animado;

  static const Color _electrico = ChatbotColores.electrico;
  static const Color _celeste = ChatbotColores.celeste;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centro = Offset(size.width / 2, size.height / 2);
    final double radioBase = size.width * 0.29;
    final double t = progreso * math.pi * 2;
    final double pulso = animado ? (math.sin(t) + 1) / 2 : 0.5;

    // Halo exterior.
    final Color colorHalo = switch (estado) {
      EstadoVoz.respondiendo => _electrico,
      EstadoVoz.escuchando => _celeste,
      EstadoVoz.procesando => _electrico,
      EstadoVoz.pausado => ChatbotColores.vozTextoSuave,
      EstadoVoz.error => ChatbotColores.rojo,
      EstadoVoz.noDisponible => ChatbotColores.grisSuave,
      _ => _electrico,
    };

    final double intensidad = switch (estado) {
      EstadoVoz.escuchando => 0.30 + nivel * 0.35,
      EstadoVoz.respondiendo => 0.34 + pulso * 0.18,
      EstadoVoz.procesando => 0.24 + pulso * 0.10,
      EstadoVoz.inactivo => 0.12 + pulso * 0.06,
      EstadoVoz.pausado => 0.10,
      EstadoVoz.error => 0.16,
      EstadoVoz.noDisponible => 0.08,
      _ => 0.16,
    };

    canvas.drawCircle(
      centro,
      size.width * 0.50,
      Paint()
        ..shader =
            RadialGradient(
              colors: <Color>[
                colorHalo.withValues(alpha: intensidad),
                colorHalo.withValues(alpha: intensidad * 0.35),
                colorHalo.withValues(alpha: 0),
              ],
              stops: const <double>[0, 0.55, 1],
            ).createShader(
              Rect.fromCircle(center: centro, radius: size.width * 0.5),
            ),
    );

    // Anillos concéntricos suaves. En "procesando" giran; en "escuchando"
    // laten con el nivel de sonido real que entrega STT.
    for (int i = 0; i < 3; i++) {
      final double fase = i * math.pi / 3;
      final double amplitud = estado == EstadoVoz.procesando
          ? size.width * 0.018
          : size.width * 0.012;
      final double radio =
          radioBase +
          size.width * (0.075 + i * 0.052) +
          (animado ? math.sin(t + fase) * amplitud : 0) +
          (estado == EstadoVoz.escuchando ? nivel * size.width * 0.02 : 0);

      final double opacidad = switch (estado) {
        EstadoVoz.procesando => 0.34 - i * 0.07,
        EstadoVoz.escuchando => 0.30 - i * 0.06,
        EstadoVoz.respondiendo => 0.30 - i * 0.06,
        EstadoVoz.inactivo => 0.16 - i * 0.03,
        EstadoVoz.pausado => 0.10 - i * 0.02,
        _ => 0.14 - i * 0.03,
      };

      canvas.drawCircle(
        centro,
        radio,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 1.8 : 1.0
          ..color = colorHalo.withValues(alpha: opacidad.clamp(0.0, 1.0)),
      );
    }

    // Arcos en movimiento durante "procesando" y "respondiendo".
    if (animado &&
        (estado == EstadoVoz.procesando || estado == EstadoVoz.respondiendo)) {
      final double rotacion = t;
      for (int i = 0; i < 2; i++) {
        final double radio = radioBase + size.width * (0.14 + i * 0.055);
        canvas.drawArc(
          Rect.fromCircle(center: centro, radius: radio),
          rotacion + i * math.pi,
          math.pi * 0.55,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.2
            ..shader = SweepGradient(
              colors: <Color>[
                colorHalo.withValues(alpha: 0),
                colorHalo.withValues(alpha: 0.75),
                colorHalo.withValues(alpha: 0),
              ],
              stops: const <double>[0, 0.5, 1],
            ).createShader(Rect.fromCircle(center: centro, radius: radio)),
        );
      }
    }

    // Cuerpo de la esfera.
    final double atenuacion = estado == EstadoVoz.pausado
        ? 0.55
        : estado == EstadoVoz.noDisponible
        ? 0.4
        : 1.0;

    final Rect esfera = Rect.fromCircle(center: centro, radius: radioBase);
    canvas.drawCircle(
      centro,
      radioBase,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.35),
          colors: <Color>[
            Color(0xFF7CC7F7),
            Color(0xFF2F80ED),
            Color(0xFF0F3D78),
            Color(0xFF082645),
          ],
          stops: <double>[0, 0.35, 0.78, 1],
        ).createShader(esfera),
    );

    // Brillo interior.
    canvas.drawCircle(
      Offset(centro.dx - radioBase * 0.28, centro.dy - radioBase * 0.34),
      radioBase * 0.32,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.35 * atenuacion),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(esfera),
    );

    // Borde luminoso.
    canvas.drawCircle(
      centro,
      radioBase,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _celeste.withValues(alpha: 0.55 * atenuacion),
    );

    // Ondas de voz o marca central según el estado.
    if (estado == EstadoVoz.escuchando ||
        estado == EstadoVoz.respondiendo ||
        estado == EstadoVoz.procesando) {
      _ondas(canvas, centro, radioBase, t, atenuacion);
    } else {
      _marcaCentral(canvas, centro, radioBase, atenuacion);
    }
  }

  void _ondas(
    Canvas canvas,
    Offset centro,
    double radioBase,
    double t,
    double atenuacion,
  ) {
    const int barras = 7;
    final double ancho = math.max(3.0, radioBase * 0.075);
    final double separacion = ancho * 1.75;
    final double total = (barras - 1) * separacion;

    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92 * atenuacion)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = ancho;

    for (int i = 0; i < barras; i++) {
      final double distancia = (i - (barras - 1) / 2).abs();
      final double base = 1 - distancia / barras;
      final double oscilacion = estado == EstadoVoz.escuchando
          ? (math.sin(t * 2 + i * 0.9) + 1) / 2
          : (math.sin(t * 1.6 + i * 0.7) + 1) / 2;
      final double entrada = estado == EstadoVoz.escuchando
          ? nivel * 0.85
          : estado == EstadoVoz.procesando
          ? 0.25
          : 0.55;
      final double alto =
          radioBase * (0.14 + base * 0.30 * (0.35 + oscilacion * entrada));

      final double x = centro.dx - total / 2 + i * separacion;
      canvas.drawLine(
        Offset(x, centro.dy - alto / 2),
        Offset(x, centro.dy + alto / 2),
        paint,
      );
    }
  }

  void _marcaCentral(
    Canvas canvas,
    Offset centro,
    double radioBase,
    double atenuacion,
  ) {
    final Color color = estado == EstadoVoz.error
        ? ChatbotColores.rojo
        : Colors.white.withValues(alpha: 0.86 * atenuacion);

    if (estado == EstadoVoz.inactivo) {
      // Micrófono estilizado: no representa captura de audio.
      final Paint paint = Paint()
        ..color = color
        ..strokeWidth = radioBase * 0.055
        ..strokeCap = StrokeCap.round;
      final RRect cuerpo = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centro.dx, centro.dy - radioBase * 0.05),
          width: radioBase * 0.20,
          height: radioBase * 0.40,
        ),
        Radius.circular(radioBase * 0.12),
      );
      canvas.drawRRect(cuerpo, paint..style = PaintingStyle.stroke);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(centro.dx, centro.dy + radioBase * 0.02),
          width: radioBase * 0.44,
          height: radioBase * 0.34,
        ),
        0,
        math.pi,
        false,
        paint,
      );
      canvas.drawLine(
        Offset(centro.dx, centro.dy + radioBase * 0.19),
        Offset(centro.dx, centro.dy + radioBase * 0.30),
        paint,
      );
      return;
    }

    if (estado == EstadoVoz.error) {
      final Paint paint = Paint()
        ..color = color
        ..strokeWidth = radioBase * 0.06
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(centro.dx, centro.dy - radioBase * 0.15),
        Offset(centro.dx, centro.dy + radioBase * 0.08),
        paint,
      );
      canvas.drawCircle(
        Offset(centro.dx, centro.dy + radioBase * 0.22),
        radioBase * 0.035,
        paint,
      );
      return;
    }

    canvas.drawCircle(centro, radioBase * 0.06, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _EsferaPainter oldDelegate) {
    return oldDelegate.estado != estado ||
        oldDelegate.progreso != progreso ||
        oldDelegate.nivel != nivel ||
        oldDelegate.animado != animado;
  }
}
