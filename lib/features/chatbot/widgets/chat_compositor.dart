import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chatbot_ui.dart';

/// Compositor del chat: campo multilínea, límite del Backend, envío y acceso a
/// la modalidad de voz.
class ChatCompositor extends StatelessWidget {
  const ChatCompositor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.puedeEnviar,
    required this.maxCaracteres,
    required this.onEnviar,
    required this.onVoz,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool puedeEnviar;
  final int maxCaracteres;
  final VoidCallback onEnviar;
  final VoidCallback onVoz;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: ChatbotColores.borde)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: ChatbotColores.azulProfundo.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (BuildContext context, TextEditingValue valor, _) {
            final bool vacio = valor.text.trim().isEmpty;
            final bool habilitado = !vacio && puedeEnviar;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: const Key('chatbot-compositor'),
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: maxCaracteres,
                        inputFormatters: <TextInputFormatter>[
                          LengthLimitingTextInputFormatter(maxCaracteres),
                        ],
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'Escribe tu consulta...',
                          hintStyle: const TextStyle(
                            fontSize: 13.5,
                            color: ChatbotColores.grisTexto,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: ChatbotColores.fondoSuave,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: ChatbotColores.borde,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: ChatbotColores.borde,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: ChatbotColores.azulPrincipal,
                              width: 1.5,
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: ChatbotColores.texto,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Hablar con el asistente',
                      child: Semantics(
                        button: true,
                        label: 'Hablar con el asistente',
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Material(
                            color: ChatbotColores.celesteMuySuave,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: puedeEnviar ? onVoz : null,
                              child: const Icon(
                                Icons.mic_none_rounded,
                                size: 22,
                                color: ChatbotColores.azulProfundo,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Enviar mensaje',
                      child: Semantics(
                        button: true,
                        enabled: habilitado,
                        label: 'Enviar mensaje',
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Material(
                            shape: const CircleBorder(),
                            color: habilitado
                                ? ChatbotColores.azulProfundo
                                : ChatbotColores.grisSuave.withValues(
                                    alpha: 0.35,
                                  ),
                            child: InkWell(
                              key: const Key('chatbot-enviar'),
                              customBorder: const CircleBorder(),
                              onTap: habilitado ? onEnviar : null,
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (valor.text.length > 900)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${valor.text.length}/$maxCaracteres',
                        style: TextStyle(
                          fontSize: 10,
                          color: valor.text.length >= maxCaracteres
                              ? ChatbotColores.rojo
                              : ChatbotColores.grisSuave,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
