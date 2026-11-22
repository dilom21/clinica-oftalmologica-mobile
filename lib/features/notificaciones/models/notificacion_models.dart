class DispositivoPush {
  const DispositivoPush({
    required this.id,
    required this.plataforma,
    required this.activo,
  });

  final int id;
  final String plataforma;
  final bool activo;

  factory DispositivoPush.fromJson(Map<String, dynamic> json) =>
      DispositivoPush(
        id: json['id'] as int,
        plataforma: json['plataforma'] as String,
        activo: json['activo'] as bool,
      );
}

class NotificacionPaciente {
  const NotificacionPaciente({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.cuerpo,
    required this.leida,
    required this.fechaCreacion,
    this.datos,
    this.citaId,
  });

  final int id;
  final String tipo;
  final String titulo;
  final String cuerpo;
  final Map<String, dynamic>? datos;
  final int? citaId;
  final bool leida;
  final DateTime fechaCreacion;

  factory NotificacionPaciente.fromJson(Map<String, dynamic> json) {
    final datos = json['datos'];
    return NotificacionPaciente(
      id: json['id'] as int,
      tipo: json['tipo'] as String,
      titulo: json['titulo'] as String,
      cuerpo: json['cuerpo'] as String,
      datos: datos is Map<String, dynamic> ? datos : null,
      citaId: json['cita_id'] as int?,
      leida: json['leida'] as bool,
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
    );
  }

  int? get citaIdNavegable {
    final valor = citaId ?? datos?['cita_id'];
    if (valor is int && valor > 0) return valor;
    if (valor is String) return int.tryParse(valor)?.takeIfPositive;
    return null;
  }
}

extension on int? {
  int? get takeIfPositive => this != null && this! > 0 ? this : null;
}

class BandejaNotificaciones {
  const BandejaNotificaciones({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<NotificacionPaciente> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  factory BandejaNotificaciones.fromJson(Map<String, dynamic> json) =>
      BandejaNotificaciones(
        items: (json['items'] as List<dynamic>)
            .map(
              (item) =>
                  NotificacionPaciente.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
        total: json['total'] as int,
        page: json['page'] as int,
        pageSize: json['page_size'] as int,
        totalPages: json['total_pages'] as int,
      );
}

class PreferenciasNotificacion {
  const PreferenciasNotificacion({
    required this.pushHabilitado,
    required this.citasCreadas,
    required this.citasConfirmadas,
    required this.citasReprogramadas,
    required this.citasCanceladas,
    required this.recordatorios,
  });

  final bool pushHabilitado;
  final bool citasCreadas;
  final bool citasConfirmadas;
  final bool citasReprogramadas;
  final bool citasCanceladas;
  final bool recordatorios;

  factory PreferenciasNotificacion.fromJson(Map<String, dynamic> json) =>
      PreferenciasNotificacion(
        pushHabilitado: json['push_habilitado'] as bool,
        citasCreadas: json['citas_creadas'] as bool,
        citasConfirmadas: json['citas_confirmadas'] as bool,
        citasReprogramadas: json['citas_reprogramadas'] as bool,
        citasCanceladas: json['citas_canceladas'] as bool,
        recordatorios: json['recordatorios'] as bool,
      );
}
