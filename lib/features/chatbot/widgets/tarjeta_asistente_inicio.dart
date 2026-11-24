import 'package:flutter/material.dart';

import 'chatbot_ui.dart';

/// Acceso premium al asistente virtual desde Inicio.
///
/// No realiza peticiones ni inicializa el micrófono: solo navega cuando el
/// paciente elige "Conversar" o "Hablar".
class TarjetaAsistenteInicio extends StatelessWidget {
  const TarjetaAsistenteInicio({super.key, this.onConversar, this.onHablar});

  final VoidCallback? onConversar;
  final VoidCallback? onHablar;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('inicio-asistente'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFEAF8FF),
            Color(0xFFD8F0FD),
            Color(0xFFC7EAFB),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: ChatbotColores.azulPrincipal.withValues(alpha: 0.13),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -46,
              right: -32,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
            Positioned(
              bottom: -58,
              right: 42,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ChatbotColores.celeste.withValues(alpha: 0.18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      const AsistenteAvatar(size: 54),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: ChatbotColores.verde,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Flexible(
                                  child: Text(
                                    'ASISTENTE VIRTUAL',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      letterSpacing: 0.9,
                                      fontWeight: FontWeight.w800,
                                      color: ChatbotColores.azulProfundo,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              '¿En qué podemos ayudarte hoy?',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                                color: ChatbotColores.azulProfundo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Consulta servicios, profesionales, disponibilidad y tus '
                    'citas. También puedes conversar por voz.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: ChatbotColores.grisTexto,
                    ),
                  ),
                  const SizedBox(height: 15),
                  LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints limites) {
                      final double anchoBoton = limites.maxWidth >= 300
                          ? (limites.maxWidth - 10) / 2
                          : limites.maxWidth;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: <Widget>[
                          SizedBox(
                            width: anchoBoton,
                            child: FilledButton.icon(
                              key: const Key('inicio-asistente-conversar'),
                              onPressed: onConversar,
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                              ),
                              label: const Text('Conversar'),
                              style: FilledButton.styleFrom(
                                backgroundColor: ChatbotColores.azulProfundo,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: anchoBoton,
                            child: OutlinedButton.icon(
                              key: const Key('inicio-asistente-hablar'),
                              onPressed: onHablar,
                              icon: const Icon(Icons.mic_none, size: 19),
                              label: const Text('Hablar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ChatbotColores.azulProfundo,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.82,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                side: BorderSide(
                                  color: ChatbotColores.azulPrincipal
                                      .withValues(alpha: 0.35),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
