part of 'tarjetas_chatbot.dart';

class _TarjetaPropuesta extends StatelessWidget {
  const _TarjetaPropuesta({
    required this.tarjeta,
    required this.acciones,
    required this.vigente,
    required this.habilitada,
    required this.mensajeId,
    required this.indice,
  });

  final TarjetaPropuestaCita tarjeta;
  final AccionesTarjetasChatbot acciones;
  final bool vigente;
  final bool habilitada;
  final String mensajeId;
  final int indice;

  bool get _completa => tarjeta.datosValidos;

  @override
  Widget build(BuildContext context) {
    final String profesional =
        tarjeta.profesional?.nombre ?? 'Profesional asignado';
    final DateTime? fecha = tarjeta.fecha;

    return _ContenedorTarjeta(
      icono: Icons.event_available_outlined,
      titulo: 'PROPUESTA DE CITA',
      color: ChatbotColores.verdeSuave,
      borde: ChatbotColores.verde.withValues(alpha: 0.22),
      colorTitulo: ChatbotColores.verde,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: ChatbotColores.ambarSuave,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: ChatbotColores.ambar.withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.pending_actions_outlined,
                  size: 14,
                  color: ChatbotColores.ambar,
                ),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Pendiente de confirmación',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ChatbotColores.ambar,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FilaDato(
            icono: Icons.person_outline,
            etiqueta: 'Profesional',
            valor: profesional,
          ),
          _FilaDato(
            icono: Icons.event,
            etiqueta: 'Fecha',
            valor: fecha == null
                ? 'Fecha no disponible'
                : fechaLargaEspanol(fecha),
          ),
          _FilaDato(
            icono: Icons.schedule,
            etiqueta: 'Horario',
            valor: '${tarjeta.horaInicioCorta} – ${tarjeta.horaFinCorta}',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed:
                vigente &&
                    habilitada &&
                    _completa &&
                    acciones.onContinuarAgendamiento != null
                ? () =>
                      acciones.onContinuarAgendamiento!.call(mensajeId, indice)
                : null,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Continuar al agendamiento'),
            style: FilledButton.styleFrom(
              backgroundColor: ChatbotColores.azulProfundo,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            vigente
                ? 'La disponibilidad se verificará otra vez antes de '
                      'registrar la cita.'
                : 'Esta propuesta ya no está vigente. Pide una nueva al '
                      'asistente.',
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: ChatbotColores.grisTexto,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Citas propias
// ---------------------------------------------------------------------------

class _TarjetaCitasPropias extends StatelessWidget {
  const _TarjetaCitasPropias({required this.tarjeta, required this.acciones});

  final TarjetaCitasPropias tarjeta;
  final AccionesTarjetasChatbot acciones;

  @override
  Widget build(BuildContext context) {
    return _ContenedorTarjeta(
      icono: Icons.lock_outline,
      titulo: 'TUS CITAS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (tarjeta.citas.isEmpty)
            const _TextoNeutro(
              'No tienes citas próximas para mostrar con este filtro.',
            )
          else
            for (final CitaPropiaChat cita in tarjeta.citas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _filaCita(cita),
              ),
          if (tarjeta.hayMas == true) ...<Widget>[
            const _TextoNeutro('Hay más citas además de las mostradas.'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: acciones.onNavegar == null
                    ? null
                    : () => acciones.onNavegar!(
                        const TarjetaNavegacion(destino: DestinoChat.misCitas),
                      ),
                child: const Text('Ver todas mis citas'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filaCita(CitaPropiaChat cita) {
    final String? nombre = cita.oftalmologoId == null
        ? null
        : acciones.profesionales[cita.oftalmologoId];
    final int? id = cita.id;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ChatbotColores.fondoSuave,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChatbotColores.borde),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.event,
                      size: 14,
                      color: ChatbotColores.azulPrincipal,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        cita.fecha == null
                            ? 'Fecha no disponible'
                            : fechaCorta(cita.fecha!),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ChatbotColores.texto,
                        ),
                      ),
                    ),
                    ChipEstadoCita(estado: cita.estado, compacto: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  cita.franja,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ChatbotColores.azulProfundo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nombre ?? 'Profesional asignado',
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
          if (acciones.onVerCita != null && id != null && id > 0)
            IconButton(
              tooltip: 'Ver detalle de la cita',
              onPressed: () => acciones.onVerCita!(id),
              icon: const Icon(
                Icons.chevron_right,
                color: ChatbotColores.azulPrincipal,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clínica
// ---------------------------------------------------------------------------

class _TarjetaClinica extends StatelessWidget {
  const _TarjetaClinica({required this.tarjeta});

  final TarjetaClinica tarjeta;

  @override
  Widget build(BuildContext context) {
    if (tarjeta.sinDatos) {
      return const _ContenedorTarjeta(
        icono: Icons.local_hospital_outlined,
        titulo: 'INFORMACIÓN DE LA CLÍNICA',
        child: _TextoNeutro(
          'La clínica todavía no registró información de contacto.',
        ),
      );
    }

    return _ContenedorTarjeta(
      icono: Icons.local_hospital_outlined,
      titulo: 'INFORMACIÓN DE LA CLÍNICA',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (tarjeta.nombre != null)
            _FilaDato(
              icono: Icons.business_outlined,
              etiqueta: 'Nombre',
              valor: tarjeta.nombre!,
            ),
          if (tarjeta.direccion != null)
            _FilaDato(
              icono: Icons.location_on_outlined,
              etiqueta: 'Dirección',
              valor: tarjeta.direccion!,
            ),
          if (tarjeta.telefono != null)
            _FilaDato(
              icono: Icons.call_outlined,
              etiqueta: 'Teléfono',
              valor: tarjeta.telefono!,
            ),
          if (tarjeta.correo != null)
            _FilaDato(
              icono: Icons.mail_outline,
              etiqueta: 'Correo',
              valor: tarjeta.correo!,
            ),
          if (tarjeta.horarioGeneral != null)
            _FilaDato(
              icono: Icons.schedule,
              etiqueta: 'Horario',
              valor: tarjeta.horarioGeneral!,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navegación
// ---------------------------------------------------------------------------

class _TarjetaNavegacion extends StatelessWidget {
  const _TarjetaNavegacion({required this.tarjeta, required this.acciones});

  final TarjetaNavegacion tarjeta;
  final AccionesTarjetasChatbot acciones;

  @override
  Widget build(BuildContext context) {
    final bool destructiva =
        tarjeta.destino == DestinoChat.reprogramarCita ||
        tarjeta.destino == DestinoChat.cancelarCita;

    return _ContenedorTarjeta(
      icono: Icons.alt_route,
      titulo: 'ACCIÓN DISPONIBLE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _iconoDestino(tarjeta.destino),
                size: 22,
                color: destructiva
                    ? ChatbotColores.ambar
                    : ChatbotColores.azulPrincipal,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  tarjeta.destino.etiqueta,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: ChatbotColores.texto,
                  ),
                ),
              ),
            ],
          ),
          if (destructiva) ...<Widget>[
            const SizedBox(height: 6),
            const _TextoNeutro(
              'Se abrirá el detalle de la cita. Reprogramar o cancelar exige '
              'tu confirmación explícita en el módulo de citas.',
            ),
          ],
          if (!tarjeta.accionDisponible) ...<Widget>[
            const SizedBox(height: 6),
            const _TextoNeutro(
              'El asistente no indicó una cita válida para esta acción.',
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: tarjeta.accionDisponible && acciones.onNavegar != null
                ? () => acciones.onNavegar!(tarjeta)
                : null,
            icon: const Icon(Icons.open_in_new, size: 17),
            label: Text(destructiva ? 'Abrir gestión de la cita' : 'Abrir'),
            style: OutlinedButton.styleFrom(
              foregroundColor: destructiva
                  ? ChatbotColores.ambar
                  : ChatbotColores.azulProfundo,
              side: BorderSide(
                color:
                    (destructiva
                            ? ChatbotColores.ambar
                            : ChatbotColores.azulProfundo)
                        .withValues(alpha: 0.35),
              ),
              minimumSize: const Size(48, 48),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconoDestino(DestinoChat destino) {
    return switch (destino) {
      DestinoChat.catalogo => Icons.menu_book_outlined,
      DestinoChat.agendarCita => Icons.add_circle_outline,
      DestinoChat.misCitas => Icons.list_alt,
      DestinoChat.detalleCita => Icons.event_note_outlined,
      DestinoChat.reprogramarCita => Icons.update,
      DestinoChat.cancelarCita => Icons.event_busy_outlined,
      DestinoChat.desconocido => Icons.help_outline,
    };
  }
}

// ---------------------------------------------------------------------------
// Desconocidas
// ---------------------------------------------------------------------------

class _TarjetaDesconocida extends StatelessWidget {
  const _TarjetaDesconocida();

  @override
  Widget build(BuildContext context) {
    return const _ContenedorTarjeta(
      icono: Icons.info_outline,
      titulo: 'INFORMACIÓN',
      color: ChatbotColores.fondoSuave,
      child: _TextoNeutro(
        'Este contenido no está disponible en esta versión de la aplicación.',
      ),
    );
  }
}

class _TextoNeutro extends StatelessWidget {
  const _TextoNeutro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11.5,
        height: 1.4,
        color: ChatbotColores.grisTexto,
      ),
    );
  }
}

String _iniciales(String nombre) {
  final List<String> partes = nombre
      .trim()
      .split(RegExp(r'\s+'))
      .where((String p) => p.isNotEmpty)
      .toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first[0].toUpperCase();
  return (partes.first[0] + partes[1][0]).toUpperCase();
}
