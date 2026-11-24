import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../../citas/pages/mis_citas_view.dart';
import '../../citas/services/agenda_service.dart';
import '../../citas/widgets/citas_ui.dart';
import '../../perfil_paciente/services/paciente_service.dart';
import 'chat_agendamiento_page.dart';

/// Listado CU10 reutilizado desde el chatbot.
///
/// La cita se abre en el detalle real, donde reprogramar/cancelar exigen las
/// confirmaciones existentes. Nunca se ejecuta una operación destructiva
/// directamente desde una tarjeta del asistente.
class ChatCitasPage extends StatefulWidget {
  const ChatCitasPage({
    super.key,
    this.clinica,
    this.agendaService,
    this.pacienteService,
    this.onSesionInvalida,
    this.onCitasCambiadas,
  });

  final ClinicaSesion? clinica;
  final AgendaService? agendaService;
  final PacienteService? pacienteService;
  final Future<void> Function()? onSesionInvalida;
  final VoidCallback? onCitasCambiadas;

  @override
  State<ChatCitasPage> createState() => _ChatCitasPageState();
}

class _ChatCitasPageState extends State<ChatCitasPage> {
  final GlobalKey<MisCitasViewState> _listaKey = GlobalKey<MisCitasViewState>();

  Future<void> _abrirAgendar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatAgendamientoPage(
          clinica: widget.clinica,
          agendaService: widget.agendaService,
          pacienteService: widget.pacienteService,
          onSesionInvalida: widget.onSesionInvalida,
          onCitasCambiadas: widget.onCitasCambiadas,
        ),
      ),
    );

    if (!mounted) return;
    // La cita pudo registrarse: el listado se refresca con datos reales.
    await _listaKey.currentState?.cargar(silencioso: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FF),
      appBar: AppBar(
        title: const Text('Mis citas'),
        backgroundColor: const Color(0xFFF4F9FF),
        foregroundColor: CitasColores.azulProfundo,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: SafeArea(
        child: MisCitasView(
          key: _listaKey,
          agendaService: widget.agendaService,
          clinica: widget.clinica,
          onSesionInvalida: widget.onSesionInvalida,
          onAgendarCita: _abrirAgendar,
          onCitasCambiadas: widget.onCitasCambiadas,
        ),
      ),
    );
  }
}
