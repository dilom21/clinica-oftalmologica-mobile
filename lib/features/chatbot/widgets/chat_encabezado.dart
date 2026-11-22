import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import 'chatbot_ui.dart';

/// Encabezado del chat escrito: regreso, identidad del asistente, clínica real
/// y menú de opciones.
class ChatEncabezado extends StatelessWidget {
  const ChatEncabezado({
    super.key,
    required this.clinica,
    required this.onVolver,
    required this.onOpcion,
  });

  final ClinicaSesion? clinica;
  final VoidCallback onVolver;
  final ValueChanged<String> onOpcion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: const Border(bottom: BorderSide(color: ChatbotColores.borde)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: ChatbotColores.azulProfundo.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const Key('chatbot-volver'),
            tooltip: 'Volver a Inicio',
            onPressed: onVolver,
            icon: const Icon(
              Icons.arrow_back_ios_new,
              size: 20,
              color: ChatbotColores.azulProfundo,
            ),
          ),
          const AsistenteAvatar(size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Asistente virtual',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ChatbotColores.azulProfundo,
                  ),
                ),
                Text(
                  clinica?.etiqueta ?? 'Orientación administrativa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ChatbotColores.grisTexto,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('chatbot-menu'),
            tooltip: 'Opciones del asistente',
            onSelected: onOpcion,
            icon: const Icon(
              Icons.more_vert,
              color: ChatbotColores.azulProfundo,
            ),
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'nueva',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh),
                      title: Text('Nueva conversación'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'privacidad',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.privacy_tip_outlined),
                      title: Text('Privacidad y alcance'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'voz',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.record_voice_over_outlined),
                      title: Text('Configuración de voz'),
                    ),
                  ),
                ],
          ),
        ],
      ),
    );
  }
}
