import 'package:flutter/material.dart';

import '../../citas/models/cita_models.dart';
import '../../citas/widgets/citas_ui.dart';
import '../models/chatbot_models.dart';
import 'chatbot_ui.dart';

part 'tarjetas_chatbot_publicas.dart';
part 'tarjetas_chatbot_privadas.dart';

/// Acciones que la pantalla del chat conecta con CU10/CU38.
///
/// Las tarjetas no navegan por sí solas ni ejecutan operaciones destructivas:
/// solo notifican la intención al contenedor, que aplica las comprobaciones
/// reales de cada módulo.
class AccionesTarjetasChatbot {
  const AccionesTarjetasChatbot({
    this.onVerCatalogo,
    this.onConsultarServicio,
    this.onVerDisponibilidad,
    this.onSeleccionarHorario,
    this.onContinuarAgendamiento,
    this.onVerCita,
    this.onNavegar,
    this.profesionales = const <int, String>{},
  });

  final VoidCallback? onVerCatalogo;
  final void Function(ServicioChat servicio)? onConsultarServicio;
  final void Function(ProfesionalChat profesional)? onVerDisponibilidad;
  final void Function(TarjetaDisponibilidad disponibilidad, IntervaloChat)?
  onSeleccionarHorario;
  final void Function(String mensajeId, int indiceTarjeta)?
  onContinuarAgendamiento;
  final void Function(int citaId)? onVerCita;
  final void Function(TarjetaNavegacion navegacion)? onNavegar;

  /// Nombres reales resueltos con CU09 (`GET /agenda-citas/oftalmologos`).
  final Map<int, String> profesionales;
}

/// Renderiza las siete tarjetas del contrato y una tarjeta neutra para
/// discriminadores desconocidos.
class TarjetasChatbot extends StatelessWidget {
  const TarjetasChatbot({
    super.key,
    required this.tarjetas,
    required this.acciones,
    this.vigente = true,
    this.mensajeId = '',
    this.propuestaVigente,
    this.accionesHabilitadas = true,
  });

  final List<TarjetaChatbot> tarjetas;
  final AccionesTarjetasChatbot acciones;

  /// Disponibilidad de la última respuesta. Las propuestas usan su propia
  /// identidad/vigencia, independiente de la posición del mensaje.
  final bool vigente;
  final String mensajeId;
  final bool Function(int indice)? propuestaVigente;
  final bool accionesHabilitadas;

  @override
  Widget build(BuildContext context) {
    if (tarjetas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (indice, tarjeta) in tarjetas.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: switch (tarjeta) {
              TarjetaServicios() => _TarjetaServicios(
                tarjeta: tarjeta,
                acciones: acciones,
              ),
              TarjetaProfesionales() => _TarjetaProfesionales(
                tarjeta: tarjeta,
                acciones: acciones,
              ),
              TarjetaDisponibilidad() => _TarjetaDisponibilidad(
                tarjeta: tarjeta,
                acciones: acciones,
                vigente: vigente,
              ),
              TarjetaPropuestaCita() => _TarjetaPropuesta(
                tarjeta: tarjeta,
                acciones: acciones,
                vigente: propuestaVigente?.call(indice) ?? vigente,
                habilitada: accionesHabilitadas,
                mensajeId: mensajeId,
                indice: indice,
              ),
              TarjetaCitasPropias() => _TarjetaCitasPropias(
                tarjeta: tarjeta,
                acciones: acciones,
              ),
              TarjetaClinica() => _TarjetaClinica(tarjeta: tarjeta),
              TarjetaNavegacion() => _TarjetaNavegacion(
                tarjeta: tarjeta,
                acciones: acciones,
              ),
              TarjetaDesconocida() => const _TarjetaDesconocida(),
            },
          ),
      ],
    );
  }
}

class _ContenedorTarjeta extends StatelessWidget {
  const _ContenedorTarjeta({
    required this.icono,
    required this.titulo,
    required this.child,
    this.color = Colors.white,
    this.borde = ChatbotColores.borde,
    this.colorTitulo = ChatbotColores.azulPrincipal,
  });

  final IconData icono;
  final String titulo;
  final Widget child;
  final Color color;
  final Color borde;
  final Color colorTitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borde),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: ChatbotColores.azulPrincipal.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          EtiquetaTarjeta(icono: icono, texto: titulo, color: colorTitulo),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, size: 15, color: ChatbotColores.azulPrincipal),
          const SizedBox(width: 7),
          SizedBox(
            width: 82,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 11.5,
                color: ChatbotColores.grisTexto,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: ChatbotColores.texto,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Servicios
// ---------------------------------------------------------------------------
