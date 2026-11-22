import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chatbot_models.dart';

/// Identidad visual del módulo CU41.
///
/// Respeta la paleta de CitasColores y añade variantes tonales exclusivas del
/// asistente (degradados celestes y fondo nocturno de la experiencia de voz).
class ChatbotColores {
  const ChatbotColores._();

  static const Color azulProfundo = Color(0xFF0D47A1);
  static const Color azulPrincipal = Color(0xFF1976D2);
  static const Color celeste = Color(0xFF4FC3F7);
  static const Color celesteSuave = Color(0xFFBFE7FB);
  static const Color celesteMuySuave = Color(0xFFE3F4FD);
  static const Color fondo = Color(0xFFF4F9FF);
  static const Color fondoSuave = Color(0xFFF2F8FE);
  static const Color borde = Color(0xFFE1ECF5);
  static const Color texto = Color(0xFF12395E);
  static const Color grisTexto = Color(0xFF5C6F80);
  static const Color grisSuave = Color(0xFF8A9BA9);
  static const Color verde = Color(0xFF2E7D32);
  static const Color verdeSuave = Color(0xFFE8F6EC);
  static const Color ambar = Color(0xFFB26A00);
  static const Color ambarSuave = Color(0xFFFFF4E0);
  static const Color rojo = Color(0xFFC62828);
  static const Color rojoSuave = Color(0xFFFDECEC);

  // Experiencia de voz.
  static const Color nocturno = Color(0xFF071C38);
  static const Color nocturnoMedio = Color(0xFF0A2A50);
  static const Color nocturnoSuave = Color(0xFF123B66);
  static const Color electrico = Color(0xFF2F80ED);
  static const Color vozTexto = Color(0xFFF4FAFF);
  static const Color vozTextoSuave = Color(0xFFAFCBE8);
}

/// Fondo claro del chat con formas suaves, sin imágenes externas.
class FondoChatbot extends StatelessWidget {
  const FondoChatbot({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFF7FBFF),
                  Color(0xFFEEF8FF),
                  Color(0xFFE4F3FD),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _Halo(
            size: 260,
            color: ChatbotColores.celeste.withValues(alpha: 0.16),
          ),
        ),
        Positioned(
          top: 210,
          left: -110,
          child: _Halo(
            size: 240,
            color: ChatbotColores.azulPrincipal.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// Avatar original del asistente (robot profesional), dibujado con Flutter.
///
/// No usa fotografías ni recursos externos y mantiene su nitidez a cualquier
/// tamaño.
class AsistenteAvatar extends StatelessWidget {
  const AsistenteAvatar({super.key, this.size = 56, this.conHalo = false});

  final double size;
  final bool conHalo;

  @override
  Widget build(BuildContext context) {
    final Widget avatar = Semantics(
      label: 'Asistente virtual',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFEAF8FF),
              Color(0xFFCDECFB),
              Color(0xFF9AD8F5),
            ],
          ),
          border: Border.all(color: Colors.white, width: size * 0.05),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: ChatbotColores.azulPrincipal.withValues(alpha: 0.22),
              blurRadius: size * 0.34,
              offset: Offset(0, size * 0.12),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: CustomPaint(painter: _RobotPainter()),
        ),
      ),
    );

    if (!conHalo) return avatar;

    return SizedBox(
      width: size * 2.1,
      height: size * 2.1,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: size * 2.1,
            height: size * 2.1,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  ChatbotColores.celeste.withValues(alpha: 0.35),
                  ChatbotColores.celeste.withValues(alpha: 0.08),
                  ChatbotColores.celeste.withValues(alpha: 0),
                ],
                stops: const <double>[0, 0.6, 1],
              ),
            ),
          ),
          avatar,
        ],
      ),
    );
  }
}

class _RobotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint cabeza = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFFFFFFFF), Color(0xFFDDF3FF)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final Paint contorno = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..color = ChatbotColores.azulPrincipal.withValues(alpha: 0.65);

    // Antena
    canvas.drawLine(
      Offset(w * 0.5, h * 0.18),
      Offset(w * 0.5, h * 0.03),
      Paint()
        ..color = ChatbotColores.azulPrincipal
        ..strokeWidth = w * 0.045
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.035),
      w * 0.07,
      Paint()..color = ChatbotColores.celeste,
    );

    // Orejas
    final RRect orejaIzq = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.04, h * 0.36, w * 0.12, h * 0.24),
      Radius.circular(w * 0.06),
    );
    final RRect orejaDer = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.84, h * 0.36, w * 0.12, h * 0.24),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(orejaIzq, Paint()..color = ChatbotColores.celesteSuave);
    canvas.drawRRect(orejaDer, Paint()..color = ChatbotColores.celesteSuave);

    // Cabeza
    final RRect cabezaRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.14, h * 0.2, w * 0.72, h * 0.62),
      Radius.circular(w * 0.20),
    );
    canvas.drawRRect(cabezaRect, cabeza);
    canvas.drawRRect(cabezaRect, contorno);

    // Pantalla/visera
    final RRect visera = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, h * 0.32, w * 0.56, h * 0.34),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(
      visera,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1E5FA8), Color(0xFF0D3D73)],
        ).createShader(visera.outerRect),
    );

    // Ojos luminosos
    final Paint ojos = Paint()..color = const Color(0xFF9BE7FF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.32, h * 0.42, w * 0.11, h * 0.11),
        Radius.circular(w * 0.05),
      ),
      ojos,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.57, h * 0.42, w * 0.11, h * 0.11),
        Radius.circular(w * 0.05),
      ),
      ojos,
    );

    // Sonrisa
    final Path sonrisa = Path()
      ..moveTo(w * 0.4, h * 0.57)
      ..quadraticBezierTo(w * 0.5, h * 0.64, w * 0.6, h * 0.57);
    canvas.drawPath(
      sonrisa,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF9BE7FF),
    );

    // Cuerpo/base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.30, h * 0.80, w * 0.40, h * 0.09),
        Radius.circular(w * 0.05),
      ),
      Paint()..color = ChatbotColores.azulPrincipal.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Botón circular de acción del chat.
