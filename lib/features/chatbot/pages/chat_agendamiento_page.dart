import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../../citas/models/cita_models.dart';
import '../../citas/models/preseleccion_cita.dart';
import '../../citas/pages/agendar_cita_view.dart';
import '../../citas/services/agenda_service.dart';
import '../../citas/widgets/citas_ui.dart';
import '../../perfil_paciente/services/paciente_service.dart';
import 'chat_citas_page.dart';

/// Envoltura del flujo CU10 reutilizado desde el chatbot.
///
/// No duplica el formulario: presenta [AgendarCitaView] con una posible
/// [PreseleccionCita] y mantiene la conversación del asistente intacta debajo
/// de esta ruta.
class ChatAgendamientoPage extends StatelessWidget {
  const ChatAgendamientoPage({
    super.key,
    this.preseleccion,
    this.clinica,
    this.agendaService,
    this.pacienteService,
    this.onSesionInvalida,
    this.onCitasCambiadas,
  });

  final PreseleccionCita? preseleccion;
  final ClinicaSesion? clinica;
  final AgendaService? agendaService;
  final PacienteService? pacienteService;
  final Future<void> Function()? onSesionInvalida;
  final VoidCallback? onCitasCambiadas;

  void _abrirMisCitas(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatCitasPage(
          clinica: clinica,
          agendaService: agendaService,
          pacienteService: pacienteService,
          onSesionInvalida: onSesionInvalida,
          onCitasCambiadas: onCitasCambiadas,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FF),
      appBar: AppBar(
        title: const Text('Agendar cita'),
        backgroundColor: const Color(0xFFF4F9FF),
        foregroundColor: CitasColores.azulProfundo,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: SafeArea(
        child: AgendarCitaView(
          preseleccion: preseleccion,
          agendaService: agendaService,
          pacienteService: pacienteService,
          clinica: clinica,
          onSesionInvalida: onSesionInvalida,
          onVerMisCitas: () => _abrirMisCitas(context),
          onCitaCreada: (Cita cita) {
            onCitasCambiadas?.call();
          },
        ),
      ),
    );
  }
}
