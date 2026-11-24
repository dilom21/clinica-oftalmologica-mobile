part of 'tarjetas_chatbot.dart';

class _TarjetaServicios extends StatelessWidget {
  const _TarjetaServicios({required this.tarjeta, required this.acciones});

  final TarjetaServicios tarjeta;
  final AccionesTarjetasChatbot acciones;

  @override
  Widget build(BuildContext context) {
    return _ContenedorTarjeta(
      icono: Icons.menu_book_outlined,
      titulo: 'SERVICIOS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (tarjeta.servicios.isEmpty)
            const _TextoNeutro('No hay servicios disponibles en esta consulta.')
          else
            for (int i = 0; i < tarjeta.servicios.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 16, color: ChatbotColores.borde),
              _servicio(tarjeta.servicios[i]),
            ],
          if (tarjeta.servicios.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            if (tarjeta.hayMas == true)
              const _TextoNeutro('Hay más servicios disponibles.')
            else if (tarjeta.hayMas == null)
              const _TextoNeutro('La lista puede no incluir todo el catálogo.'),
            if (acciones.onVerCatalogo != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: acciones.onVerCatalogo,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Ver catálogo completo'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _servicio(ServicioChat servicio) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                servicio.nombre,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: ChatbotColores.texto,
                ),
              ),
              if (servicio.descripcion != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  servicio.descripcion!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: ChatbotColores.grisTexto,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _chip(
                    texto: servicio.precioTexto,
                    color: servicio.precio == null
                        ? ChatbotColores.grisSuave
                        : ChatbotColores.azulProfundo,
                  ),
                  _chip(
                    texto: servicio.duracionTexto,
                    color: ChatbotColores.grisTexto,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (acciones.onConsultarServicio != null) ...<Widget>[
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => acciones.onConsultarServicio!(servicio),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 48),
            ),
            child: const Text('Consultar'),
          ),
        ],
      ],
    );
  }

  Widget _chip({required String texto, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profesionales
// ---------------------------------------------------------------------------

class _TarjetaProfesionales extends StatelessWidget {
  const _TarjetaProfesionales({required this.tarjeta, required this.acciones});

  final TarjetaProfesionales tarjeta;
  final AccionesTarjetasChatbot acciones;

  @override
  Widget build(BuildContext context) {
    return _ContenedorTarjeta(
      icono: Icons.medical_services_outlined,
      titulo: 'PROFESIONALES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (tarjeta.profesionales.isEmpty)
            const _TextoNeutro(
              'No hay profesionales disponibles en esta consulta.',
            )
          else
            for (final ProfesionalChat profesional in tarjeta.profesionales)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    _AvatarProfesional(nombre: profesional.nombre),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            profesional.nombre,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: ChatbotColores.texto,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profesional.especialidad ??
                                'Especialidad no registrada',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: ChatbotColores.grisTexto,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (acciones.onVerDisponibilidad != null)
                      TextButton(
                        onPressed: () =>
                            acciones.onVerDisponibilidad!(profesional),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Disponibilidad'),
                      ),
                  ],
                ),
              ),
          if (tarjeta.hayMas == true)
            const _TextoNeutro('Hay más profesionales disponibles.'),
        ],
      ),
    );
  }
}

class _AvatarProfesional extends StatelessWidget {
  const _AvatarProfesional({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final String iniciales = _iniciales(nombre);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ChatbotColores.azulPrincipal.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Text(
        iniciales,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: ChatbotColores.azulProfundo,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Disponibilidad
// ---------------------------------------------------------------------------

class _TarjetaDisponibilidad extends StatelessWidget {
  const _TarjetaDisponibilidad({
    required this.tarjeta,
    required this.acciones,
    required this.vigente,
  });

  final TarjetaDisponibilidad tarjeta;
  final AccionesTarjetasChatbot acciones;
  final bool vigente;

  @override
  Widget build(BuildContext context) {
    final String? nombre = tarjeta.profesional?.nombre;
    final DateTime? fecha = tarjeta.fecha;

    return _ContenedorTarjeta(
      icono: Icons.schedule_outlined,
      titulo: 'HORARIOS DISPONIBLES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FilaDato(
            icono: Icons.person_outline,
            etiqueta: 'Profesional',
            valor: nombre ?? 'Profesional no especificado',
          ),
          _FilaDato(
            icono: Icons.event,
            etiqueta: 'Fecha',
            valor: fecha == null
                ? 'Fecha no disponible'
                : fechaLargaEspanol(fecha),
          ),
          if (tarjeta.franja != FranjaChat.desconocida)
            _FilaDato(
              icono: Icons.wb_twilight,
              etiqueta: 'Franja',
              valor: tarjeta.franja.etiqueta,
            ),
          const SizedBox(height: 6),
          if (tarjeta.intervalos.isEmpty)
            const _TextoNeutro('No hay intervalos libres para esta fecha.')
          else ...<Widget>[
            const Text(
              'Selecciona un horario',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ChatbotColores.azulProfundo,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints limites) {
                final double ancho = (limites.maxWidth - 16) / 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final IntervaloChat intervalo in tarjeta.intervalos)
                      SizedBox(
                        width: ancho.clamp(86.0, 140.0),
                        child: _HorarioChip(
                          intervalo: intervalo,
                          habilitado: vigente,
                          onTap: vigente
                              ? () => acciones.onSeleccionarHorario?.call(
                                  tarjeta,
                                  intervalo,
                                )
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (!vigente) ...<Widget>[
            const SizedBox(height: 8),
            const _TextoNeutro(
              'Esta disponibilidad es de una consulta anterior. Pide al '
              'asistente los horarios actuales antes de elegir.',
            ),
          ],
        ],
      ),
    );
  }
}

class _HorarioChip extends StatelessWidget {
  const _HorarioChip({
    required this.intervalo,
    required this.habilitado,
    required this.onTap,
  });

  final IntervaloChat intervalo;
  final bool habilitado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: habilitado,
      enabled: habilitado,
      label: habilitado
          ? 'Seleccionar horario de las ${intervalo.inicioCorto}'
          : 'Horario de las ${intervalo.inicioCorto}, no vigente',
      child: Material(
        color: habilitado ? Colors.white : ChatbotColores.fondoSuave,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: habilitado ? onTap : null,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: habilitado
                    ? ChatbotColores.borde
                    : ChatbotColores.grisSuave.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              intervalo.inicioCorto,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: habilitado
                    ? ChatbotColores.azulProfundo
                    : ChatbotColores.grisTexto,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Propuesta de cita
// ---------------------------------------------------------------------------