class BotonCircularChatbot extends StatelessWidget {
  const BotonCircularChatbot({
    super.key,
    required this.icono,
    required this.onPressed,
    required this.etiqueta,
    this.color = ChatbotColores.azulPrincipal,
    this.fondo,
    this.size = 48,
    this.deshabilitado = false,
  });

  final IconData icono;
  final VoidCallback? onPressed;
  final String etiqueta;
  final Color color;
  final Color? fondo;
  final double size;
  final bool deshabilitado;

  @override
  Widget build(BuildContext context) {
    final bool activo = !deshabilitado && onPressed != null;
    return Tooltip(
      message: etiqueta,
      child: Semantics(
        button: true,
        enabled: activo,
        label: etiqueta,
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            color: fondo ?? color,
            shape: const CircleBorder(),
            elevation: activo ? 2 : 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: activo ? onPressed : null,
              child: Icon(
                icono,
                size: size * 0.46,
                color: activo ? Colors.white : Colors.white54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Burbuja de conversación.
class BurbujaMensaje extends StatelessWidget {
  const BurbujaMensaje({
    super.key,
    required this.mensaje,
    this.onCopiar,
    this.onEscuchar,
  });

  final MensajeChat mensaje;
  final VoidCallback? onCopiar;
  final VoidCallback? onEscuchar;

  @override
  Widget build(BuildContext context) {
    switch (mensaje.rol) {
      case RolMensajeChat.paciente:
        return _burbujaPaciente(context);
      case RolMensajeChat.sistema:
        return _mensajeSistema(context);
      case RolMensajeChat.asistente:
        return _burbujaAsistente(context);
    }
  }

  Widget _burbujaPaciente(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    ChatbotColores.azulPrincipal,
                    ChatbotColores.azulProfundo,
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(
                mensaje.texto,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              horaLocal(mensaje.hora),
              style: const TextStyle(
                fontSize: 11,
                color: ChatbotColores.grisTexto,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _burbujaAsistente(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AsistenteAvatar(size: 30),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(15, 12, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border.all(color: ChatbotColores.borde),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: ChatbotColores.azulPrincipal.withValues(
                        alpha: 0.06,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      mensaje.texto,
                      style: const TextStyle(
                        color: ChatbotColores.texto,
                        fontSize: 14.5,
                        height: 1.45,
                      ),
                    ),
                    if (onCopiar != null || onEscuchar != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          if (onEscuchar != null)
                            _accion(
                              icono: Icons.volume_up_outlined,
                              etiqueta: 'Escuchar respuesta',
                              onTap: onEscuchar!,
                            ),
                          if (onCopiar != null)
                            _accion(
                              icono: Icons.copy_rounded,
                              etiqueta: 'Copiar respuesta',
                              onTap: onCopiar!,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                horaLocal(mensaje.hora),
                style: const TextStyle(
                  fontSize: 11,
                  color: ChatbotColores.grisTexto,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
      ],
    );
  }

  Widget _accion({
    required IconData icono,
    required String etiqueta,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: etiqueta,
      child: Semantics(
        button: true,
        label: etiqueta,
        child: SizedBox(
          width: 48,
          height: 48,
          child: InkResponse(
            onTap: onTap,
            radius: 24,
            child: Center(
              child: Icon(icono, size: 18, color: ChatbotColores.grisTexto),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mensajeSistema(BuildContext context) {
    final bool error = mensaje.esError;
    return Column(
      children: <Widget>[
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: error ? ChatbotColores.rojoSuave : ChatbotColores.fondoSuave,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: error
                  ? ChatbotColores.rojo.withValues(alpha: 0.25)
                  : ChatbotColores.borde,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                error ? Icons.error_outline : Icons.info_outline,
                size: 18,
                color: error
                    ? ChatbotColores.rojo
                    : ChatbotColores.azulPrincipal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mensaje.texto,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: error
                        ? ChatbotColores.rojo
                        : ChatbotColores.grisTexto,
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

/// Indicador discreto mientras el backend prepara la respuesta.
class IndicadorEscribiendo extends StatelessWidget {
  const IndicadorEscribiendo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const AsistenteAvatar(size: 30),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ChatbotColores.borde),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ChatbotColores.azulPrincipal,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'El asistente está escribiendo...',
                style: TextStyle(
                  fontSize: 12.5,
                  color: ChatbotColores.grisTexto,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Etiqueta pequeña reutilizable de las tarjetas.
class EtiquetaTarjeta extends StatelessWidget {
  const EtiquetaTarjeta({
    super.key,
    required this.icono,
    required this.texto,
    this.color = ChatbotColores.azulPrincipal,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icono, size: 17, color: color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Hora local `HH:mm` para las burbujas.
String horaLocal(DateTime fecha) {
  final String hh = fecha.hour.toString().padLeft(2, '0');
  final String mm = fecha.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Copia texto al portapapeles mostrando una confirmación discreta.
Future<void> copiarTexto(BuildContext context, String texto) async {
  await Clipboard.setData(ClipboardData(text: texto));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Respuesta copiada.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
}
