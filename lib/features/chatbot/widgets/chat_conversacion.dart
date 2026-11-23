import 'package:flutter/material.dart';

import '../models/chatbot_models.dart';
import 'chatbot_ui.dart';
import 'tarjetas_chatbot.dart';

/// Lista de mensajes y tarjetas de la conversación activa.
class ChatConversacion extends StatelessWidget {
  const ChatConversacion({
    super.key,
    required this.mensajes,
    required this.enviando,
    required this.tarjetasInvalidas,
    required this.propuestaVigente,
    required this.puedeReintentar,
    required this.scrollController,
    required this.acciones,
    required this.puedeEscuchar,
    required this.onCopiar,
    required this.onEscuchar,
    required this.onReintentar,
  });

  final List<MensajeChat> mensajes;
  final bool enviando;
  final bool tarjetasInvalidas;
  final bool Function(String mensajeId, int indice) propuestaVigente;
  final bool puedeReintentar;
  final ScrollController scrollController;
  final AccionesTarjetasChatbot acciones;
  final bool Function(MensajeChat mensaje) puedeEscuchar;
  final void Function(MensajeChat mensaje) onCopiar;
  final void Function(MensajeChat mensaje) onEscuchar;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final int ultimoAsistente = _ultimoIndiceAsistente();

    return ListView.builder(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: mensajes.length + (enviando ? 1 : 0),
      itemBuilder: (BuildContext context, int indice) {
        if (indice >= mensajes.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: IndicadorEscribiendo(),
          );
        }

        final MensajeChat mensaje = mensajes[indice];
        final bool esUltimoAsistente = indice == ultimoAsistente;
        final bool escuchar =
            mensaje.rol == RolMensajeChat.asistente && puedeEscuchar(mensaje);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              BurbujaMensaje(
                mensaje: mensaje,
                onCopiar: mensaje.rol == RolMensajeChat.asistente
                    ? () => onCopiar(mensaje)
                    : null,
                onEscuchar: escuchar ? () => onEscuchar(mensaje) : null,
              ),
              if (mensaje.esError && mensaje.textoReintentable != null)
                Center(
                  child: TextButton.icon(
                    key: const Key('chatbot-reintentar'),
                    onPressed: puedeReintentar ? onReintentar : null,
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('Reintentar'),
                  ),
                ),
              if (mensaje.rol == RolMensajeChat.asistente &&
                  mensaje.tarjetas.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 2),
                  child: TarjetasChatbot(
                    tarjetas: mensaje.tarjetas,
                    mensajeId: mensaje.id,
                    propuestaVigente: (indice) =>
                        propuestaVigente(mensaje.id, indice),
                    accionesHabilitadas: !enviando,
                    vigente:
                        esUltimoAsistente && !tarjetasInvalidas && !enviando,
                    acciones: acciones,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  int _ultimoIndiceAsistente() {
    for (int i = mensajes.length - 1; i >= 0; i--) {
      if (mensajes[i].rol == RolMensajeChat.asistente) return i;
    }
    return -1;
  }
}
