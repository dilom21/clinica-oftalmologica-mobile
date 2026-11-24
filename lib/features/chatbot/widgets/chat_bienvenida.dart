import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import 'chatbot_ui.dart';

/// Bienvenida del chat inicial: avatar central, capacidades y sugerencias.
class ChatBienvenida extends StatelessWidget {
  const ChatBienvenida({
    super.key,
    required this.clinica,
    required this.aviso,
    required this.puedeEnviar,
    required this.onSugerencia,
    required this.onPrivacidad,
  });

  final ClinicaSesion? clinica;
  final String? aviso;
  final bool puedeEnviar;
  final ValueChanged<String> onSugerencia;
  final VoidCallback onPrivacidad;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      children: <Widget>[
        if (aviso != null) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ChatbotColores.ambarSuave,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ChatbotColores.ambar.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.schedule,
                  size: 18,
                  color: ChatbotColores.ambar,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    aviso!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: ChatbotColores.grisTexto,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        const Center(child: AsistenteAvatar(size: 74, conHalo: true)),
        const SizedBox(height: 2),
        const Text(
          'Hola',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ChatbotColores.grisTexto,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Soy tu asistente virtual',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 23,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: ChatbotColores.azulProfundo,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          clinica == null
              ? 'Puedo ayudarte a agendar una cita, revisar tus citas y '
                    'consultar servicios, profesionales y disponibilidad.'
              : 'Puedo ayudarte con los servicios y la agenda de '
                    '${clinica!.etiqueta}, además de tus propias citas.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.8,
            height: 1.45,
            color: ChatbotColores.grisTexto,
          ),
        ),
        const SizedBox(height: 18),
        for (final SugerenciaChat sugerencia in sugerenciasChat) ...<Widget>[
          _SugerenciaTile(
            sugerencia: sugerencia,
            habilitada: puedeEnviar,
            onTap: () => onSugerencia(sugerencia.consulta),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ChatbotColores.borde),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: ChatbotColores.azulPrincipal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Asistente administrativo. No realiza diagnósticos '
                      'médicos.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: ChatbotColores.grisTexto,
                      ),
                    ),
                    TextButton(
                      onPressed: onPrivacidad,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 48),
                        alignment: Alignment.centerLeft,
                      ),
                      child: const Text(
                        'Privacidad y tratamiento de datos',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ChatbotColores.azulPrincipal,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sugerencia rápida del chat inicial. Enviar siempre consulta al Backend.
class SugerenciaChat {
  const SugerenciaChat({
    required this.icono,
    required this.titulo,
    required this.consulta,
  });

  final IconData icono;
  final String titulo;
  final String consulta;
}

const List<SugerenciaChat> sugerenciasChat = <SugerenciaChat>[
  SugerenciaChat(
    icono: Icons.add_circle_outline,
    titulo: 'Quiero agendar una cita',
    consulta: 'Quiero agendar una cita.',
  ),
  SugerenciaChat(
    icono: Icons.event_note_outlined,
    titulo: 'Consultar mis citas',
    consulta: 'Quiero consultar mis citas.',
  ),
  SugerenciaChat(
    icono: Icons.menu_book_outlined,
    titulo: 'Servicios y precios',
    consulta: 'Quiero ver los servicios y precios disponibles.',
  ),
  SugerenciaChat(
    icono: Icons.schedule_outlined,
    titulo: 'Consultar disponibilidad',
    consulta: 'Quiero consultar la disponibilidad médica.',
  ),
  SugerenciaChat(
    icono: Icons.local_hospital_outlined,
    titulo: 'Información de la clínica',
    consulta: 'Quiero información de la clínica.',
  ),
];

class _SugerenciaTile extends StatelessWidget {
  const _SugerenciaTile({
    required this.sugerencia,
    required this.habilitada,
    required this.onTap,
  });

  final SugerenciaChat sugerencia;
  final bool habilitada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: habilitada,
      label: sugerencia.titulo,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: habilitada ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: ChatbotColores.borde),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: ChatbotColores.azulPrincipal.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: ChatbotColores.celesteMuySuave,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    sugerencia.icono,
                    size: 18,
                    color: ChatbotColores.azulProfundo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sugerencia.titulo,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ChatbotColores.texto,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: ChatbotColores.grisSuave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
